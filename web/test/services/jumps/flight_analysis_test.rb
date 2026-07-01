require "test_helper"

module Jumps
  class FlightAnalysisTest < ActiveSupport::TestCase
    test "keeps GPS mode when GPS altitude covers the pressure altitude range" do
      started_at = Time.zone.parse("2026-07-01 15:18:00 UTC")
      track_points = [
        track_point(started_at, 0.0, 4_210.0, 32.0, 0.2),
        track_point(started_at, 4.0, 4_140.0, 34.0, 17.5),
        track_point(started_at, 8.0, 3_980.0, 38.0, 35.0),
        track_point(started_at, 20.0, 3_500.0, 42.0, 38.0)
      ]
      sensor_samples = baro_profile(started_at, [
        [ 0.0, 4_215.0 ],
        [ 4.0, 4_130.0 ],
        [ 8.0, 3_970.0 ],
        [ 20.0, 3_490.0 ]
      ])

      analysis = FlightAnalysis.new(track_points:, sensor_samples:).call

      assert_equal "gps", analysis.mode
      assert_equal "gps", analysis.altitude_source
      assert_nil analysis.reason
    end

    test "falls back to sensor-driven analysis when GPS starts late and too low" do
      started_at = Time.zone.parse("2026-07-01 15:18:00 UTC")
      track_points = [
        track_point(started_at, 0.0, 930.0, 19.0, 4.0),
        track_point(started_at, 10.0, 870.0, 20.0, 5.0),
        track_point(started_at, 30.0, 780.0, 16.0, 3.0)
      ]
      sensor_samples = aircraft_profile(started_at)

      analysis = FlightAnalysis.new(track_points:, sensor_samples:, origin_time: started_at).call

      assert_equal "degraded", analysis.mode
      assert_equal "pressure_altitude", analysis.altitude_source
      assert_match(/Pressure altitude is substantially higher/, analysis.reason)
      assert_in_delta(-560.0, analysis.timeline_start, 0.001)
      assert_operator analysis.timeline_end, :>, 100.0
      assert_operator analysis.altitude_max, :>, 4_000.0
      assert_operator analysis.bounds[:exit_at], :<, started_at
      assert_operator analysis.bounds[:opening_at], :>, analysis.bounds[:exit_at]
      assert_operator analysis.bounds[:opening_at], :<, started_at
      assert_operator altitude_at(sensor_samples, analysis.bounds[:opening_at]), :<, 1_500.0
      assert_operator analysis.bounds[:landing_at], :>, started_at

      exit_elapsed = analysis.bounds[:exit_at] - started_at
      landing_elapsed = analysis.bounds[:landing_at] - started_at
      assert_in_delta exit_elapsed - 10.0, analysis.replay_start, 0.001
      assert_in_delta [ landing_elapsed + 10.0, analysis.timeline_end ].min, analysis.replay_end, 0.001
    end

    test "uses degraded analysis when no GPS track is available" do
      started_at = Time.zone.parse("2026-07-01 15:18:00 UTC")

      analysis = FlightAnalysis.new(
        track_points: [],
        sensor_samples: aircraft_profile(started_at),
        origin_time: started_at
      ).call

      assert_equal "degraded", analysis.mode
      assert_match(/No GPS track is available/, analysis.reason)
      assert_operator analysis.bounds[:exit_at], :<, started_at
      assert_operator analysis.bounds[:opening_at], :<, started_at
      assert_operator analysis.bounds[:landing_at], :>, started_at
    end

    test "smooths isolated pressure spikes before deriving vertical speed" do
      started_at = Time.zone.parse("2026-07-01 15:18:00 UTC")
      points = [
        pressure_point(started_at, 0.0, 1_000.0),
        pressure_point(started_at, 1.0, 990.0),
        pressure_point(started_at, 2.0, 1_260.0),
        pressure_point(started_at, 3.0, 970.0),
        pressure_point(started_at, 4.0, 960.0)
      ]

      cleaned = FlightAnalysis.new(track_points: [], sensor_samples: [], origin_time: started_at)
        .send(:add_vertical_speed, points)

      assert_operator cleaned[2][:vertical_speed_mps].abs, :<, 20.0
    end

    private

    def aircraft_profile(started_at)
      climb = [
        [ -560.0, 2_400.0 ],
        [ -460.0, 2_900.0 ],
        [ -360.0, 3_350.0 ],
        [ -260.0, 3_850.0 ],
        [ -160.0, 4_180.0 ],
        [ -140.0, 4_200.0 ],
        [ -120.0, 4_200.0 ]
      ]
      freefall = (-118..-8).step(2).map do |elapsed|
        [ elapsed.to_f, 4_200.0 - ((elapsed + 118) * 32.0) ]
      end
      canopy = (-6..120).step(2).map do |elapsed|
        [ elapsed.to_f, 674.0 - ((elapsed + 6) * 3.0) ]
      end

      baro_profile(started_at, climb + freefall + canopy)
    end

    def baro_profile(started_at, rows)
      rows.map do |elapsed_seconds, altitude_m|
        {
          sensor_type: "BARO",
          recorded_at: started_at + elapsed_seconds,
          elapsed_seconds: elapsed_seconds,
          readings: { "pressure_altitude_m" => altitude_m }
        }
      end
    end

    def track_point(started_at, elapsed_seconds, altitude_m, horizontal_speed_mps, vertical_speed_mps)
      {
        recorded_at: started_at + elapsed_seconds,
        elapsed_seconds: elapsed_seconds,
        altitude_m: altitude_m,
        horizontal_speed_mps: horizontal_speed_mps,
        vertical_speed_mps: vertical_speed_mps
      }
    end

    def pressure_point(started_at, elapsed_seconds, altitude_m)
      {
        recorded_at: started_at + elapsed_seconds,
        elapsed_seconds: elapsed_seconds,
        altitude_m: altitude_m
      }
    end

    def altitude_at(sensor_samples, recorded_at)
      nearest = sensor_samples.min_by { |sample| (sample[:recorded_at] - recorded_at).abs }

      nearest.dig(:readings, "pressure_altitude_m")
    end
  end
end
