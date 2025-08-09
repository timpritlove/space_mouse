defmodule SpaceNavigator.LiveDemo do
  @moduledoc """
  Live demonstration of SpaceMouse motion tracking.
  
  This module starts the HID monitor and prints out every movement
  and button event from the SpaceMouse in real-time.
  """

  require Logger

  @doc """
  Start monitoring and print all SpaceMouse events live.
  """
  def start_live_monitoring do
    Logger.info("🚀 Starting SpaceMouse Live Demo!")
    Logger.info("Move your SpaceMouse to see events...")
    Logger.info("Press Ctrl+C to stop")
    
    # Start the HID monitor
    {:ok, _pid} = SpaceNavigator.HidMonitor.start_link()
    
    # Subscribe to events
    :ok = SpaceNavigator.HidMonitor.subscribe()
    
    # Start monitoring
    case SpaceNavigator.HidMonitor.start_monitoring() do
      {:ok, :started} ->
        Logger.info("✓ HID monitoring started successfully!")
        Logger.info("🎮 Ready to track SpaceMouse motion!")
        
        # Listen for events indefinitely
        receive_and_print_events()
        
      {:error, reason} ->
        Logger.error("❌ Failed to start monitoring: #{inspect(reason)}")
        
        case reason do
          :spacemouse_not_found ->
            Logger.info("💡 Make sure your SpaceMouse Compact is connected")
            
          :no_helper ->
            Logger.info("💡 C helper program not found - run mix compile first")
            
          _ ->
            Logger.info("💡 Check that your SpaceMouse is working with other apps")
        end
    end
  end

  defp receive_and_print_events do
    receive do
      {:spacemouse_hid_event, {:motion, event}} ->
        print_motion_event(event)
        receive_and_print_events()
        
      {:spacemouse_hid_event, {:button, event}} ->
        print_button_event(event)
        receive_and_print_events()
        
      other ->
        Logger.debug("Received: #{inspect(other)}")
        receive_and_print_events()
    end
  end

  defp print_motion_event(event) do
    # Create a visual representation of the motion
    value = event.value
    
    # Create a simple bar chart representation
    bar = create_motion_bar(value)
    
    # Color coding for different axes
    axis_info = case event.axis do
      :x  -> {"🔴 X-Trans", value}  # Red for X translation
      :y  -> {"🟢 Y-Trans", value}  # Green for Y translation  
      :z  -> {"🔵 Z-Trans", value}  # Blue for Z translation
      :rx -> {"🟠 X-Rot  ", value}  # Orange for X rotation
      :ry -> {"🟡 Y-Rot  ", value}  # Yellow for Y rotation
      :rz -> {"🟣 Z-Rot  ", value}  # Purple for Z rotation
      _   -> {"❓ Unknown", value}
    end
    
    {axis_name, _} = axis_info
    
    # Print the motion with timestamp
    timestamp = format_timestamp(event.timestamp)
    IO.puts("#{timestamp} #{axis_name}: #{value} #{bar}")
  end

  defp print_button_event(event) do
    timestamp = format_timestamp(event.timestamp)
    action = if event.pressed, do: "PRESSED", else: "RELEASED"
    IO.puts("#{timestamp} 🔘 Button #{event.button}: #{action}")
  end

  defp create_motion_bar(value) do
    # Create a visual bar representation of the motion value
    # Scale to fit in reasonable terminal width
    max_bar_length = 20
    
    cond do
      value == 0 ->
        "│"
        
      value > 0 ->
        # Positive values - right side bar
        scaled = min(abs(value), 350) # SpaceMouse range is roughly -350 to 350
        bar_length = round(scaled / 350 * max_bar_length)
        "│" <> String.duplicate("█", bar_length)
        
      value < 0 ->
        # Negative values - left side bar  
        scaled = min(abs(value), 350)
        bar_length = round(scaled / 350 * max_bar_length)
        String.duplicate("█", bar_length) <> "│"
    end
  end

  defp format_timestamp(timestamp) do
    # Convert monotonic time to readable format
    # Just show milliseconds for simplicity
    ms = rem(timestamp, 10000)
    "#{String.pad_leading(Integer.to_string(ms), 4, "0")}ms"
  end

  @doc """
  Start with motion aggregation - combine all 6DOF into one update.
  """
  def start_with_aggregation do
    Logger.info("🚀 Starting SpaceMouse 6DOF Aggregated Demo!")
    
    # Start the monitor
    {:ok, _pid} = SpaceNavigator.HidMonitor.start_link()
    :ok = SpaceNavigator.HidMonitor.subscribe()
    
    case SpaceNavigator.HidMonitor.start_monitoring() do
      {:ok, :started} ->
        Logger.info("✓ Monitoring started - showing combined 6DOF motion")
        
        # Use a GenServer to aggregate motion over time windows
        {:ok, aggregator_pid} = start_motion_aggregator()
        receive_and_aggregate_events(aggregator_pid)
        
      {:error, reason} ->
        Logger.error("Failed to start: #{inspect(reason)}")
    end
  end

  defp start_motion_aggregator do
    # Simple GenServer to collect motion over time windows
    Agent.start_link(fn -> 
      %{x: 0, y: 0, z: 0, rx: 0, ry: 0, rz: 0, last_update: 0}
    end)
  end

  defp receive_and_aggregate_events(aggregator_pid) do
    receive do
      {:spacemouse_hid_event, {:motion, event}} ->
        # Update the aggregated state
        Agent.update(aggregator_pid, fn state ->
          updated_state = Map.put(state, event.axis, event.value)
          Map.put(updated_state, :last_update, event.timestamp)
        end)
        
        # Print combined state every 50ms
        current_time = System.monotonic_time(:millisecond)
        last_print = Agent.get(aggregator_pid, &Map.get(&1, :last_print, 0))
        
        if current_time - last_print > 50 do
          Agent.update(aggregator_pid, &Map.put(&1, :last_print, current_time))
          print_6dof_state(Agent.get(aggregator_pid, & &1))
        end
        
        receive_and_aggregate_events(aggregator_pid)
        
      {:spacemouse_hid_event, {:button, event}} ->
        print_button_event(event)
        receive_and_aggregate_events(aggregator_pid)
        
      _ ->
        receive_and_aggregate_events(aggregator_pid)
    end
  end

  defp print_6dof_state(state) do
    timestamp = format_timestamp(state.last_update)
    
    # Format all 6 axes in one line
    IO.puts("#{timestamp} 🎮 6DOF: " <>
            "X:#{format_value(state.x)} " <>
            "Y:#{format_value(state.y)} " <> 
            "Z:#{format_value(state.z)} " <>
            "Rx:#{format_value(state.rx)} " <>
            "Ry:#{format_value(state.ry)} " <>
            "Rz:#{format_value(state.rz)}")
  end

  defp format_value(value) do
    String.pad_leading(Integer.to_string(value), 4)
  end

  @doc """
  Quick test to verify the C helper is working.
  """
  def test_c_helper do
    Logger.info("🔧 Testing C helper program...")
    
    helper_path = Path.join([__DIR__, "..", "..", "priv", "spacemouse_reader"])
    
    if File.exists?(helper_path) do
      Logger.info("✓ C helper found at #{helper_path}")
      Logger.info("Starting helper for 5 seconds...")
      
      port = Port.open(
        {:spawn_executable, helper_path},
        [:binary, :exit_status]
      )
      
      # Listen for output for 5 seconds
      test_helper_output(port, 5000)
      Port.close(port)
      
    else
      Logger.error("❌ C helper not found")
      Logger.info("💡 Run: cd priv && clang -framework IOKit -framework CoreFoundation -o spacemouse_reader spacemouse_reader.c")
    end
  end

  defp test_helper_output(port, timeout) do
    receive do
      {^port, {:data, data}} ->
        IO.puts("C Helper: #{String.trim(data)}")
        test_helper_output(port, 1000)  # Continue for 1 more second
        
      {^port, {:exit_status, status}} ->
        Logger.info("C helper exited with status: #{status}")
        
    after
      timeout ->
        Logger.info("Test complete")
    end
  end
end
