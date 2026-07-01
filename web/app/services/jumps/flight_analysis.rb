module Jumps
  class FlightAnalysis
    Result = Data.define(
      :mode,
      :reason,
      :bounds,
      :timeline_start,
      :timeline_end,
      :replay_start,
      :replay_end,
      :altitude_source,
      :altitude_min,
      :altitude_max,
      :duration_seconds
    ) do
      def degraded?
        mode == "degraded"
      end

      def to_h
        {
          mode: mode,
          reason: reason,
          bounds: bounds,
          timeline_start: timeline_start,
          timeline_end: timeline_end,
          replay_start: replay_start,
          replay_end: replay_end,
          altitude_source: altitude_source,
          altitude_min: altitude_min,
          altitude_max: altitude_max,
          duration_seconds: duration_seconds
        }
      end
    end

    STANDARD_PRESSURE_PA = 101_325.0
    PRESSURE_ALTITUDE_EXPONENT = 0.190294957
    SENSOR_ALTITUDE_DOMINANCE_M = 500.0
    MIN_AIRCRAFT_OPENING_ALTITUDE_M = 500.0
    EXIT_LOOKAHEAD_SECONDS = 8.0
    EXIT_MIN_ALTITUDE_LOSS_M = 45.0
    EXIT_MIN_AVG_DESCENT_MPS = 7.0
    OPENING_LOOKAHEAD_SECONDS = 20.0
    OPENING_MAX_AVG_DESCENT_MPS = 8.0
    LANDING_MAX_MOTION_MPS = 1.0
    PRESSURE_SPEED_WINDOW_SECONDS = 4.0
    PRESSURE_SPEED_MAX_MPS = 140.0
    PRESSURE_SPEED_MIN_PAIR_SECONDS = 0.25
    REPLAY_PADDING_SECONDS = 10.0

    def initialize(track_points:, sensor_samples:, origin_time: nil)
      @track_points = normalize_track_points(track_points)
      @origin_time = origin_time || @track_points.first&.fetch(:recorded_at, nil)
      @sensor_samples = normalize_sensor_samples(sensor_samples)
      @pressure_points = pressure_altitude_points
    end

    def call
      bounds = degraded? ? degraded_bounds : gps_bounds
      altitude_points = degraded? ? @pressure_points : @track_points
      timeline_values = (@track_points + @sensor_samples).filter_map { |point| point[:elapsed_seconds] }
      timeline_start = timeline_values.min || 0.0
      timeline_end = timeline_values.max || 0.0
      replay_start, replay_end = replay_window(bounds, timeline_start, timeline_end)

      Result.new(
        mode: degraded? ? "degraded" : "gps",
        reason: degraded? ? degraded_reason : nil,
        bounds: bounds,
        timeline_start: timeline_start,
        timeline_end: timeline_end,
        replay_start: replay_start,
        replay_end: replay_end,
        altitude_source: degraded? ? "pressure_altitude" : "gps",
        altitude_min: altitude_points.filter_map { |point| point[:altitude_m] }.min,
        altitude_max: altitude_points.filter_map { |point| point[:altitude_m] }.max,
        duration_seconds: timeline_values.present? ? timeline_values.max - timeline_values.min : nil
      )
    end

    private

    def degraded?
      return true if @track_points.empty? && @pressure_points.any?
      return false if @pressure_points.empty?

      pressure_max = @pressure_points.filter_map { |point| point[:altitude_m] }.max
      gps_max = @track_points.filter_map { |point| point[:altitude_m] }.max
      return false unless pressure_max && gps_max

      pressure_max - gps_max >= SENSOR_ALTITUDE_DOMINANCE_M
    end

    def degraded_reason
      return "No GPS track is available; pressure altitude is driving replay analysis." if @track_points.empty?

      "Pressure altitude is substantially higher than GPS altitude; using sensor-driven replay analysis."
    end

    def replay_window(bounds, timeline_start, timeline_end)
      exit_elapsed = elapsed_for(bounds[:exit_at])
      landing_elapsed = elapsed_for(bounds[:landing_at])

      replay_start = exit_elapsed ? [ exit_elapsed - REPLAY_PADDING_SECONDS, timeline_start ].max : timeline_start
      replay_end = landing_elapsed ? [ landing_elapsed + REPLAY_PADDING_SECONDS, timeline_end ].min : timeline_end
      return [ timeline_start, timeline_end ] if replay_end < replay_start

      [ replay_start, replay_end ]
    end

    def elapsed_for(timestamp)
      return nil unless timestamp && @origin_time

      timestamp - @origin_time
    end

    def gps_bounds
      DetectBounds.new(@track_points).call
    end

    def degraded_bounds
      return gps_bounds if @pressure_points.empty?

      exit_point = detect_sensor_exit || @pressure_points.first
      opening_point = detect_sensor_opening(exit_point) || fallback_opening(exit_point)
      landing_point = detect_sensor_landing || @pressure_points.last

      {
        exit_at: exit_point[:recorded_at],
        opening_at: opening_point&.fetch(:recorded_at, nil),
        landing_at: landing_point[:recorded_at]
      }
    end

    def detect_sensor_exit
      peak_index = @pressure_points.each_with_index.max_by { |point, _index| point[:altitude_m].to_f }&.last || 0
      search_start = [ peak_index - 12, 0 ].max

      @pressure_points.each_with_index.drop(search_start).each do |_point, index|
        window = time_window(index, EXIT_LOOKAHEAD_SECONDS)
        next if window.size < 2

        duration = window.last[:elapsed_seconds] - window.first[:elapsed_seconds]
        next unless duration&.positive?

        altitude_loss = window.first[:altitude_m].to_f - window.last[:altitude_m].to_f
        next unless altitude_loss >= EXIT_MIN_ALTITUDE_LOSS_M
        next unless (altitude_loss / duration) >= EXIT_MIN_AVG_DESCENT_MPS

        return window.find { |point| point[:vertical_speed_mps].to_f >= 2.5 } || window.first
      end

      nil
    end

    def detect_sensor_opening(exit_point)
      return nil unless exit_point

      after_exit = @pressure_points.drop_while do |point|
        point[:elapsed_seconds].to_f <= exit_point[:elapsed_seconds].to_f + 8.0
      end
      seen_fast_descent = false

      after_exit.each_with_index do |point, offset|
        seen_fast_descent ||= point[:vertical_speed_mps].to_f >= 18.0
        next unless seen_fast_descent
        next unless point[:altitude_m].to_f >= MIN_AIRCRAFT_OPENING_ALTITUDE_M

        index = @pressure_points.length - after_exit.length + offset
        window = time_window(index, OPENING_LOOKAHEAD_SECONDS)
        next if window.size < 2

        duration = window.last[:elapsed_seconds] - window.first[:elapsed_seconds]
        next unless duration&.positive?

        altitude_loss = window.first[:altitude_m].to_f - window.last[:altitude_m].to_f
        avg_descent = altitude_loss / duration
        return point if avg_descent <= OPENING_MAX_AVG_DESCENT_MPS
      end

      nil
    end

    def fallback_opening(exit_point)
      return nil unless exit_point

      after_exit = @pressure_points.select { |point| point[:elapsed_seconds].to_f > exit_point[:elapsed_seconds].to_f }
      after_exit.find { |point| point[:altitude_m].to_f <= 1_200.0 && point[:altitude_m].to_f >= MIN_AIRCRAFT_OPENING_ALTITUDE_M } ||
        after_exit[(after_exit.length * 0.7).floor]
    end

    def detect_sensor_landing
      active_points = @pressure_points.select do |point|
        point[:vertical_speed_mps].to_f.abs >= LANDING_MAX_MOTION_MPS
      end

      active_points.last
    end

    def time_window(index, seconds)
      start = @pressure_points[index]
      return [] unless start

      @pressure_points[index..].take_while do |point|
        point[:elapsed_seconds].to_f <= start[:elapsed_seconds].to_f + seconds
      end
    end

    def normalize_track_points(records)
      records.map do |record|
        {
          recorded_at: value(record, :recorded_at),
          elapsed_seconds: numeric(value(record, :elapsed_seconds)),
          altitude_m: numeric(value(record, :altitude_m)),
          horizontal_speed_mps: numeric(value(record, :horizontal_speed_mps)),
          vertical_speed_mps: numeric(value(record, :vertical_speed_mps))
        }
      end.compact.sort_by { |point| point[:elapsed_seconds] || 0.0 }
    end

    def normalize_sensor_samples(records)
      records.map do |record|
        recorded_at = value(record, :recorded_at)
        raw_elapsed = numeric(value(record, :elapsed_seconds))
        elapsed_seconds = if recorded_at && @origin_time
          recorded_at - @origin_time
        else
          raw_elapsed
        end

        {
          sensor_type: value(record, :sensor_type).to_s,
          recorded_at: recorded_at,
          elapsed_seconds: elapsed_seconds,
          readings: readings(record).merge("sensor_time" => raw_elapsed)
        }
      end.compact.sort_by { |sample| sample[:elapsed_seconds] || 0.0 }
    end

    def pressure_altitude_points
      points = @sensor_samples.filter_map do |sample|
        next unless sample[:sensor_type] == "BARO"

        altitude = numeric(sample.dig(:readings, "pressure_altitude_m")) ||
          pressure_altitude(sample.dig(:readings, "pressure"))
        elapsed_seconds = numeric(sample[:elapsed_seconds])
        next unless altitude && elapsed_seconds

        {
          recorded_at: sample[:recorded_at],
          elapsed_seconds: elapsed_seconds,
          altitude_m: altitude
        }
      end

      dedupe_pressure_points(points).then { |deduped| add_vertical_speed(deduped) }
    end

    def dedupe_pressure_points(points)
      points.sort_by { |point| point[:elapsed_seconds] }.each_with_object([]) do |point, deduped|
        previous = deduped.last
        next if previous && (previous[:elapsed_seconds] - point[:elapsed_seconds]).abs < 0.001

        deduped << point
      end
    end

    def add_vertical_speed(points)
      previous_index = 0
      next_index = 0
      half_window = PRESSURE_SPEED_WINDOW_SECONDS / 2.0

      points.each_with_index.map do |point, index|
        elapsed = point[:elapsed_seconds].to_f

        while previous_index + 1 < index && points[previous_index + 1][:elapsed_seconds].to_f <= elapsed - half_window
          previous_index += 1
        end

        next_index = [ next_index, index ].max
        while next_index + 1 < points.length && points[next_index][:elapsed_seconds].to_f < elapsed + half_window
          next_index += 1
        end

        point.merge(vertical_speed_mps: cleaned_pressure_speed(points[previous_index], points[next_index]))
      end
    end

    def cleaned_pressure_speed(previous, following)
      return nil unless previous && following

      duration = following[:elapsed_seconds].to_f - previous[:elapsed_seconds].to_f
      return nil if duration < PRESSURE_SPEED_MIN_PAIR_SECONDS

      speed = (previous[:altitude_m].to_f - following[:altitude_m].to_f) / duration
      return nil if speed.abs > PRESSURE_SPEED_MAX_MPS

      speed
    end

    def pressure_altitude(pressure)
      pressure = numeric(pressure)
      return nil unless pressure

      44_330.0 * (1.0 - (pressure / STANDARD_PRESSURE_PA)**PRESSURE_ALTITUDE_EXPONENT)
    end

    def readings(record)
      raw = value(record, :readings) || {}
      raw.respond_to?(:to_h) ? raw.to_h : {}
    end

    def value(record, key)
      if record.respond_to?(:[])
        record[key] || record[key.to_s]
      elsif record.respond_to?(key)
        record.public_send(key)
      end
    end

    def numeric(value)
      return nil if value.nil?

      number = value.to_f
      number.finite? ? number : nil
    end
  end
end
