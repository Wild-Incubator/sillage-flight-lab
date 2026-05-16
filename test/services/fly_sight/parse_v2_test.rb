require "test_helper"

module FlySight
  class ParseV2Test < ActiveSupport::TestCase
    test "parses FlySight V2 track and sensor rows" do
      parser = ParseV2.new(
        file_fixture("flysight_v2/TRACK.CSV").read,
        file_fixture("flysight_v2/SENSOR.CSV").read
      )
      session = parser.call

      assert_equal "flysight_v2", session.format
      assert_equal 8, session.track_points.size
      assert_equal 8, session.sensor_samples.size
      assert_equal "fixture-device", session.metadata.dig("sensor_vars", "DEVICE_ID")
      assert_equal Time.utc(2024, 4, 20, 4, 20, 0), session.sensor_samples.first[:recorded_at]
    end
  end
end
