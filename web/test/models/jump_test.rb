require "test_helper"

class JumpTest < ActiveSupport::TestCase
  test "height uses the lowest altitude as ground reference" do
    jump = jumps(:one)
    jump.min_altitude_m = 3_298.0
    jump.max_altitude_m = 4_100.0

    assert_equal 802.0, jump.height_m
  end
end
