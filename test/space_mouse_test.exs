defmodule SpaceMouseTest do
  use ExUnit.Case
  doctest SpaceMouse

  test "API functions are available" do
    # Test that the main API functions exist
    assert function_exported?(SpaceMouse, :start_monitoring, 0)
    assert function_exported?(SpaceMouse, :stop_monitoring, 0)
    assert function_exported?(SpaceMouse, :subscribe, 0)
    assert function_exported?(SpaceMouse, :subscribe, 1)
    assert function_exported?(SpaceMouse, :unsubscribe, 0)
    assert function_exported?(SpaceMouse, :unsubscribe, 1)
    assert function_exported?(SpaceMouse, :set_led, 1)
    assert function_exported?(SpaceMouse, :get_led_state, 0)
    assert function_exported?(SpaceMouse, :connected?, 0)
    assert function_exported?(SpaceMouse, :platform_info, 0)
  end

  test "platform info returns correct structure" do
    info = SpaceMouse.platform_info()
    assert is_map(info)
    assert Map.has_key?(info, :platform)
    assert Map.has_key?(info, :method)
    assert Map.has_key?(info, :version)
  end
end
