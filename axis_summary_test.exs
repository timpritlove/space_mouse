#!/usr/bin/env elixir

# Axis Summary Test - Shows changes per axis per second
# Run with: mix run axis_summary_test.exs

defmodule AxisSummaryAnalyzer do
  require Logger

  def run_test do
    IO.puts """
    
    📊 ===============================
       Axis Summary Test
    ===============================
    
    This test summarizes motion events per axis per second:
    
    • Shows min/max/average values per axis
    • Counts how many events affected each axis
    • Reports every 1 second
    • Clean, concise output
    
    """

    # Start the system
    IO.puts "🔧 Starting SpaceNavigator..."
    :ok = SpaceNavigator.start_monitoring()
    SpaceNavigator.subscribe()
    
    # Wait for connection
    wait_for_connection()
    
    IO.puts """
    
    📊 Starting axis summary analysis...
    Reports will show every 1 second with per-axis statistics.
    
    """
    
    # Schedule first report
    schedule_summary_report()
    
    # Start analysis loop
    axis_summary_loop(%{
      x_values: [],
      y_values: [],
      z_values: [],
      rx_values: [],
      ry_values: [],
      rz_values: [],
      total_events: 0,
      button_events: 0,
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

  defp schedule_summary_report do
    Process.send_after(self(), :print_summary, 1000)
  end

  defp axis_summary_loop(stats) do
    receive do
      {:spacemouse_motion, %{x: x, y: y, z: z, rx: rx, ry: ry, rz: rz}} ->
        # Collect values for each axis (only non-zero values)
        new_stats = %{
          stats |
          x_values: if(x != 0, do: [x | stats.x_values], else: stats.x_values),
          y_values: if(y != 0, do: [y | stats.y_values], else: stats.y_values),
          z_values: if(z != 0, do: [z | stats.z_values], else: stats.z_values),
          rx_values: if(rx != 0, do: [rx | stats.rx_values], else: stats.rx_values),
          ry_values: if(ry != 0, do: [ry | stats.ry_values], else: stats.ry_values),
          rz_values: if(rz != 0, do: [rz | stats.rz_values], else: stats.rz_values),
          total_events: stats.total_events + 1
        }
        
        axis_summary_loop(new_stats)
        
      {:spacemouse_button, _button} ->
        new_stats = %{stats | button_events: stats.button_events + 1}
        axis_summary_loop(new_stats)
        
      :print_summary ->
        # Print summary and reset
        print_axis_summary(stats)
        
        # Schedule next report
        schedule_summary_report()
        
        # Reset stats
        reset_stats = %{
          x_values: [],
          y_values: [],
          z_values: [],
          rx_values: [],
          ry_values: [],
          rz_values: [],
          total_events: 0,
          button_events: 0,
          start_time: System.monotonic_time(:millisecond)
        }
        
        axis_summary_loop(reset_stats)
        
    after
      100 ->
        axis_summary_loop(stats)
    end
  end

  defp print_axis_summary(stats) do
    current_time = System.monotonic_time(:millisecond)
    elapsed_ms = current_time - stats.start_time
    elapsed_seconds = elapsed_ms / 1000.0
    
    events_per_second = if elapsed_seconds > 0, do: stats.total_events / elapsed_seconds, else: 0
    
    timestamp = DateTime.utc_now() |> DateTime.to_time() |> Time.to_string() |> String.slice(0, 8)
    
    IO.puts """
    
    📊 [#{timestamp}] === AXIS SUMMARY (#{:erlang.float_to_binary(elapsed_seconds, decimals: 1)}s) ===
    📊 Total Events: #{stats.total_events} (#{:erlang.float_to_binary(events_per_second, decimals: 1)}/sec)
    📊 Button Events: #{stats.button_events}
    📊 
    📊 Translation Axes:
    📊   X: #{format_axis_summary(stats.x_values)}
    📊   Y: #{format_axis_summary(stats.y_values)}
    📊   Z: #{format_axis_summary(stats.z_values)}
    📊 
    📊 Rotation Axes:
    📊   RX: #{format_axis_summary(stats.rx_values)}
    📊   RY: #{format_axis_summary(stats.ry_values)}
    📊   RZ: #{format_axis_summary(stats.rz_values)}
    📊 ================================================================
    """
  end

  defp format_axis_summary([]) do
    "inactive"
  end

  defp format_axis_summary(values) do
    count = length(values)
    min_val = Enum.min(values)
    max_val = Enum.max(values)
    avg_val = Enum.sum(values) / count
    
    range_str = if min_val == max_val do
      "#{min_val}"
    else
      "#{min_val} to #{max_val}"
    end
    
    "#{count} events, range: #{range_str}, avg: #{:erlang.float_to_binary(avg_val, decimals: 1)}"
  end
end

# Instructions and start
IO.puts """
📊 AXIS SUMMARY TEST INSTRUCTIONS:

This test provides clean per-axis summaries every second:

• Shows which axes are active
• Reports min/max/average values per axis
• Counts events per axis
• Much cleaner than individual event logging

Test different movements:
1. Single axis movements (X, Y, Z, RX, RY, RZ)
2. Combined movements
3. Gentle vs. forceful movements
4. Button presses

Starting...
"""

AxisSummaryAnalyzer.run_test()
