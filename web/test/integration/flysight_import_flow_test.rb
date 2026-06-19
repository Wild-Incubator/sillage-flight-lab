require "test_helper"

class FlysightImportFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

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
    assert_redirected_to jump_path(jump)

    follow_redirect!
    assert_response :success
    assert_select "h1", jump.name
    assert_select ".flight-readiness-strip strong", text: I18n.t("flight_lab.mode_gld_replay")
    assert_select ".metric-strip span", text: I18n.t("stats.height")
    assert_select ".trajectory-scene"
    assert_select ".video-sync"
    assert_select "canvas.analysis-chart", minimum: 6

    viewer = css_select("[data-controller='flight-viewer']").first
    points = JSON.parse(viewer["data-flight-viewer-points-value"])
    assert_in_delta 802.0, points.first["height"]
    assert_in_delta 0.0, points.last["height"]
  end

  test "dashboard renders import form and recent jumps" do
    get root_path

    assert_response :success
    assert_select "form.upload-form"
    assert_select ".flight-readiness-strip strong", text: I18n.t("flight_lab.mode_gld")
    assert_select "a", text: I18n.t("nav.jumps")
  end

  test "french locale falls back to english" do
    get root_path(locale: :fr)

    assert_response :success
    assert_select "html[lang=en]"
    assert_select ".locale-switch", count: 0
  end

  test "uploads a video for web optimization and stores the marked exit point" do
    jump = jumps(:one)

    assert_enqueued_jobs 1, only: JumpVideoProcessingJob do
      patch jump_path(jump), params: {
        jump: {
          video_upload: fixture_file_upload("sample.mp4", "video/mp4")
        }
      }
    end

    assert_redirected_to jump_path(jump)
    assert_equal "processing", jump.reload.video_processing_status
    assert jump.video_upload.attached?

    patch jump_path(jump), params: {
      jump: {
        video_exit_offset_seconds: "12.345"
      }
    }

    assert_redirected_to jump_path(jump)
    assert_in_delta 12.345, jump.reload.video_exit_offset_seconds
  ensure
    clear_enqueued_jobs
  end

  test "renders ready video controls with the saved exit offset" do
    jump = jumps(:one)
    jump.video.attach(
      io: file_fixture("sample.mp4").open,
      filename: "sample.mp4",
      content_type: "video/mp4"
    )
    jump.update!(
      video_processing_status: "ready",
      video_exit_offset_seconds: 4.2,
      video_duration_seconds: 12.0
    )

    get jump_path(jump)

    assert_response :success
    assert_select "video.jump-video"
    assert_select "button", text: I18n.t("jumps.video.mark_exit")
    assert_select ".video-sync-state", text: I18n.t("jumps.video.exit_marked", timestamp: "00:04")

    viewer = css_select("[data-controller='flight-viewer']").first
    assert_equal "4.2", viewer["data-flight-viewer-video-exit-offset-value"]
  end
end
