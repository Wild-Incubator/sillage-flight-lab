require "test_helper"

module Devreference
  class DesignSystemControllerTest < ActionDispatch::IntegrationTest
    test "shows the design system reference page" do
      get devreference_design_system_path

      assert_response :success
      assert_select "h1", "Exopter Design System"
      assert_select ".reference-swatch-card", minimum: 12
      assert_select ".reference-hud-panel"
      assert_select ".reference-check-grid .reference-panel", minimum: 5
      assert_select "td", "HUD-03"
    end
  end
end
