require "test_helper"

class FlysightImportFlowTest < ActionDispatch::IntegrationTest
  test "imports FlySight V2 files and renders the jump detail" do
    post flight_imports_path, params: {
      flight_import: {
        source_files: [
          fixture_file_upload("flysight_v2/TRACK.CSV", "text/csv"),
          fixture_file_upload("flysight_v2/SENSOR.CSV", "text/csv")
        ]
      }
    }

    jump = FlightImport.order(:created_at).last.jumps.first
    assert_redirected_to jump_path(jump, locale: :fr)

    follow_redirect!
    assert_response :success
    assert_select "h1", jump.name
    assert_select ".trajectory-scene"
    assert_select "canvas.analysis-chart", minimum: 6
  end

  test "dashboard renders import form and recent jumps" do
    get root_path

    assert_response :success
    assert_select "form.upload-form"
    assert_select "a", text: I18n.t("nav.jumps")
  end
end
