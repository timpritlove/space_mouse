#!/usr/bin/env elixir

# Raw Event Counter Test - No filtering, pure statistics
# Run with: mix run raw_event_test.exs

defmodule RawEventCounter do
  require Logger

  def run_test do
    IO.puts """
    
    📊 ===============================
       Raw Event Counter Test
    ===============================
    
    This test receives EVERY event without filtering
    and reports statistics every second:
    
    • Total events per second
    • Motion events breakdown
    • Button events breakdown
    • Connection events
    
    """

    # Start the system
    IO.puts "🔧 Starting SpaceNavigator..."
    :ok = SpaceNavigator.start_monitoring()
    SpaceNavigator.subscribe()
    
    # Wait for connection
    wait_for_connection()
    
    IO.puts """
    
    📊 Starting raw event counting...
    Reports will show every 1 second.
    Move your SpaceMouse to generate events!
    
    """
    
    # Start the statistics timer
    schedule_stats_report()
    
    # Start event counting loop
    event_counting_loop(%{
      motion_events: 0,
      button_events: 0,
      connection_events: 0,
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

  defp schedule_stats_report do
    Process.send_after(self(), :print_stats, 1000)
  end

  defp event_counting_loop(stats) do
    receive do
      {:spacemouse_motion, _motion} ->
        # Count every single motion event - NO FILTERING
        new_stats = %{stats | motion_events: stats.motion_events + 1}
        event_counting_loop(new_stats)
        
      {:spacemouse_button, _button} ->
        # Count every button event
        new_stats = %{stats | button_events: stats.button_events + 1}
        event_counting_loop(new_stats)
        
      {:spacemouse_connected, _info} ->
        # Count connection events
        new_stats = %{stats | connection_events: stats.connection_events + 1}
        event_counting_loop(new_stats)
        
      {:spacemouse_disconnected, _info} ->
        # Count disconnection events
        new_stats = %{stats | connection_events: stats.connection_events + 1}
        event_counting_loop(new_stats)
        
      :print_stats ->
        # Print statistics and reset counters
        print_stats_report(stats)
        
        # Schedule next report
        schedule_stats_report()
        
        # Reset counters but keep start time
        reset_stats = %{
          motion_events: 0,
          button_events: 0,
          connection_events: 0,
          start_time: System.monotonic_time(:millisecond)
        }
        
        event_counting_loop(reset_stats)
        
    after
      100 ->
        # Continue loop
        event_counting_loop(stats)
    end
  end

  defp print_stats_report(stats) do
    current_time = System.monotonic_time(:millisecond)
    elapsed_ms = current_time - stats.start_time
    elapsed_seconds = elapsed_ms / 1000.0
    
    total_events = stats.motion_events + stats.button_events + stats.connection_events
    events_per_second = if elapsed_seconds > 0, do: total_events / elapsed_seconds, else: 0
    
    timestamp = DateTime.utc_now() |> DateTime.to_time() |> Time.to_string() |> String.slice(0, 8)
    
    IO.puts """
    
    📊 [#{timestamp}] === EVENT STATISTICS (Last #{:erlang.float_to_binary(elapsed_seconds, decimals: 1)}s) ===
    📊 Total Events: #{total_events}
    📊 Events/Second: #{:erlang.float_to_binary(events_per_second, decimals: 1)}
    📊 
    📊 Event Breakdown:
    📊   🎯 Motion Events:     #{stats.motion_events}
    📊   🔘 Button Events:     #{stats.button_events}  
    📊   🔌 Connection Events: #{stats.connection_events}
    📊 
    📊 Motion Rate: #{:erlang.float_to_binary(stats.motion_events / elapsed_seconds, decimals: 1)} events/sec
    📊 ================================================================
    """
  end
end

# Instructions and start
IO.puts """
🎯 RAW EVENT TEST INSTRUCTIONS:

This test counts EVERY event with no filtering whatsoever.

Test scenarios:
1. Leave SpaceMouse untouched - see baseline event rate
2. Gently touch the knob - see motion sensitivity  
3. Move in different directions - see event generation rate
4. Press buttons - see button event counting
5. Try disconnecting/reconnecting - see connection events

Press Ctrl+C to stop the test.

Starting...
"""

RawEventCounter.run_test()
