module FlySight
  class ParseV1
    REQUIRED_COLUMNS = %w[time lat lon hMSL velN velE velD].freeze

    def initialize(text, filename: nil)
      @text = text.to_s
      @filename = filename
    end

    def call
      lines = @text.each_line.map(&:strip).reject(&:blank?)
      headers = CsvTools.parse_line(lines.first).to_a
      validate_headers!(headers)

      track_points = lines.drop(2).filter_map do |line|
        row = CsvTools.parse_line(line)
        next if row.blank?

        values = headers.zip(row).to_h
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
          heading_deg: CsvTools.numeric(values["heading"]),
          course_accuracy_deg: CsvTools.numeric(values["cAcc"]),
          gps_fix: CsvTools.integer(values["gpsFix"]),
          satellite_count: CsvTools.integer(values["numSV"])
        }
      end

      raise Error, "Aucun point GPS valide dans #{@filename || "le CSV FlySight"}." if track_points.empty?

      ParsedSession.new(
        format: "flysight_v1",
        metadata: {
          "source" => @filename,
          "columns" => headers
        },
        track_points: track_points,
        sensor_samples: []
      )
    end

    private

    def validate_headers!(headers)
      missing = REQUIRED_COLUMNS - headers
      return if missing.empty?

      raise Error, "CSV FlySight V1 invalide: colonnes manquantes #{missing.join(", ")}."
    end
  end
end
