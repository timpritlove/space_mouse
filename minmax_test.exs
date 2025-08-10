#!/usr/bin/env elixir

# Min/Max Range Test - Discovers the full range of each 6DOF axis
# Run with: mix run minmax_test.exs

defmodule MinMaxAnalyzer do
  require Logger

  def run_test do
    IO.puts """
    
    📏 ===============================
       6DOF Min/Max Range Discovery
    ===============================
    
    This test tracks the minimum and maximum values for each axis:
    
    • Continuously updates min/max for each axis
    • Shows current ranges and extremes
    • Reports every 5 seconds
    • Run this while moving SpaceMouse in all directions!
    
    """

    # Start the system
    IO.puts "🔧 Starting SpaceNavigator..."
    :ok = SpaceNavigator.start_monitoring()
    SpaceNavigator.subscribe()
    
    # Wait for connection
    wait_for_connection()
    
    IO.puts """
    
    📏 Starting min/max tracking...
    Move your SpaceMouse in ALL directions to discover full ranges:
    
    🔄 Rotate around all axes (RX, RY, RZ)
    📐 Translate along all axes (X, Y, Z)  
    💪 Try gentle AND forceful movements
    ⏱️  Keep moving for accurate ranges!
    
    """
    
    # Schedule first report
    schedule_minmax_report()
    
    # Start tracking loop with initial "impossible" values
    minmax_tracking_loop(%{
      x_min: :infinity, x_max: :neg_infinity,
      y_min: :infinity, y_max: :neg_infinity,
      z_min: :infinity, z_max: :neg_infinity,
      rx_min: :infinity, rx_max: :neg_infinity,
      ry_min: :infinity, ry_max: :neg_infinity,
      rz_min: :infinity, rz_max: :neg_infinity,
      total_events: 0,
      non_zero_events: 0,
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

  defp schedule_minmax_report do
    Process.send_after(self(), :print_minmax, 5000)
  end

  defp minmax_tracking_loop(ranges) do
    receive do
      {:spacemouse_motion, %{x: x, y: y, z: z, rx: rx, ry: ry, rz: rz}} ->
        # Update min/max for each axis
        new_ranges = %{
          ranges |
          x_min: update_min(ranges.x_min, x),
          x_max: update_max(ranges.x_max, x),
          y_min: update_min(ranges.y_min, y),
          y_max: update_max(ranges.y_max, y),
          z_min: update_min(ranges.z_min, z),
          z_max: update_max(ranges.z_max, z),
          rx_min: update_min(ranges.rx_min, rx),
          rx_max: update_max(ranges.rx_max, rx),
          ry_min: update_min(ranges.ry_min, ry),
          ry_max: update_max(ranges.ry_max, ry),
          rz_min: update_min(ranges.rz_min, rz),
          rz_max: update_max(ranges.rz_max, rz),
          total_events: ranges.total_events + 1,
          non_zero_events: ranges.non_zero_events + (if any_non_zero?(x, y, z, rx, ry, rz), do: 1, else: 0)
        }
        
        minmax_tracking_loop(new_ranges)
        
      {:spacemouse_button, _button} ->
        # Ignore buttons for this test
        minmax_tracking_loop(ranges)
        
      :print_minmax ->
        # Print current ranges
        print_current_ranges(ranges)
        
        # Schedule next report
        schedule_minmax_report()
        
        minmax_tracking_loop(ranges)
        
    after
      100 ->
        minmax_tracking_loop(ranges)
    end
  end

  defp update_min(:infinity, value), do: value
  defp update_min(current_min, value) when value < current_min, do: value
  defp update_min(current_min, _value), do: current_min

  defp update_max(:neg_infinity, value), do: value
  defp update_max(current_max, value) when value > current_max, do: value
  defp update_max(current_max, _value), do: current_max

  defp any_non_zero?(x, y, z, rx, ry, rz) do
    x != 0 or y != 0 or z != 0 or rx != 0 or ry != 0 or rz != 0
  end

  defp print_current_ranges(ranges) do
    current_time = System.monotonic_time(:millisecond)
    elapsed_ms = current_time - ranges.start_time
    elapsed_seconds = elapsed_ms / 1000.0
    
    events_per_second = if elapsed_seconds > 0, do: ranges.total_events / elapsed_seconds, else: 0.0
    motion_percentage = if ranges.total_events > 0, do: (ranges.non_zero_events / ranges.total_events * 100), else: 0.0
    
    timestamp = DateTime.utc_now() |> DateTime.to_time() |> Time.to_string() |> String.slice(0, 8)
    
    IO.puts """
    
    📏 [#{timestamp}] === 6DOF RANGES (#{:erlang.float_to_binary(elapsed_seconds, decimals: 1)}s) ===
    📏 Events: #{ranges.total_events} total (#{:erlang.float_to_binary(events_per_second, decimals: 1)}/sec)
    📏 Motion: #{ranges.non_zero_events} active (#{:erlang.float_to_binary(motion_percentage, decimals: 1)}%)
    📏 
    📏 TRANSLATION RANGES:
    📏   X: #{format_range(ranges.x_min, ranges.x_max)} #{format_span(ranges.x_min, ranges.x_max)}
    📏   Y: #{format_range(ranges.y_min, ranges.y_max)} #{format_span(ranges.y_min, ranges.y_max)}
    📏   Z: #{format_range(ranges.z_min, ranges.z_max)} #{format_span(ranges.z_min, ranges.z_max)}
    📏 
    📏 ROTATION RANGES:
    📏   RX: #{format_range(ranges.rx_min, ranges.rx_max)} #{format_span(ranges.rx_min, ranges.rx_max)}
    📏   RY: #{format_range(ranges.ry_min, ranges.ry_max)} #{format_span(ranges.ry_min, ranges.ry_max)}
    📏   RZ: #{format_range(ranges.rz_min, ranges.rz_max)} #{format_span(ranges.rz_min, ranges.rz_max)}
    📏 ================================================================
    """
  end

  defp format_range(:infinity, :neg_infinity), do: "no data yet"
  defp format_range(:infinity, _max), do: "no data yet"
  defp format_range(_min, :neg_infinity), do: "no data yet"
  defp format_range(min, max), do: "#{min} to #{max}"

  defp format_span(:infinity, :neg_infinity), do: ""
  defp format_span(:infinity, _max), do: ""
  defp format_span(_min, :neg_infinity), do: ""
  defp format_span(min, max) when min == max, do: "(single value)"
  defp format_span(min, max), do: "(span: #{max - min})"
end

# Instructions and start
IO.puts """
📏 MIN/MAX RANGE DISCOVERY INSTRUCTIONS:

This test will discover the full operating range of your SpaceMouse.

IMPORTANT: Move the SpaceMouse in ALL possible ways:

🔄 ROTATIONS:
   • Twist left/right (RZ)
   • Tilt forward/back (RX)  
   • Roll left/right (RY)

📐 TRANSLATIONS:
   • Left/right (X)
   • Forward/back (Y)
   • Up/down (Z)

💪 FORCE LEVELS:
   • Gentle touches
   • Medium pressure
   • Maximum force (within reason!)

⏱️  Keep moving for at least 30-60 seconds to get accurate ranges.
The test reports every 5 seconds with current min/max values.

Starting...
"""

MinMaxAnalyzer.run_test()
