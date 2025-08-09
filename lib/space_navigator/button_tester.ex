defmodule SpaceNavigator.ButtonTester do
  @moduledoc """
  Test button events from SpaceMouse to see what's being received.
  """

  def start do
    IO.puts("🔘 SpaceMouse Button Event Tester")
    IO.puts("📌 Press buttons on your SpaceMouse to see ALL events...")
    IO.puts("🔍 This will show EVERY HID event, not just motion")
    IO.puts("=" |> String.duplicate(50))

    helper_path = Path.join([__DIR__, "..", "..", "priv", "spacemouse_reader"])
    
    port = Port.open(
      {:spawn_executable, helper_path},
      [:binary, :exit_status, {:line, 1024}]
    )

    listen_for_all_events(port)
  end

  defp listen_for_all_events(port) do
    receive do
      {^port, {:data, data}} ->
        line = extract_line(data)
        analyze_event(line)
        listen_for_all_events(port)
        
      {^port, {:exit_status, status}} ->
        IO.puts("🔚 Program exited: #{status}")
        
    after 60_000 ->
        IO.puts("⏰ 60 second timeout - stopping")
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

  defp analyze_event(line) do
    cond do
      line in ["ready", "device_found"] ->
        IO.puts("✅ #{line}")
        
      String.starts_with?(line, "motion:") ->
        IO.puts("🎯 #{line}")
        
      String.starts_with?(line, "button:") ->
        IO.puts("🔘 BUTTON EVENT: #{line}")
        
      String.starts_with?(line, "hid_event:") ->
        # Parse and analyze HID events
        case Regex.run(~r/hid_event:page=(\d+),usage=(\d+),value=(-?\d+)/, line) do
          [_, page, usage, value] ->
            page_num = String.to_integer(page)
            usage_num = String.to_integer(usage)
            value_num = String.to_integer(value)
            
            event_type = categorize_event(page_num, usage_num, value_num)
            IO.puts("📊 #{event_type}: page=#{page_num}, usage=#{usage_num}, value=#{value_num}")
            
          _ ->
            IO.puts("❓ Unknown HID event: #{line}")
        end
        
      String.trim(line) != "" ->
        IO.puts("🔍 Other: #{line}")
        
      true ->
        # Empty line, ignore
        nil
    end
  end

  defp categorize_event(page, usage, value) do
    case page do
      1 ->
        # Generic Desktop page
        case usage do
          48 -> "🔴 X-Translation (#{value})"
          49 -> "🟢 Y-Translation (#{value})"
          50 -> "🔵 Z-Translation (#{value})"
          51 -> "🟠 X-Rotation (#{value})"
          52 -> "🟡 Y-Rotation (#{value})"
          53 -> "🟣 Z-Rotation (#{value})"
          8  -> "🎮 Multi-axis Controller (#{value})"
          _ -> "🖱️  Generic Desktop usage #{usage} (#{value})"
        end
        
      9 ->
        # Button page
        if value > 0 do
          "🔘 BUTTON #{usage} PRESSED"
        else
          "🔘 BUTTON #{usage} RELEASED"
        end
        
      _ ->
        "📋 Page #{page}, Usage #{usage} (#{value})"
    end
  end

  def test_motion_vs_buttons do
    IO.puts("🧪 Motion vs Button Test")
    IO.puts("1️⃣  First, DON'T touch your SpaceMouse for 3 seconds...")
    Process.sleep(3000)
    
    IO.puts("2️⃣  Now ONLY move (don't press buttons) for 5 seconds...")
    start_test_period("MOTION ONLY", 5000)
    
    IO.puts("3️⃣  Now ONLY press buttons (don't move) for 5 seconds...")
    start_test_period("BUTTONS ONLY", 5000)
    
    IO.puts("✅ Test complete!")
  end

  defp start_test_period(test_name, duration) do
    IO.puts("🔄 #{test_name} test starting...")
    
    helper_path = Path.join([__DIR__, "..", "..", "priv", "spacemouse_reader"])
    
    port = Port.open(
      {:spawn_executable, helper_path},
      [:binary, :exit_status, {:line, 1024}]
    )

    listen_with_timeout(port, test_name, duration)
    Port.close(port)
  end

  defp listen_with_timeout(port, test_name, timeout) do
    receive do
      {^port, {:data, data}} ->
        line = extract_line(data)
        if String.contains?(line, "hid_event") do
          IO.puts("#{test_name}: #{line}")
        end
        listen_with_timeout(port, test_name, timeout - 50)
        
    after
      timeout ->
        IO.puts("⏰ #{test_name} test period ended")
    end
  end
end
