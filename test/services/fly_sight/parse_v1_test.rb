require "test_helper"

module FlySight
  class ParseV1Test < ActiveSupport::TestCase
    test "parses FlySight V1 track rows" do
      parser = ParseV1.new(file_fixture("flysight_v1/SESSION.CSV").read, filename: "SESSION.CSV")
      session = parser.call

      assert_equal "flysight_v1", session.format
      assert_equal 4, session.track_points.size
      assert_empty session.sensor_samples
      assert_equal 45.0, session.track_points.first[:lat]
      assert_equal 3, session.track_points.first[:gps_fix]
    end
  end
end
