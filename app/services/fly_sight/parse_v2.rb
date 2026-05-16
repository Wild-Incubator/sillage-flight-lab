module FlySight
  class ParseV2
    GPS_EPOCH = Time.utc(1980, 1, 6)

    def initialize(track_text, sensor_text, track_filename: "TRACK.CSV", sensor_filename: "SENSOR.CSV")
      @track_text = track_text.to_s
      @sensor_text = sensor_text.to_s
      @track_filename = track_filename
      @sensor_filename = sensor_filename
    end

    def call
      track_document = parse_document(@track_text)
      sensor_document = parse_document(@sensor_text)
      track_points = parse_track_points(track_document)
      sensor_samples = parse_sensor_samples(sensor_document, track_points.first&.fetch(:recorded_at, nil))

      raise Error, "Aucun point GNSS valide dans #{@track_filename}." if track_points.empty?

      ParsedSession.new(
        format: "flysight_v2",
        metadata: {
          "track_file" => @track_filename,
          "sensor_file" => @sensor_filename,
          "track_vars" => track_document.fetch(:vars),
          "sensor_vars" => sensor_document.fetch(:vars),
          "track_columns" => track_document.fetch(:columns),
          "sensor_columns" => sensor_document.fetch(:columns)
        },
        track_points: track_points,
        sensor_samples: sensor_samples
      )
    end

    private

    def parse_document(text)
      vars = {}
      columns = {}
      units = {}
      data_rows = []
      in_data = false

      text.each_line do |line|
        row = CsvTools.parse_line(line)
        next if row.blank?

        token = row.first.to_s
        if in_data
          data_rows << row
          next
        end

        case token
        when "$VAR"
          vars[row[1].to_s] = row.drop(2).join(",")
        when "$COL"
          columns[CsvTools.normalize_sensor_name(row[1])] = row.drop(2)
        when "$UNIT"
          units[CsvTools.normalize_sensor_name(row[1])] = row.drop(2)
        when "$DATA"
          in_data = true
        end
      end

      raise Error, "Fichier FlySight V2 invalide: section $DATA absente." unless in_data

      { vars: vars, columns: columns, units: units, rows: data_rows }
    end

    def parse_track_points(document)
      columns = document.fetch(:columns).fetch("GNSS") do
        raise Error, "#{@track_filename} ne contient pas de définition $COL,GNSS."
      end

      document.fetch(:rows).filter_map do |row|
        next unless CsvTools.normalize_sensor_name(row.first) == "GNSS"

        values = columns.zip(row.drop(1)).to_h
        recorded_at = CsvTools.timestamp(values["time"])
        next unless recorded_at

        {
          recorded_at: recorded_at,
          lat: CsvTools.numeric(values["lat"]),
          lon: CsvTools.numeric(values["lon"]),
          altitude_m: CsvTools.numeric(values["hMSL"]),
          vel_n_mps: CsvTools.numeric(values["velN"]),
          vel_e_mps: CsvTools.numeric(values["velE"]),
          vel_d_mps: CsvTools.numeric(values["velD"]),
          horizontal_accuracy_m: CsvTools.numeric(values["hAcc"]),
          vertical_accuracy_m: CsvTools.numeric(values["vAcc"]),
          speed_accuracy_mps: CsvTools.numeric(values["sAcc"]),
          satellite_count: CsvTools.integer(values["numSV"])
        }
      end
    end

    def parse_sensor_samples(document, first_track_time)
      rows = document.fetch(:rows).filter_map do |row|
        sensor = CsvTools.normalize_sensor_name(row.first)
        columns = document.fetch(:columns)[sensor]
        next if columns.blank?

        values = columns.zip(row.drop(1)).to_h
        elapsed_seconds = CsvTools.numeric(values["time"])
        readings = values.except("time").transform_values { |value| CsvTools.numeric(value) }

        {
          sensor_type: sensor,
          elapsed_seconds: elapsed_seconds.is_a?(Numeric) ? elapsed_seconds : nil,
          readings: readings
        }
      end

      sync_origin = sensor_sync_origin(rows, first_track_time)

      rows.map do |sample|
        recorded_at = if sync_origin && sample[:elapsed_seconds]
          sync_origin + sample[:elapsed_seconds]
        end

        sample.merge(recorded_at: recorded_at)
      end
    end

    def sensor_sync_origin(rows, first_track_time)
      time_sample = rows.find do |sample|
        sample[:sensor_type] == "TIME" &&
          sample[:elapsed_seconds] &&
          sample.dig(:readings, "tow").is_a?(Numeric) &&
          sample.dig(:readings, "week").is_a?(Numeric)
      end

      if time_sample
        gps_time = GPS_EPOCH + (time_sample.dig(:readings, "week").to_i * 7 * 86_400) + time_sample.dig(:readings, "tow").to_f
        gps_time - time_sample[:elapsed_seconds]
      elsif first_track_time
        first_elapsed = rows.find { |sample| sample[:elapsed_seconds] }&.fetch(:elapsed_seconds)
        first_elapsed ? first_track_time - first_elapsed : nil
      end
    end
  end
end
