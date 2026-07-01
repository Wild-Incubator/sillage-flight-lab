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
      assert_in_delta 0.0, session.sensor_samples.first[:elapsed_seconds]
      assert_in_delta 4_055.5, session.sensor_samples.second.dig(:readings, "pressure_altitude_m"), 0.1
    end

    test "rebases raw sensor elapsed time to the GNSS track start" do
      track_text = <<~CSV
        $FLYS,1
        $VAR,DEVICE_ID,fixture-device
        $COL,GNSS,time,lat,lon,hMSL,velN,velE,velD,hAcc,vAcc,sAcc,numSV
        $DATA
        $GNSS,2024-04-20T04:20:00.000Z,45.0,5.0,4100.0,0.0,0.0,0.0,1.0,1.5,0.5,12
      CSV
      sensor_text = <<~CSV
        $FLYS,1
        $VAR,DEVICE_ID,fixture-device
        $COL,TIME,time,tow,week
        $COL,BARO,time,pressure,temperature
        $DATA
        $TIME,1000.0,534000.0,2310
        $BARO,990.0,61200.0,18.2
        $BARO,1000.0,62500.0,18.0
      CSV

      session = ParseV2.new(track_text, sensor_text).call
      baro_samples = session.sensor_samples.select { |sample| sample[:sensor_type] == "BARO" }

      assert_equal [ -10.0, 0.0 ], baro_samples.map { |sample| sample[:elapsed_seconds] }
      assert_equal Time.utc(2024, 4, 20, 4, 19, 50), baro_samples.first[:recorded_at]
      assert_equal 990.0, baro_samples.first.dig(:readings, "sensor_time")
      assert_in_delta 4_055.5, baro_samples.first.dig(:readings, "pressure_altitude_m"), 0.1
    end
  end
end
