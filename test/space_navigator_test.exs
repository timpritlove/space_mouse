defmodule SpaceNavigatorTest do
  use ExUnit.Case
  doctest SpaceNavigator

  test "API functions are available" do
    # Test that the main API functions exist
    assert function_exported?(SpaceNavigator, :start_monitoring, 0)
    assert function_exported?(SpaceNavigator, :stop_monitoring, 0)
    assert function_exported?(SpaceNavigator, :subscribe, 0)
    assert function_exported?(SpaceNavigator, :subscribe, 1)
    assert function_exported?(SpaceNavigator, :unsubscribe, 0)
    assert function_exported?(SpaceNavigator, :unsubscribe, 1)
    assert function_exported?(SpaceNavigator, :set_led, 1)
    assert function_exported?(SpaceNavigator, :get_led_state, 0)
    assert function_exported?(SpaceNavigator, :connected?, 0)
    assert function_exported?(SpaceNavigator, :platform_info, 0)
  end

  test "platform info returns correct structure" do
    info = SpaceNavigator.platform_info()
    assert is_map(info)
    assert Map.has_key?(info, :platform)
    assert Map.has_key?(info, :method)
    assert Map.has_key?(info, :version)
  end
end
