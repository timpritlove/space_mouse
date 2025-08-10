#!/usr/bin/env elixir

# Comprehensive SpaceMouse Test Script
# Run with: mix run test_spacemouse.exs

defmodule SpaceMouseTester do
  require Logger

  def run_comprehensive_test do
    IO.puts """
    
    🚀 =================================
       SpaceNavigator Comprehensive Test
    =================================
    
    This will test:
    ✓ Device connection
    ✓ LED control (on/off)
    ✓ Motion events (move your SpaceMouse!)
    ✓ Button events (press the buttons!)
    ✓ Disconnection handling (unplug/replug test)
    
    """

    # Start the system
    IO.puts "🔧 Starting SpaceNavigator..."
    :ok = SpaceNavigator.start_monitoring()
    SpaceNavigator.subscribe()
    
    # Wait for connection
    wait_for_connection()
    
    # Test LED control
    test_led_control()
    
    # Test motion and button events
    test_events()
    
    # Test disconnection handling
    test_disconnection()
    
    IO.puts "\n✅ All tests completed!"
  end

  defp wait_for_connection do
    IO.puts "⏳ Waiting for SpaceMouse connection..."
    
    case wait_for_message({:spacemouse_connected, :_}, 5000) do
      {:ok, device_info} ->
        IO.puts "✅ SpaceMouse connected: #{inspect(device_info)}"
        platform = SpaceNavigator.platform_info()
        IO.puts "📋 Platform: #{inspect(platform)}"
        
      :timeout ->
        IO.puts "❌ SpaceMouse not connected within 5 seconds"
        IO.puts "   Make sure your SpaceMouse is plugged in!"
        exit(:device_not_connected)
    end
  end

  defp test_led_control do
    IO.puts "\n💡 Testing LED Control..."
    
    # Turn LED on
    IO.puts "🔆 Turning LED ON..."
    :ok = SpaceNavigator.set_led(:on)
    {:ok, state} = SpaceNavigator.get_led_state()
    IO.puts "   LED State: #{state}"
    Process.sleep(2000)
    
    # Turn LED off
    IO.puts "🔅 Turning LED OFF..."
    :ok = SpaceNavigator.set_led(:off)
    {:ok, state} = SpaceNavigator.get_led_state()
    IO.puts "   LED State: #{state}"
    Process.sleep(2000)
    
    # Turn LED on again
    IO.puts "🔆 Turning LED ON again..."
    :ok = SpaceNavigator.set_led(:on)
    {:ok, state} = SpaceNavigator.get_led_state()
    IO.puts "   LED State: #{state}"
    
    IO.puts "✅ LED control test complete!"
  end

  defp test_events do
    IO.puts """
    
    🎮 Testing Motion and Button Events
    
    Instructions:
    1. Move your SpaceMouse in different directions
    2. Press both buttons on the SpaceMouse
    3. Watch the real-time event display below
    4. Press Ctrl+C when done testing
    
    Event Display:
    ==============
    """
    
    event_loop(%{motion_count: 0, button_count: 0})
  end

  defp event_loop(stats) do
    receive do
      {:spacemouse_motion, motion} ->
        display_motion(motion)
        new_stats = %{stats | motion_count: stats.motion_count + 1}
        
        if rem(new_stats.motion_count, 10) == 0 do
          IO.puts "📊 Stats: #{new_stats.motion_count} motion events, #{new_stats.button_count} button events"
        end
        
        event_loop(new_stats)
        
      {:spacemouse_button, button} ->
        display_button(button)
        new_stats = %{stats | button_count: stats.button_count + 1}
        event_loop(new_stats)
        
      {:spacemouse_disconnected, info} ->
        IO.puts "\n🔌 SpaceMouse disconnected: #{inspect(info)}"
        IO.puts "⏳ Waiting for reconnection..."
        event_loop(stats)
        
      {:spacemouse_connected, info} ->
        IO.puts "\n🔌 SpaceMouse reconnected: #{inspect(info)}"
        event_loop(stats)
        
    after
      100 ->
        event_loop(stats)
    end
  end

  defp display_motion(%{x: x, y: y, z: z, rx: rx, ry: ry, rz: rz}) do
    # Only display significant motion to avoid spam
    if significant_motion?(%{x: x, y: y, z: z, rx: rx, ry: ry, rz: rz}) do
      IO.write "\r🎯 Motion: "
      IO.write "X:#{format_value(x)} Y:#{format_value(y)} Z:#{format_value(z)} "
      IO.write "RX:#{format_value(rx)} RY:#{format_value(ry)} RZ:#{format_value(rz)}"
      IO.write "          " # Clear any leftover text
    end
  end

  defp display_button(%{id: id, state: state}) do
    icon = if state == :pressed, do: "🔴", else: "⚪"
    IO.puts "\n#{icon} Button #{id}: #{state}"
  end

  defp significant_motion?(%{x: x, y: y, z: z, rx: rx, ry: ry, rz: rz}) do
    threshold = 100
    abs(x) > threshold or abs(y) > threshold or abs(z) > threshold or
    abs(rx) > threshold or abs(ry) > threshold or abs(rz) > threshold
  end

  defp format_value(val) when val >= 0, do: String.pad_leading("#{val}", 6)
  defp format_value(val), do: String.pad_leading("#{val}", 6)

  defp test_disconnection do
    IO.puts """
    
    🔌 Testing Disconnection/Reconnection
    
    Instructions:
    1. Unplug your SpaceMouse now
    2. Wait 3 seconds
    3. Plug it back in
    4. Observe the reconnection behavior
    
    """
    
    IO.puts "⏳ Waiting for disconnection event..."
    
    case wait_for_message({:spacemouse_disconnected, :_}, 30000) do
      {:ok, _info} ->
        IO.puts "✅ Disconnection detected!"
        IO.puts "⏳ Waiting for reconnection..."
        
        case wait_for_message({:spacemouse_connected, :_}, 30000) do
          {:ok, _info} ->
            IO.puts "✅ Reconnection successful!"
            IO.puts "🔆 Testing LED after reconnection..."
            SpaceNavigator.set_led(:on)
            Process.sleep(1000)
            SpaceNavigator.set_led(:off)
            Process.sleep(1000)
            SpaceNavigator.set_led(:on)
            IO.puts "✅ LED works after reconnection!"
            
          :timeout ->
            IO.puts "⚠️  No reconnection within 30 seconds (this is okay if you didn't plug it back in)"
        end
        
      :timeout ->
        IO.puts "⚠️  No disconnection within 30 seconds (test skipped - device stayed connected)"
    end
  end

  defp wait_for_message({type, pattern}, timeout) do
    receive do
      {^type, data} = msg ->
        if pattern == :_ or data == pattern do
          {:ok, data}
        else
          wait_for_message({type, pattern}, timeout)
        end
        
    after
      timeout -> :timeout
    end
  end
end

# Run the test
SpaceMouseTester.run_comprehensive_test()
