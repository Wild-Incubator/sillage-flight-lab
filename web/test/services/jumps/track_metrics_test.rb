require "test_helper"

module Jumps
  class TrackMetricsTest < ActiveSupport::TestCase
    test "averages glide ratio between exit and opening bounds" do
      started_at = Time.zone.parse("2026-05-20 09:39:03 UTC")
      points = [
        point(started_at, -5.0, 10.0),
        point(started_at, 0.0, 2.0),
        point(started_at, 10.0, 3.0),
        point(started_at, 15.0, 100.0)
      ]

      summary = TrackMetrics.new([]).summary(
        points,
        bounds: {
          exit_at: started_at,
          opening_at: started_at + 10.0
        }
      )

      assert_in_delta 2.5, summary[:avg_glide_ratio]
    end

    test "averages glide ratio across all points when bounds are absent" do
      started_at = Time.zone.parse("2026-05-20 09:39:03 UTC")
      points = [
        point(started_at, -5.0, 10.0),
        point(started_at, 0.0, 2.0),
        point(started_at, 10.0, 3.0),
        point(started_at, 15.0, 100.0)
      ]

      summary = TrackMetrics.new([]).summary(points)

      assert_in_delta 28.75, summary[:avg_glide_ratio]
    end

    private

    def point(started_at, elapsed_seconds, glide_ratio)
      {
        recorded_at: started_at + elapsed_seconds,
        elapsed_seconds: elapsed_seconds,
        altitude_m: 4_000.0 - elapsed_seconds,
        horizontal_speed_mps: 30.0,
        vertical_speed_mps: 20.0,
        glide_ratio: glide_ratio
      }
    end
  end
end
