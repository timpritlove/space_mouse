defmodule SpaceMouse.Demo.CompleteDemo do
  @moduledoc """
  Complete demonstration of SpaceMouse functionality.
  
  This demo shows all the key features:
  - Device connection/disconnection
  - Real-time 6DOF motion tracking
  - Button event handling  
  - LED control and state change events
  - Proper event subscription and handling
  
  Run with: `SpaceMouse.Demo.CompleteDemo.run()`
  """

  require Logger

  @doc """
  Run the complete SpaceMouse demonstration.
  """
  def run do
    IO.puts """
    
    🚀 =======================================
       SpaceMouse Complete Demo
    =======================================
    
    This demo will:
    • Connect to your SpaceMouse
    • Show live 6DOF motion data (-1.0 to +1.0 range)
    • Display button press/release events
    • Control the LED and show state change events
    • Handle disconnection/reconnection
    
    Make sure your SpaceMouse is connected!
    Press Ctrl+C to exit.
    
    """

    # Start monitoring and subscribe to events
    :ok = SpaceMouse.start_monitoring()
    :ok = SpaceMouse.subscribe()
    
    # Wait for connection or show current state
    show_initial_state()
    
    # Start the main event loop
    event_loop(%{
      motion_count: 0,
      button_states: %{},
      led_blink_count: 0,
      last_stats: System.monotonic_time(:second)
    })
  end

  defp show_initial_state do
    case SpaceMouse.connected?() do
      true ->
        IO.puts "✅ SpaceMouse already connected!"
        {:ok, led_state} = SpaceMouse.get_led_state()
        IO.puts "💡 Current LED state: #{led_state}"
        test_led_control()
        
      false ->
        IO.puts "⏳ Waiting for SpaceMouse connection..."
    end
  end

  defp test_led_control do
    IO.puts "🔆 Testing LED control..."
    SpaceMouse.set_led(:on)
    Process.sleep(1000)
    SpaceMouse.set_led(:off)
    Process.sleep(500)
    SpaceMouse.set_led(:on)
    IO.puts "💡 LED should be on now"
  end

  defp event_loop(state) do
    receive do
      # Connection events
      {:spacemouse_connected, device_info} ->
        IO.puts "🎉 SpaceMouse connected!"
        IO.puts "   Device info: #{inspect(device_info)}"
        test_led_control()
        event_loop(state)

      {:spacemouse_disconnected, device_info} ->
        IO.puts "❌ SpaceMouse disconnected"
        IO.puts "   Device info: #{inspect(device_info)}"
        IO.puts "⏳ Waiting for reconnection..."
        event_loop(state)

      # Motion events
      {:spacemouse_motion, motion} ->
        new_state = handle_motion_event(motion, state)
        event_loop(new_state)

      # Button events
      {:spacemouse_button, button} ->
        new_state = handle_button_event(button, state)
        event_loop(new_state)

      # LED events
      {:spacemouse_led_changed, led_change} ->
        handle_led_event(led_change)
        event_loop(state)

    after
      5000 ->
        # Show periodic stats and maybe blink LED
        new_state = handle_periodic_update(state)
        event_loop(new_state)
    end
  end

  defp handle_motion_event(%{x: x, y: y, z: z, rx: rx, ry: ry, rz: rz}, state) do
    # Only show significant motion to avoid spam
    if significant_motion?(x, y, z, rx, ry, rz) do
      IO.puts """
      🎯 Motion Event ##{state.motion_count + 1}:
         Translation: X=#{format_axis(x)} Y=#{format_axis(y)} Z=#{format_axis(z)}
         Rotation:    RX=#{format_axis(rx)} RY=#{format_axis(ry)} RZ=#{format_axis(rz)}
      """
    end

    %{state | motion_count: state.motion_count + 1}
  end

  defp handle_button_event(%{id: id, state: button_state}, state) do
    # Track button state changes
    previous_state = Map.get(state.button_states, id, :released)
    
    if previous_state != button_state do
      icon = if button_state == :pressed, do: "🔴", else: "⚪"
      IO.puts "#{icon} Button #{id}: #{button_state}"
      
      # Demo: Toggle LED when button 1 is pressed
      if id == 1 and button_state == :pressed do
        {:ok, current_led} = SpaceMouse.get_led_state()
        new_led = if current_led == :on, do: :off, else: :on
        SpaceMouse.set_led(new_led)
        IO.puts "   💡 Toggled LED to #{new_led}"
      end
    end

    new_button_states = Map.put(state.button_states, id, button_state)
    %{state | button_states: new_button_states}
  end

  defp handle_led_event(%{from: from, to: to, timestamp: timestamp}) do
    IO.puts "💡 LED State Changed: #{from} → #{to} (at #{timestamp})"
  end

  defp handle_periodic_update(state) do
    current_time = System.monotonic_time(:second)
    time_diff = current_time - state.last_stats
    
    if time_diff >= 5 do
      show_stats(state, time_diff)
      
      # Periodic LED blink demo every 30 seconds
      new_blink_count = if rem(current_time, 30) == 0 and state.led_blink_count < current_time do
        blink_led_demo()
        current_time
      else
        state.led_blink_count
      end
      
      %{state | 
        last_stats: current_time,
        led_blink_count: new_blink_count,
        motion_count: 0
      }
    else
      state
    end
  end

  defp show_stats(state, time_diff) do
    motion_rate = state.motion_count / time_diff
    
    IO.puts """
    
    📊 === Stats (last #{time_diff}s) ===
    Motion events: #{state.motion_count} (~#{:erlang.float_to_binary(motion_rate, decimals: 1)}/s)
    Active buttons: #{format_active_buttons(state.button_states)}
    Device connected: #{SpaceMouse.connected?()}
    Platform: #{inspect(SpaceMouse.platform_info())}
    =====================================
    
    """
  end

  defp blink_led_demo do
    IO.puts "✨ LED Demo: 3 quick blinks..."
    
    for _i <- 1..3 do
      SpaceMouse.set_led(:off)
      Process.sleep(200)
      SpaceMouse.set_led(:on)
      Process.sleep(200)
    end
  end

  defp significant_motion?(x, y, z, rx, ry, rz) do
    # With ±1.0 range, 0.05 is a good threshold for significant motion
    threshold = 0.05
    abs(x) > threshold or abs(y) > threshold or abs(z) > threshold or
    abs(rx) > threshold or abs(ry) > threshold or abs(rz) > threshold
  end

  defp format_axis(value) when is_float(value) do
    :erlang.float_to_binary(value, decimals: 3) |> String.pad_leading(7)
  end
  defp format_axis(value), do: String.pad_leading("#{value}", 7)

  defp format_active_buttons(button_states) do
    pressed_buttons = 
      button_states
      |> Enum.filter(fn {_id, state} -> state == :pressed end)
      |> Enum.map(fn {id, _state} -> id end)
      |> Enum.sort()
    
    if Enum.empty?(pressed_buttons) do
      "none"
    else
      Enum.join(pressed_buttons, ", ")
    end
  end
end
