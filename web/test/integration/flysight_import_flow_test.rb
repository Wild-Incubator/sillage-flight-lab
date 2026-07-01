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
    assert_select ".replay-kit-screen"
    assert_select ".replay-kit-id", text: /\AGLD-\d{4}-\d{3}\z/
    assert_select ".mode-badge", text: "Replay"
    assert_select ".replay-kit-metrics span", text: "Altitude"
    assert_select ".trajectory-scene"
    assert_select ".video-sync"
    assert_select "canvas[data-flight-viewer-target='motionChart']"
    assert_select "canvas.analysis-chart", minimum: 6

    viewer = css_select("[data-controller='flight-viewer']").first
    points = JSON.parse(viewer["data-flight-viewer-points-value"])
    analysis = JSON.parse(viewer["data-flight-viewer-analysis-value"])
    assert_in_delta 802.0, points.first["height"]
    assert_in_delta 0.0, points.last["height"]
    assert_equal "gps", analysis["mode"]
    assert_equal "gps", analysis["altitude_source"]
    assert points.all? { |point| point["t"] >= analysis["replay_start"] && point["t"] <= analysis["replay_end"] }
  end

  test "dashboard renders the Sillage logbook" do
    jump = Jump.recent.first

    get root_path

    assert_response :success
    assert_select "link[rel='icon'][href='/icon.svg?v=exopter-e'][type='image/svg+xml']"
    assert_select "h1", "Logbook"
    assert_sillage_breadcrumb room: "Flights", tab: "Logbook"
    assert_select ".sillage-mode-switcher", count: 0
    assert_select ".sillage-live-badge", count: 0
    assert_select ".sillage-account-menu"
    assert_select "form[action='#{logout_path}'][method='post'] button", text: "Log out"
    assert_select ".logbook-table"
    assert_select ".logbook-table tbody tr", minimum: 1
    assert_select ".logbook-row[data-controller='row-link'][data-row-link-url-value='#{jump_path(jump)}']"
    assert_select "a[href='#{jumps_path}']", text: "Logbook"
    assert_select "a[href='#{new_flight_import_path}']", text: "Import FDR"
    assert_select "a[href='#{forge_path}']", text: "Forge"

    get forge_path

    assert_response :success
    assert_select "h1", "Sillage Forge"
    assert_sillage_breadcrumb room: "Forge", tab: "Overview"
    assert_select ".room-placeholder-card"
    assert_select ".room-placeholder-card span", text: "Not built in this UI kit"
    assert_select ".reference-layout", count: 0
  end

  test "top breadcrumb follows the current room and tab" do
    jump = jumps(:one)

    get new_flight_import_path
    assert_response :success
    assert_sillage_breadcrumb room: "Flights", tab: "Flight prep"

    get jump_path(jump)
    assert_response :success
    assert_sillage_breadcrumb room: "Flights", tab: "Replay"

    get flight_hud_path
    assert_response :success
    assert_sillage_breadcrumb room: "Flights", tab: "HUD"

    get atlas_path
    assert_response :success
    assert_sillage_breadcrumb room: "Atlas", tab: "Overview"
  end

  test "logout clears the local session" do
    delete logout_path

    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
    assert_select ".flash.notice", text: "Signed out."
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

  private

  def assert_sillage_breadcrumb(room:, tab:)
    assert_select ".sillage-breadcrumb[aria-label='Breadcrumb']"
    assert_select ".sillage-breadcrumb ol li", 3
    assert_select ".sillage-breadcrumb ol li:nth-child(1) a[href='#{root_path}']", text: "Sillage"
    assert_select ".sillage-breadcrumb ol li:nth-child(2) a", text: room
    assert_select ".sillage-breadcrumb ol li:nth-child(3) [aria-current='page']", text: tab
  end
end
