module Jumps
  class TrackMetrics
    EARTH_RADIUS_M = 6_371_000.0

    def initialize(points)
      @points = points.sort_by { |point| point[:recorded_at] || Time.at(0) }
    end

    def prepared_points
      return [] if @points.empty?

      origin_time = @points.first[:recorded_at]
      previous = nil
      distance = 0.0

      @points.map do |point|
        distance += haversine_distance(previous, point) if previous
        previous = point

        horizontal_speed = speed(point[:vel_n_mps], point[:vel_e_mps])
        vertical_speed = point[:vel_d_mps]&.to_f

        point.merge(
          elapsed_seconds: point[:recorded_at] && origin_time ? point[:recorded_at] - origin_time : nil,
          horizontal_speed_mps: horizontal_speed,
          vertical_speed_mps: vertical_speed,
          glide_ratio: glide_ratio(horizontal_speed, vertical_speed),
          distance_from_start_m: distance
        )
      end
    end

    def summary(points = prepared_points, sensor_count: 0, bounds: nil)
      altitudes = points.filter_map { |point| point[:altitude_m]&.to_f }
      horizontal_speeds = points.filter_map { |point| point[:horizontal_speed_mps]&.to_f }
      vertical_speeds = points.filter_map { |point| point[:vertical_speed_mps]&.to_f }
      glide_ratios = points_for_glide_average(points, bounds)
        .filter_map { |point| point[:glide_ratio]&.to_f }
        .select(&:finite?)

      {
        started_at: points.first&.fetch(:recorded_at, nil),
        ended_at: points.last&.fetch(:recorded_at, nil),
        duration_seconds: duration(points),
        min_altitude_m: altitudes.min,
        max_altitude_m: altitudes.max,
        altitude_loss_m: altitude_loss(altitudes),
        distance_m: points.last&.fetch(:distance_from_start_m, nil),
        max_horizontal_speed_mps: horizontal_speeds.max,
        max_vertical_speed_mps: vertical_speeds.max,
        avg_glide_ratio: average(glide_ratios),
        sample_count: points.size,
        sensor_sample_count: sensor_count
      }
    end

    private

    def points_for_glide_average(points, bounds)
      return points unless bounds

      exit_at = bounds[:exit_at]
      opening_at = bounds[:opening_at]
      return points unless exit_at || opening_at

      points.select do |point|
        recorded_at = point[:recorded_at]
        recorded_at &&
          (!exit_at || recorded_at >= exit_at) &&
          (!opening_at || recorded_at <= opening_at)
      end
    end

    def duration(points)
      return nil if points.size < 2

      points.last[:recorded_at] - points.first[:recorded_at]
    end

    def speed(north, east)
      return nil unless north && east

      Math.sqrt(north.to_f**2 + east.to_f**2)
    end

    def glide_ratio(horizontal_speed, vertical_speed)
      return nil unless horizontal_speed && vertical_speed&.positive?
      return nil if vertical_speed < 0.3

      horizontal_speed / vertical_speed
    end

    def altitude_loss(altitudes)
      return nil if altitudes.empty?

      altitudes.max - altitudes.min
    end

    def average(values)
      return nil if values.empty?

      values.sum / values.size
    end

    def haversine_distance(a, b)
      return 0.0 unless coordinate?(a) && coordinate?(b)

      lat1 = radians(a[:lat])
      lat2 = radians(b[:lat])
      delta_lat = radians(b[:lat] - a[:lat])
      delta_lon = radians(b[:lon] - a[:lon])
      h = Math.sin(delta_lat / 2)**2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(delta_lon / 2)**2

      2 * EARTH_RADIUS_M * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h))
    end

    def coordinate?(point)
      point && point[:lat].present? && point[:lon].present?
    end

    def radians(degrees)
      degrees.to_f * Math::PI / 180.0
    end
  end
end
