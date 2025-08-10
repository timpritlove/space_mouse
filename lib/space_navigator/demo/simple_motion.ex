defmodule SpaceNavigator.SimpleMotion do
  @moduledoc """
  Simple, clean SpaceMouse motion viewer with zero errors.
  """

  def start do
    IO.puts("🚀 SpaceMouse Motion Tracker - WORKING VERSION!")
    IO.puts("🎮 Move your SpaceMouse to see live 6DOF data...")
    IO.puts("📊 Press Ctrl+C to stop")
    IO.puts("=" |> String.duplicate(50))

    helper_path = Path.join([__DIR__, "..", "..", "priv", "spacemouse_reader"])
    
    port = Port.open(
      {:spawn_executable, helper_path},
      [:binary, :exit_status, {:line, 1024}]
    )

    listen_and_display(port, %{x: 0, y: 0, z: 0, rx: 0, ry: 0, rz: 0})
  end

  defp listen_and_display(port, motion_state) do
    receive do
      {^port, {:data, data}} ->
        line = extract_line(data)
        new_state = process_motion_line(line, motion_state)
        listen_and_display(port, new_state)
        
      {^port, {:exit_status, _status}} ->
        IO.puts("🔚 SpaceMouse disconnected")
        
    after 30_000 ->
        IO.puts("⏰ No motion for 30 seconds - stopping")
        Port.close(port)
    end
  end

  defp extract_line(data) do
    case data do
      {:eol, text} -> text
      binary when is_binary(binary) -> String.trim(binary)
      _ -> ""
    end
  end

  defp process_motion_line(line, motion_state) do
    case String.starts_with?(line, "motion:") do
      true -> 
        parse_and_display_motion(line, motion_state)
      false -> 
        if line in ["ready", "device_found"] do
          IO.puts("✅ #{line}")
        end
        motion_state
    end
  end

  defp parse_and_display_motion(line, motion_state) do
    # Parse "motion:page=1,usage=48,value=24"
    case Regex.run(~r/motion:page=1,usage=(\d+),value=(-?\d+)/, line) do
      [_, usage, value] ->
        axis = usage_to_axis(String.to_integer(usage))
        val = String.to_integer(value)
        
        new_state = Map.put(motion_state, axis, val)
        display_motion(axis, val, new_state)
        new_state
        
      _ ->
        motion_state
    end
  end

  defp usage_to_axis(48), do: :x   # X translation
  defp usage_to_axis(49), do: :y   # Y translation  
  defp usage_to_axis(50), do: :z   # Z translation
  defp usage_to_axis(51), do: :rx  # X rotation
  defp usage_to_axis(52), do: :ry  # Y rotation
  defp usage_to_axis(53), do: :rz  # Z rotation
  defp usage_to_axis(_), do: :unknown

  defp display_motion(axis, value, full_state) do
    # Only show non-zero values to reduce noise
    if value != 0 do
      axis_name = case axis do
        :x  -> "🔴 X-Trans"
        :y  -> "🟢 Y-Trans"
        :z  -> "🔵 Z-Trans"
        :rx -> "🟠 X-Rot  "
        :ry -> "🟡 Y-Rot  "
        :rz -> "🟣 Z-Rot  "
        _   -> "❓ Unknown"
      end
      
      bar = create_bar(value)
      timestamp = format_time()
      
      IO.puts("#{timestamp} #{axis_name}: #{String.pad_leading(Integer.to_string(value), 4)} #{bar}")
      
      # Show full 6DOF state every few movements
      if rem(System.monotonic_time(:millisecond), 500) < 100 do
        show_full_state(full_state)
      end
    end
  end

  defp create_bar(value) do
    max_width = 15
    scaled = min(abs(value), 100) / 100 * max_width
    bar_length = round(scaled)
    
    cond do
      value == 0 -> "│"
      value > 0 -> "│" <> String.duplicate("█", bar_length)
      value < 0 -> String.duplicate("█", bar_length) <> "│"
    end
  end

  defp format_time do
    ms = rem(System.monotonic_time(:millisecond), 10000)
    "#{String.pad_leading(Integer.to_string(ms), 4, "0")}ms"
  end

  defp show_full_state(state) do
    IO.puts("━━━ 6DOF State ━━━")
    IO.puts("Trans: X:#{pad(state.x)} Y:#{pad(state.y)} Z:#{pad(state.z)}")
    IO.puts("Rot:   X:#{pad(state.rx)} Y:#{pad(state.ry)} Z:#{pad(state.rz)}")
    IO.puts("━━━━━━━━━━━━━━━━━━")
  end

  defp pad(value), do: String.pad_leading(Integer.to_string(value), 4)
end
