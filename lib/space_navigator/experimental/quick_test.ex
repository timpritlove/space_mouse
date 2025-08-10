defmodule SpaceNavigator.QuickTest do
  @moduledoc """
  Quick interactive test for SpaceMouse events.
  """

  require Logger

  def start do
    Logger.info("🚀 Starting Quick SpaceMouse Test")
    
    # Start the HID monitor
    {:ok, _pid} = SpaceNavigator.HidMonitor.start_link()
    
    # Subscribe to events
    :ok = SpaceNavigator.HidMonitor.subscribe()
    
    # Start monitoring  
    case SpaceNavigator.HidMonitor.start_monitoring() do
      {:ok, :started} ->
        Logger.info("✅ Monitoring started!")
        Logger.info("🎮 Move your SpaceMouse now!")
        
        # Listen for 20 seconds
        listen_for_events(20_000)
        
      {:error, reason} ->
        Logger.error("❌ Failed to start: #{inspect(reason)}")
    end
  end

  defp listen_for_events(timeout) do
    receive do
      {:spacemouse_hid_event, event} ->
        IO.puts("📡 EVENT: #{inspect(event)}")
        listen_for_events(timeout - 100)
        
    after
      timeout ->
        Logger.info("⏰ Test timeout")
    end
  end

  def test_c_program_directly do
    Logger.info("🔧 Testing C program directly")
    
    helper_path = Path.join([__DIR__, "..", "..", "priv", "spacemouse_reader"])
    
    port = Port.open(
      {:spawn_executable, helper_path},
      [:binary, :exit_status, {:line, 1024}]
    )
    
    Logger.info("✅ C program started, listening for 10 seconds...")
    Logger.info("🎮 MOVE YOUR SPACEMOUSE NOW!")
    
    listen_to_port(port, 10_000)
    Port.close(port)
  end

  defp listen_to_port(port, timeout) do
    receive do
      {^port, {:data, data}} ->
        line = case data do
          {:eol, text} -> text
          binary when is_binary(binary) -> String.trim(binary)
          other -> inspect(other)
        end
        IO.puts("📨 C OUTPUT: #{line}")
        listen_to_port(port, 10_000)
        
      {^port, {:exit_status, status}} ->
        Logger.info("C program exited: #{status}")
        
      other ->
        IO.puts("📨 OTHER: #{inspect(other)}")
        listen_to_port(port, 10_000)
        
    after
      timeout ->
        Logger.info("⏰ C test timeout")
    end
  end
end
