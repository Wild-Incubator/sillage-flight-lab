require "stringio"
require "set"
require "zip"

module FlySight
  class ImportService
    FilePayload = Data.define(:path, :filename, :content, :content_type)
    SessionFile = Data.define(:format, :track, :sensor, :csv)

    def initialize(uploaded_files)
      @uploaded_files = Array(uploaded_files).compact_blank
    end

    def call
      raise Error, "Sélectionne un fichier ZIP FlySight ou des fichiers CSV." if @uploaded_files.empty?

      uploaded_payloads = read_uploaded_payloads
      flight_import = FlightImport.create!(
        source_filename: uploaded_payloads.map(&:filename).join(", "),
        status: "pending"
      )
      attach_sources(flight_import, uploaded_payloads)

      flight_import.update!(status: "processing")

      sessions = detect_sessions(expand_archives(uploaded_payloads))
      raise Error, "Aucune session FlySight exploitable trouvée." if sessions.empty?

      parsed_sessions = sessions.map { |session| parse_session(session) }

      FlightImport.transaction do
        parsed_sessions.each.with_index(1) do |parsed_session, index|
          create_jump!(flight_import, parsed_session, index)
        end

        first = parsed_sessions.first
        flight_import.update!(
          status: "imported",
          device_id: metadata_value(first, "DEVICE_ID"),
          firmware_version: metadata_value(first, "FIRMWARE_VER"),
          session_id: metadata_value(first, "SESSION_ID"),
          log_started_at: first.started_at,
          details: {
            "format" => parsed_sessions.map(&:format).uniq.join(", "),
            "sessions_count" => parsed_sessions.size,
            "sessions" => parsed_sessions.map(&:metadata)
          }
        )
      end

      flight_import
    rescue StandardError => exception
      flight_import&.update(status: "failed", error_message: exception.message)
      raise
    end

    private

    def read_uploaded_payloads
      @uploaded_files.map do |uploaded|
        uploaded.rewind if uploaded.respond_to?(:rewind)
        content = uploaded.read
        uploaded.rewind if uploaded.respond_to?(:rewind)

        FilePayload.new(
          path: uploaded.original_filename,
          filename: uploaded.original_filename,
          content: content,
          content_type: uploaded.respond_to?(:content_type) ? uploaded.content_type : "application/octet-stream"
        )
      end
    end

    def attach_sources(flight_import, payloads)
      payloads.each do |payload|
        flight_import.source_files.attach(
          io: StringIO.new(payload.content),
          filename: payload.filename,
          content_type: payload.content_type.presence || "application/octet-stream"
        )
      end
    end

    def expand_archives(payloads)
      payloads.flat_map do |payload|
        if zip?(payload)
          extract_zip(payload)
        else
          payload
        end
      end
    end

    def zip?(payload)
      payload.filename.to_s.downcase.end_with?(".zip") || payload.content.b.start_with?("PK\x03\x04".b)
    end

    def extract_zip(payload)
      files = []
      Zip::File.open_buffer(StringIO.new(payload.content)) do |zip_file|
        zip_file.each do |entry|
          next if entry.directory?
          next if entry.name.start_with?("__MACOSX/")

          filename = File.basename(entry.name)
          next unless filename.match?(/\A(?:TRACK|SENSOR)\.CSV\z/i) || filename.match?(/\.csv\z/i)

          files << FilePayload.new(
            path: entry.name,
            filename: filename,
            content: entry.get_input_stream.read,
            content_type: "text/csv"
          )
        end
      end

      files
    rescue Zip::Error
      raise Error, "#{payload.filename} n'est pas une archive ZIP lisible."
    end

    def detect_sessions(files)
      sessions = []
      used_paths = Set.new

      files.group_by { |file| File.dirname(file.path.to_s) }.each_value do |group|
        track = group.find { |file| basename(file) == "TRACK.CSV" }
        next unless track

        sensor = group.find { |file| basename(file) == "SENSOR.CSV" }
        raise Error, "#{track.path} détecté sans SENSOR.CSV dans le même dossier." unless sensor

        sessions << SessionFile.new(format: :v2, track: track, sensor: sensor, csv: nil)
        used_paths << track.path << sensor.path
      end

      files.each do |file|
        next if used_paths.include?(file.path)
        next unless file.filename.to_s.downcase.end_with?(".csv")
        next unless v1_candidate?(file)

        sessions << SessionFile.new(format: :v1, track: nil, sensor: nil, csv: file)
      end

      sessions
    end

    def basename(file)
      File.basename(file.path.to_s).upcase
    end

    def v1_candidate?(file)
      headers = CsvTools.parse_line(text(file).each_line.first).to_a
      (ParseV1::REQUIRED_COLUMNS - headers).empty?
    end

    def parse_session(session)
      case session.format
      when :v2
        ParseV2.new(
          text(session.track),
          text(session.sensor),
          track_filename: session.track.path,
          sensor_filename: session.sensor.path
        ).call
      when :v1
        ParseV1.new(text(session.csv), filename: session.csv.path).call
      end
    end

    def create_jump!(flight_import, parsed_session, index)
      metrics = Jumps::TrackMetrics.new(parsed_session.track_points)
      points = metrics.prepared_points
      analysis = Jumps::FlightAnalysis.new(track_points: points, sensor_samples: parsed_session.sensor_samples).call
      bounds = analysis.bounds
      summary = metrics.summary(points, sensor_count: parsed_session.sensor_samples.size, bounds: bounds)
        .merge(analysis_summary(analysis))

      jump = flight_import.jumps.create!(
        {
          name: generated_name(parsed_session, index)
        }.merge(summary, bounds)
      )

      insert_track_points(jump, points)
      insert_sensor_samples(jump, parsed_session.sensor_samples)
      jump
    end

    def analysis_summary(analysis)
      {
        min_altitude_m: analysis.altitude_min,
        max_altitude_m: analysis.altitude_max,
        altitude_loss_m: altitude_loss(analysis),
        duration_seconds: analysis.duration_seconds
      }.compact
    end

    def altitude_loss(analysis)
      return nil unless analysis.altitude_min && analysis.altitude_max

      analysis.altitude_max - analysis.altitude_min
    end

    def insert_track_points(jump, points)
      now = Time.current
      points.each_slice(1_000) do |slice|
        TrackPoint.insert_all!(
          slice.map do |point|
            point.slice(
              :recorded_at, :elapsed_seconds, :lat, :lon, :altitude_m, :vel_n_mps, :vel_e_mps, :vel_d_mps,
              :horizontal_accuracy_m, :vertical_accuracy_m, :speed_accuracy_mps, :heading_deg, :course_accuracy_deg,
              :gps_fix, :satellite_count, :horizontal_speed_mps, :vertical_speed_mps, :glide_ratio, :distance_from_start_m
            ).merge(jump_id: jump.id, created_at: now, updated_at: now)
          end
        )
      end
    end

    def insert_sensor_samples(jump, samples)
      now = Time.current
      samples.each_slice(1_000) do |slice|
        SensorSample.insert_all!(
          slice.map do |sample|
            sample.slice(:sensor_type, :recorded_at, :elapsed_seconds, :readings)
              .merge(jump_id: jump.id, created_at: now, updated_at: now)
          end
        )
      end
    end

    def generated_name(parsed_session, index)
      timestamp = parsed_session.started_at&.in_time_zone&.strftime("%Y-%m-%d %H:%M")
      [ "FlySight", timestamp || "session #{index}" ].join(" ")
    end

    def metadata_value(parsed_session, key)
      metadata = parsed_session.metadata
      metadata.dig("sensor_vars", key).presence || metadata.dig("track_vars", key).presence
    end

    def text(payload)
      payload.content.dup.force_encoding("UTF-8").scrub
    end
  end
end
