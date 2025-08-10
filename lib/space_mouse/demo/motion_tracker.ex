defmodule SpaceMouse.Demo.MotionTracker do
  @moduledoc """
  Simple, focused motion tracking demonstration.
  
  This demo focuses specifically on 6DOF motion data, showing:
  - Normalized motion values (-1.0 to +1.0)
  - Real-time coordinate system feedback
  - Motion magnitude and direction
  - Clean, readable output format
  
  Perfect for understanding SpaceMouse motion data structure.
  
  Run with: `SpaceMouse.Demo.MotionTracker.run()`
  """

  @doc """
  Run the motion tracking demo.
  """
  def run do
    IO.puts """
    
    🎯 ==============================
       SpaceMouse Motion Tracker
    ==============================
    
    This demo shows real-time 6DOF motion data:
    
    Translation Axes:
    • X: Left(-) / Right(+)
    • Y: Forward(-) / Back(+) 
    • Z: Down(-) / Up(+)
    
    Rotation Axes:
    • RX: Pitch Down(-) / Up(+)
    • RY: Roll Left(-) / Right(+)
    • RZ: Yaw Left(-) / Right(+)
    
    Values: -1.0 to +1.0 (normalized)
    
    Move your SpaceMouse to see live data!
    Press Ctrl+C to exit.
    
    """

    # Start system and subscribe
    :ok = SpaceMouse.start_monitoring()
    :ok = SpaceMouse.subscribe()
    
    # Wait for connection
    wait_for_connection()
    
    # Start motion tracking
    track_motion(%{
      sample_count: 0,
      last_motion: %{x: 0.0, y: 0.0, z: 0.0, rx: 0.0, ry: 0.0, rz: 0.0},
      max_values: %{x: 0.0, y: 0.0, z: 0.0, rx: 0.0, ry: 0.0, rz: 0.0}
    })
  end

  defp wait_for_connection do
    receive do
      {:spacemouse_connected, _device_info} ->
        IO.puts "✅ SpaceMouse connected - starting motion tracking!\n"
        
      {:spacemouse_disconnected, _device_info} ->
        IO.puts "❌ SpaceMouse disconnected - waiting for reconnection..."
        wait_for_connection()
        
    after
      3000 ->
        if SpaceMouse.connected?() do
          IO.puts "✅ SpaceMouse already connected - starting motion tracking!\n"
        else
          IO.puts "⏳ Still waiting for SpaceMouse..."
          wait_for_connection()
        end
    end
  end

  defp track_motion(state) do
    receive do
      {:spacemouse_motion, motion} ->
        new_state = handle_motion(motion, state)
        track_motion(new_state)

      {:spacemouse_disconnected, _device_info} ->
        IO.puts "\n❌ SpaceMouse disconnected!"
        wait_for_connection()
        track_motion(state)

      {:spacemouse_connected, _device_info} ->
        IO.puts "\n✅ SpaceMouse reconnected!"
        track_motion(state)

      _other ->
        track_motion(state)
        
    after
      100 ->
        track_motion(state)
    end
  end

  defp handle_motion(%{x: x, y: y, z: z, rx: rx, ry: ry, rz: rz} = motion, state) do
    # Only display significant motion
    if significant_motion?(motion) do
      display_motion(motion, state.sample_count + 1)
      
      # Update max values seen
      new_max = %{
        x: max(abs(x), state.max_values.x),
        y: max(abs(y), state.max_values.y),
        z: max(abs(z), state.max_values.z),
        rx: max(abs(rx), state.max_values.rx),
        ry: max(abs(ry), state.max_values.ry),
        rz: max(abs(rz), state.max_values.rz)
      }
      
      %{state | 
        sample_count: state.sample_count + 1,
        last_motion: motion,
        max_values: new_max
      }
    else
      state
    end
  end

  defp display_motion(%{x: x, y: y, z: z, rx: rx, ry: ry, rz: rz}, count) do
    # Calculate overall motion magnitude
    translation_mag = :math.sqrt(x*x + y*y + z*z)
    rotation_mag = :math.sqrt(rx*rx + ry*ry + rz*rz)
    
    IO.puts """
    🎯 Motion Sample ##{count}
    ┌─ Translation ─────────────────────────────────────┐
    │ X: #{format_value_with_bar(x)} │ #{describe_translation(:x, x)}
    │ Y: #{format_value_with_bar(y)} │ #{describe_translation(:y, y)}
    │ Z: #{format_value_with_bar(z)} │ #{describe_translation(:z, z)}
    │ Magnitude: #{format_magnitude(translation_mag)}                           │
    ├─ Rotation ────────────────────────────────────────┤
    │ RX: #{format_value_with_bar(rx)} │ #{describe_rotation(:rx, rx)}
    │ RY: #{format_value_with_bar(ry)} │ #{describe_rotation(:ry, ry)}
    │ RZ: #{format_value_with_bar(rz)} │ #{describe_rotation(:rz, rz)}
    │ Magnitude: #{format_magnitude(rotation_mag)}                           │
    └───────────────────────────────────────────────────┘
    """
  end

  defp significant_motion?(%{x: x, y: y, z: z, rx: rx, ry: ry, rz: rz}) do
    threshold = 0.03
    abs(x) > threshold or abs(y) > threshold or abs(z) > threshold or
    abs(rx) > threshold or abs(ry) > threshold or abs(rz) > threshold
  end

  defp format_value_with_bar(value) do
    value_str = format_value(value)
    bar = create_bar(value, 20)
    "#{value_str} #{bar}"
  end

  defp format_value(value) when is_float(value) do
    :erlang.float_to_binary(value, decimals: 3) |> String.pad_leading(7)
  end
  defp format_value(value), do: String.pad_leading("#{value}", 7)

  defp format_magnitude(mag) do
    :erlang.float_to_binary(mag, decimals: 3) |> String.pad_leading(7)
  end

  defp create_bar(value, width) do
    # Create a visual bar representation
    center = div(width, 2)
    filled = round(abs(value) * center)
    
    if value >= 0 do
      String.duplicate(" ", center) <> 
      String.duplicate("█", min(filled, center)) <>
      String.duplicate("░", center - min(filled, center))
    else
      String.duplicate("░", center - min(filled, center)) <>
      String.duplicate("█", min(filled, center)) <>
      String.duplicate(" ", center)
    end
  end

  defp describe_translation(:x, value) when value > 0.1, do: "Moving RIGHT"
  defp describe_translation(:x, value) when value < -0.1, do: "Moving LEFT"
  defp describe_translation(:y, value) when value > 0.1, do: "Moving BACK"
  defp describe_translation(:y, value) when value < -0.1, do: "Moving FORWARD"
  defp describe_translation(:z, value) when value > 0.1, do: "Moving UP"
  defp describe_translation(:z, value) when value < -0.1, do: "Moving DOWN"
  defp describe_translation(_, _), do: "At rest"

  defp describe_rotation(:rx, value) when value > 0.1, do: "Pitching UP"
  defp describe_rotation(:rx, value) when value < -0.1, do: "Pitching DOWN"
  defp describe_rotation(:ry, value) when value > 0.1, do: "Rolling RIGHT"
  defp describe_rotation(:ry, value) when value < -0.1, do: "Rolling LEFT"
  defp describe_rotation(:rz, value) when value > 0.1, do: "Yawing RIGHT"
  defp describe_rotation(:rz, value) when value < -0.1, do: "Yawing LEFT"
  defp describe_rotation(_, _), do: "At rest"
end
