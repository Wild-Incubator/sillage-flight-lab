module Jumps
  class DetectBounds
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
      @points.find do |point|
        point[:horizontal_speed_mps].to_f >= 20.0 || point[:vertical_speed_mps].to_f >= 12.0
      end
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
  end
end
