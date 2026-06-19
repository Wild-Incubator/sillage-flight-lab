require "csv"
require "time"

module FlySight
  module CsvTools
    module_function

    def parse_line(line)
      CSV.parse_line(line.to_s, liberal_parsing: true)&.map { |value| value&.strip }
    end

    def numeric(value)
      return nil if value.blank?

      Float(value)
    rescue ArgumentError, TypeError
      value
    end

    def integer(value)
      return nil if value.blank?

      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end

    def timestamp(value)
      return nil if value.blank?

      Time.iso8601(value)
    rescue ArgumentError
      nil
    end

    def normalize_sensor_name(value)
      value.to_s.delete_prefix("$").upcase
    end
  end
end
