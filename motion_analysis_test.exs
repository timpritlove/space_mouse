#!/usr/bin/env elixir

# Motion Event Analysis Test - Analyze individual motion event structure
# Run with: mix run motion_analysis_test.exs

defmodule MotionAnalyzer do
  require Logger

  def run_test do
    IO.puts """
    
    🔍 ===============================
       Motion Event Analysis Test
    ===============================
    
    This test analyzes the structure of individual motion events:
    
    • Shows each motion event separately
    • Displays all 6 DOF values per event
    • Identifies which axes are active in each event
    • Counts events by axis combination
    
    """

    # Start the system
    IO.puts "🔧 Starting SpaceNavigator..."
    :ok = SpaceNavigator.start_monitoring()
    SpaceNavigator.subscribe()
    
    # Wait for connection
    wait_for_connection()
    
    IO.puts """
    
    🔍 Starting motion event analysis...
    Each motion event will be shown individually.
    Try different movements to see the patterns!
    
    Legend:
    • X/Y/Z = Translation axes
    • RX/RY/RZ = Rotation axes  
    • [ACTIVE] = Non-zero values
    • [ZERO] = Zero values
    
    """
    
    # Start analysis loop
    motion_analysis_loop(%{
      event_count: 0,
      axis_combinations: %{},
      start_time: System.monotonic_time(:millisecond)
    })
  end

  defp wait_for_connection do
    IO.puts "⏳ Waiting for SpaceMouse connection..."
    
    receive do
      {:spacemouse_connected, device_info} ->
        IO.puts "✅ SpaceMouse connected: #{inspect(device_info)}"
        
    after
      5000 ->
        IO.puts "❌ SpaceMouse not connected within 5 seconds"
        exit(:device_not_connected)
    end
  end

  defp motion_analysis_loop(stats) do
    receive do
      {:spacemouse_motion, motion} ->
        # Analyze this specific motion event
        analyze_motion_event(motion, stats.event_count + 1)
        
        # Update statistics
        axis_combo = get_active_axes(motion)
        updated_combos = Map.update(stats.axis_combinations, axis_combo, 1, &(&1 + 1))
        
        new_stats = %{
          stats | 
          event_count: stats.event_count + 1,
          axis_combinations: updated_combos
        }
        
        # Print summary every 50 events
        if rem(new_stats.event_count, 50) == 0 do
          print_analysis_summary(new_stats)
        end
        
        motion_analysis_loop(new_stats)
        
      {:spacemouse_button, button} ->
        IO.puts "🔘 BUTTON: #{inspect(button)}"
        motion_analysis_loop(stats)
        
      other ->
        # Ignore other events for this test
        motion_analysis_loop(stats)
        
    after
      100 ->
        motion_analysis_loop(stats)
    end
  end

  defp analyze_motion_event(%{x: x, y: y, z: z, rx: rx, ry: ry, rz: rz}, event_num) do
    # Format each axis value with active/zero indicator
    x_str = format_axis_value("X", x)
    y_str = format_axis_value("Y", y)
    z_str = format_axis_value("Z", z)
    rx_str = format_axis_value("RX", rx)
    ry_str = format_axis_value("RY", ry)
    rz_str = format_axis_value("RZ", rz)
    
    # Count active axes
    active_count = count_active_axes(%{x: x, y: y, z: z, rx: rx, ry: ry, rz: rz})
    
    # Determine event type
    event_type = categorize_motion_event(%{x: x, y: y, z: z, rx: rx, ry: ry, rz: rz})
    
    IO.puts "🎯 Event #{String.pad_leading("#{event_num}", 3)} [#{event_type}] (#{active_count}/6 active): #{x_str} #{y_str} #{z_str} #{rx_str} #{ry_str} #{rz_str}"
  end

  defp format_axis_value(axis_name, value) do
    if value == 0 do
      "#{axis_name}:#{String.pad_leading("0", 6)}[ZERO]"
    else
      "#{axis_name}:#{String.pad_leading("#{value}", 6)}[ACTIVE]"
    end
  end

  defp count_active_axes(%{x: x, y: y, z: z, rx: rx, ry: ry, rz: rz}) do
    [x, y, z, rx, ry, rz]
    |> Enum.count(&(&1 != 0))
  end

  defp get_active_axes(%{x: x, y: y, z: z, rx: rx, ry: ry, rz: rz}) do
    active = []
    active = if x != 0, do: ["X" | active], else: active
    active = if y != 0, do: ["Y" | active], else: active
    active = if z != 0, do: ["Z" | active], else: active
    active = if rx != 0, do: ["RX" | active], else: active
    active = if ry != 0, do: ["RY" | active], else: active
    active = if rz != 0, do: ["RZ" | active], else: active
    
    case active do
      [] -> "none"
      axes -> Enum.join(Enum.reverse(axes), "+")
    end
  end

  defp categorize_motion_event(%{x: x, y: y, z: z, rx: rx, ry: ry, rz: rz}) do
    has_translation = x != 0 or y != 0 or z != 0
    has_rotation = rx != 0 or ry != 0 or rz != 0
    
    cond do
      has_translation and has_rotation -> "MIXED"
      has_translation -> "TRANS"
      has_rotation -> "ROT"
      true -> "ZERO"
    end
  end

  defp print_analysis_summary(stats) do
    current_time = System.monotonic_time(:millisecond)
    elapsed_ms = current_time - stats.start_time
    elapsed_seconds = elapsed_ms / 1000.0
    
    events_per_second = if elapsed_seconds > 0, do: stats.event_count / elapsed_seconds, else: 0
    
    IO.puts """
    
    📊 === MOTION ANALYSIS SUMMARY (#{stats.event_count} events, #{:erlang.float_to_binary(elapsed_seconds, decimals: 1)}s) ===
    📊 Event Rate: #{:erlang.float_to_binary(events_per_second, decimals: 1)} events/sec
    📊 
    📊 Axis Combinations (how often each combination appears):
    """
    
    stats.axis_combinations
    |> Enum.sort_by(fn {_combo, count} -> count end, :desc)
    |> Enum.take(10)  # Show top 10 combinations
    |> Enum.each(fn {combo, count} ->
      percentage = (count / stats.event_count * 100) |> :erlang.float_to_binary(decimals: 1)
      IO.puts "📊   #{String.pad_trailing(combo, 15)}: #{String.pad_leading("#{count}", 4)} events (#{percentage}%)"
    end)
    
    IO.puts "📊 ================================================================"
    IO.puts ""
  end
end

# Instructions and start
IO.puts """
🔍 MOTION ANALYSIS INSTRUCTIONS:

This test shows you the structure of individual motion events.

Test scenarios:
1. Move only horizontally (X-axis) - see if other axes are zero
2. Move only vertically (Y-axis) - see if other axes are zero  
3. Push/pull only (Z-axis) - see if other axes are zero
4. Rotate only around one axis - see rotation isolation
5. Combined movements - see which axes are active together

Each event shows all 6 values (X,Y,Z,RX,RY,RZ) and which are active.

Starting...
"""

MotionAnalyzer.run_test()
