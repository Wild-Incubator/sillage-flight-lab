require "test_helper"
require "tempfile"
require "zip"

module FlySight
  class ImportServiceTest < ActiveSupport::TestCase
    UploadedFile = Data.define(:path, :original_filename, :content_type) do
      def read
        File.binread(path)
      end

      def rewind
      end
    end

    test "imports paired FlySight V2 files" do
      import = ImportService.new([
        upload("flysight_v2/TRACK.CSV"),
        upload("flysight_v2/SENSOR.CSV")
      ]).call

      jump = import.jumps.first
      assert_equal "imported", import.status
      assert_equal "fixture-device", import.device_id
      assert_equal 1, import.jumps.count
      assert_equal 8, jump.track_points.count
      assert_equal 8, jump.sensor_samples.count
      assert_equal 8, jump.sample_count
      assert import.source_files.attached?
      assert jump.exit_at
      assert jump.opening_at
      assert jump.landing_at
    end

    test "imports a zipped FlySight V2 session folder" do
      archive = Tempfile.new([ "flysight", ".zip" ])
      archive.binmode

      Zip::File.open(archive.path, create: true) do |zip|
        zip.add("TEMP/0000/TRACK.CSV", file_fixture("flysight_v2/TRACK.CSV"))
        zip.add("TEMP/0000/SENSOR.CSV", file_fixture("flysight_v2/SENSOR.CSV"))
      end

      import = ImportService.new([
        UploadedFile.new(path: archive.path, original_filename: "session.zip", content_type: "application/zip")
      ]).call

      assert_equal "imported", import.status
      assert_equal 1, import.jumps.count
      assert_equal 8, import.jumps.first.sensor_samples.count
    ensure
      archive&.close!
    end

    test "rejects FlySight V2 track without matching sensor file" do
      assert_raises(FlySight::Error) do
        ImportService.new([ upload("flysight_v2/TRACK.CSV") ]).call
      end

      assert_equal "failed", FlightImport.order(:created_at).last.status
    end

    private

    def upload(fixture_path)
      file = file_fixture(fixture_path)
      UploadedFile.new(path: file.to_s, original_filename: file.basename.to_s, content_type: "text/csv")
    end
  end
end
