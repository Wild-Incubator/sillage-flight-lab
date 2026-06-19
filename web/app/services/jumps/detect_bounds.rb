module Jumps
  class DetectBounds
    HORIZONTAL_EXIT_SPEED_MPS = 20.0
    FREEFALL_VERTICAL_SPEED_MPS = 12.0
    EXIT_ONSET_VERTICAL_SPEED_MPS = 2.5
    FREEFALL_LOOKAHEAD_SECONDS = 4.0
    FREEFALL_MIN_ALTITUDE_LOSS_M = 20.0
    FREEFALL_MIN_AVG_DESCENT_MPS = 6.0
    AIRCRAFT_CLIMB_GAIN_M = 50.0

    def initialize(points)
      @points = points.sort_by { |point| point[:elapsed_seconds] || 0 }
    end

    def call
      return {} if @points.empty?

      exit_point = detect_exit || @points.first
      opening_point = detect_opening(exit_point) || fallback_opening(exit_point)
      landing_point = detect_landing || @points.last

      {
        exit_at: exit_point[:recorded_at],
        opening_at: opening_point&.fetch(:recorded_at, nil),
        landing_at: landing_point[:recorded_at]
      }
    end

    private

    def detect_exit
      detect_aircraft_exit || detect_movement_exit
    end

    def detect_aircraft_exit
      @points.each_with_index do |_point, index|
        next unless sustained_freefall_from?(index)

        return exit_onset_point(index)
      end

      nil
    end

    def detect_movement_exit
      vertical_exit = @points.find { |point| fast_freefall?(point) }
      return vertical_exit if vertical_exit
      return nil if aircraft_climb?

      @points.find do |point|
        point[:horizontal_speed_mps].to_f >= HORIZONTAL_EXIT_SPEED_MPS
      end
    end

    def sustained_freefall_from?(index)
      window = freefall_window(index)
      return false if window.size < 2

      duration = elapsed_seconds(window.last) - elapsed_seconds(window.first)
      return false unless duration.positive?

      altitude_loss = altitude_m(window.first) - altitude_m(window.last)
      return false unless altitude_loss >= FREEFALL_MIN_ALTITUDE_LOSS_M
      return false unless (altitude_loss / duration) >= FREEFALL_MIN_AVG_DESCENT_MPS

      window.any? { |point| fast_freefall?(point) } ||
        window.all? { |point| vertical_speed_mps(point).nil? }
    end

    def freefall_window(index)
      point = @points[index]
      start_elapsed = elapsed_seconds(point)
      return [] unless start_elapsed && altitude_m(point)

      window = @points[index..].take_while do |candidate|
        elapsed = elapsed_seconds(candidate)
        elapsed && elapsed <= start_elapsed + FREEFALL_LOOKAHEAD_SECONDS && altitude_m(candidate)
      end
      window = @points[index, 2].to_a if window.size < 2

      window.select { |candidate| elapsed_seconds(candidate) && altitude_m(candidate) }
    end

    def exit_onset_point(index)
      return @points.first if index.zero?

      freefall_window(index).find do |point|
        vertical_speed = vertical_speed_mps(point)
        vertical_speed && vertical_speed >= EXIT_ONSET_VERTICAL_SPEED_MPS
      end || @points[index]
    end

    def detect_opening(exit_point)
      after_exit = @points.drop_while { |point| point[:elapsed_seconds].to_f <= exit_point[:elapsed_seconds].to_f + 8.0 }
      after_peak = false

      after_exit.each_cons(4) do |window|
        after_peak ||= window.any? { |point| point[:vertical_speed_mps].to_f >= 25.0 }
        next unless after_peak

        return window.first if window.all? { |point| point[:vertical_speed_mps].to_f < 10.0 }
      end

      nil
    end

    def fallback_opening(exit_point)
      return nil if @points.size < 4

      target_elapsed = exit_point[:elapsed_seconds].to_f + ((@points.last[:elapsed_seconds].to_f - exit_point[:elapsed_seconds].to_f) * 0.7)
      @points.min_by { |point| (point[:elapsed_seconds].to_f - target_elapsed).abs }
    end

    def detect_landing
      active_points = @points.select do |point|
        point[:horizontal_speed_mps].to_f >= 2.5 || point[:vertical_speed_mps].to_f.abs >= 1.0
      end

      active_points.last
    end

    def aircraft_climb?
      start_altitude = altitude_m(@points.first)
      return false unless start_altitude

      max_altitude = @points.filter_map { |point| altitude_m(point) }.max
      max_altitude && (max_altitude - start_altitude) >= AIRCRAFT_CLIMB_GAIN_M
    end

    def fast_freefall?(point)
      vertical_speed = vertical_speed_mps(point)
      vertical_speed && vertical_speed >= FREEFALL_VERTICAL_SPEED_MPS
    end

    def elapsed_seconds(point)
      numeric(point, :elapsed_seconds)
    end

    def altitude_m(point)
      numeric(point, :altitude_m)
    end

    def vertical_speed_mps(point)
      numeric(point, :vertical_speed_mps)
    end

    def numeric(point, key)
      value = point&.fetch(key, nil)
      return nil if value.nil?

      number = value.to_f
      number.finite? ? number : nil
    end
  end
end
