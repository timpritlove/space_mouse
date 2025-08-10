#!/usr/bin/env elixir

# Detailed SpaceMouse Test Script - Shows ALL motion events
# Run with: mix run detailed_test.exs

defmodule DetailedSpaceMouseTester do
  require Logger

  def run_detailed_test do
    IO.puts """
    
    🔍 =================================
       SpaceNavigator DETAILED Test
    =================================
    
    This shows ALL motion events in real-time:
    ✓ Translation events (X, Y, Z movement)
    ✓ Rotation events (RX, RY, RZ rotation)  
    ✓ Button events (press/release)
    ✓ Motion categorization and analysis
    
    Move your SpaceMouse in different ways:
    📐 Translation: Push/pull in X, Y, Z directions
    🔄 Rotation: Twist around X, Y, Z axes
    🔘 Buttons: Press both buttons
    
    """

    # Start the system
    IO.puts "🔧 Starting SpaceNavigator..."
    :ok = SpaceNavigator.start_monitoring()
    SpaceNavigator.subscribe()
    
    # Wait for connection
    wait_for_connection()
    
    # Test LED to show connection
    test_led_indication()
    
    # Start detailed event monitoring
    start_detailed_monitoring()
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
        exit(:device_not_connected)
    end
  end

  defp test_led_indication do
    IO.puts "\n💡 LED Connection Test..."
    SpaceNavigator.set_led(:on)
    Process.sleep(500)
    SpaceNavigator.set_led(:off)
    Process.sleep(500)
    SpaceNavigator.set_led(:on)
    IO.puts "✅ LED indicates connection!"
  end

  defp start_detailed_monitoring do
    IO.puts """
    
    🎮 Detailed Motion Monitoring Active
    =====================================
    
    Legend:
    📐 TRANS = Translation (linear movement)
    🔄 ROT   = Rotation (angular movement)
    🔘 BTN   = Button press/release
    🔌 CONN  = Connection events
    
    Real-time Events:
    """
    
    detailed_event_loop(%{
      motion_count: 0, 
      button_count: 0,
      translation_count: 0,
      rotation_count: 0,
      last_motion_type: nil
    })
  end

  defp detailed_event_loop(stats) do
    receive do
      {:spacemouse_motion, motion} ->
        motion_type = categorize_motion(motion)
        display_detailed_motion(motion, motion_type)
        
        new_stats = %{
          stats | 
          motion_count: stats.motion_count + 1,
          translation_count: stats.translation_count + (if motion_type in [:translation, :both], do: 1, else: 0),
          rotation_count: stats.rotation_count + (if motion_type in [:rotation, :both], do: 1, else: 0),
          last_motion_type: motion_type
        }
        
        # Show stats every 20 events
        if rem(new_stats.motion_count, 20) == 0 do
          show_detailed_stats(new_stats)
        end
        
        detailed_event_loop(new_stats)
        
      {:spacemouse_button, button} ->
        display_detailed_button(button)
        new_stats = %{stats | button_count: stats.button_count + 1}
        detailed_event_loop(new_stats)
        
      {:spacemouse_disconnected, info} ->
        IO.puts "\n🔌 DISCONNECTED: #{inspect(info)}"
        detailed_event_loop(stats)
        
      {:spacemouse_connected, info} ->
        IO.puts "\n🔌 RECONNECTED: #{inspect(info)}"
        detailed_event_loop(stats)
        
    after
      100 ->
        detailed_event_loop(stats)
    end
  end

  defp categorize_motion(%{x: x, y: y, z: z, rx: rx, ry: ry, rz: rz}) do
    trans_threshold = 5   # Very low threshold to catch subtle movements
    rot_threshold = 3     # Even lower for rotation
    
    has_translation = abs(x) > trans_threshold or abs(y) > trans_threshold or abs(z) > trans_threshold
    has_rotation = abs(rx) > rot_threshold or abs(ry) > rot_threshold or abs(rz) > rot_threshold
    
    cond do
      has_translation and has_rotation -> :both
      has_translation -> :translation
      has_rotation -> :rotation
      true -> :minimal
    end
  end

  defp display_detailed_motion(motion, motion_type) do
    %{x: x, y: y, z: z, rx: rx, ry: ry, rz: rz} = motion
    
    # Motion type indicator
    type_icon = case motion_type do
      :translation -> "📐"
      :rotation -> "🔄"
      :both -> "📐🔄"
      :minimal -> "·"
    end
    
    # Format the display
    timestamp = DateTime.utc_now() |> DateTime.to_time() |> Time.to_string() |> String.slice(0, 8)
    
    case motion_type do
      :minimal ->
        # Show minimal motion briefly
        IO.write "\r#{type_icon} [#{timestamp}] minimal motion                                    "
        
      _ ->
        # Show detailed motion with values
        IO.write "\r#{type_icon} [#{timestamp}] "
        
        if motion_type in [:translation, :both] do
          IO.write "TRANS(X:#{format_compact(x)} Y:#{format_compact(y)} Z:#{format_compact(z)}) "
        end
        
        if motion_type in [:rotation, :both] do
          IO.write "ROT(RX:#{format_compact(rx)} RY:#{format_compact(ry)} RZ:#{format_compact(rz)}) "
        end
        
        IO.write "                    " # Clear trailing text
    end
  end

  defp display_detailed_button(%{id: id, state: state}) do
    timestamp = DateTime.utc_now() |> DateTime.to_time() |> Time.to_string() |> String.slice(0, 8)
    icon = if state == :pressed, do: "🔴", else: "⚪"
    IO.puts "\n🔘 [#{timestamp}] #{icon} Button #{id}: #{String.upcase(to_string(state))}"
  end

  defp show_detailed_stats(stats) do
    IO.puts "\n"
    IO.puts "📊 ===== MOTION STATISTICS ====="
    IO.puts "📊 Total Events: #{stats.motion_count}"
    IO.puts "📊 📐 Translation: #{stats.translation_count} (#{round(stats.translation_count/stats.motion_count*100)}%)"
    IO.puts "📊 🔄 Rotation: #{stats.rotation_count} (#{round(stats.rotation_count/stats.motion_count*100)}%)"
    IO.puts "📊 🔘 Buttons: #{stats.button_count}"
    IO.puts "📊 Last Motion Type: #{stats.last_motion_type}"
    IO.puts "📊 =============================="
    IO.puts ""
  end

  defp format_compact(val) when val >= 0 and val < 1000, do: String.pad_leading("#{val}", 3)
  defp format_compact(val) when val < 0 and val > -1000, do: String.pad_leading("#{val}", 4) 
  defp format_compact(val) when val >= 1000, do: "999+"
  defp format_compact(val) when val <= -1000, do: "-999"

  defp wait_for_message({type, pattern}, timeout) do
    receive do
      {^type, data} = _msg ->
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

# Instructions
IO.puts """
🎯 DETAILED MOTION TEST INSTRUCTIONS:

1. This test shows ALL motion events, even tiny ones
2. Try these specific movements to see different event types:

   📐 TRANSLATION TESTS:
   • Push the knob away from you (Z+)
   • Pull the knob toward you (Z-)  
   • Push left/right (X-/X+)
   • Push up/down (Y+/Y-)

   🔄 ROTATION TESTS:
   • Twist the knob clockwise/counterclockwise (RZ)
   • Tilt the knob forward/backward (RX)
   • Tilt the knob left/right (RY)

   🔘 BUTTON TESTS:
   • Press the left button
   • Press the right button

3. Watch how events are categorized in real-time!
4. Press Ctrl+C when done testing

Starting test...
"""

# Run the detailed test
DetailedSpaceMouseTester.run_detailed_test()
