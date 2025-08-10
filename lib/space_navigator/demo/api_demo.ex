defmodule SpaceNavigator.Demo.ApiDemo do
  @moduledoc """
  Demonstration of the clean SpaceNavigator API.
  
  This module shows how to use the new unified SpaceNavigator interface
  for cross-platform SpaceMouse interaction.
  """

  require Logger

  @doc """
  Basic demonstration of SpaceNavigator API usage.
  """
  def basic_demo do
    Logger.info("🚀 SpaceNavigator API Demo Starting...")

    # Check platform info
    platform = SpaceNavigator.platform_info()
    Logger.info("📋 Platform: #{inspect(platform)}")

    # Start monitoring for devices
    case SpaceNavigator.start_monitoring() do
      :ok ->
        Logger.info("👁️ Monitoring started - connect your SpaceMouse!")
        
        # Subscribe to events
        SpaceNavigator.subscribe()
        
        # Demo loop
        demo_loop()
        
      {:error, reason} ->
        Logger.error("❌ Failed to start monitoring: #{inspect(reason)}")
    end
  end

  @doc """
  Interactive demo with LED control.
  """
  def interactive_demo do
    Logger.info("🎮 Interactive SpaceNavigator Demo")
    
    # Start monitoring
    SpaceNavigator.start_monitoring()
    SpaceNavigator.subscribe()
    
    IO.puts("""
    
    🎯 SpaceNavigator Interactive Demo
    
    Commands:
      1 - Turn LED ON
      2 - Turn LED OFF  
      3 - Check connection status
      4 - Show platform info
      5 - Show current motion
      q - Quit
    
    Connect your SpaceMouse and try moving it or pressing buttons!
    """)
    
    interactive_loop()
  end

  @doc """
  Simple motion tracking demo.
  """
  def motion_demo do
    Logger.info("🎯 Motion Tracking Demo")
    
    SpaceNavigator.start_monitoring()
    SpaceNavigator.subscribe()
    
    IO.puts("🎮 Move your SpaceMouse to see motion data...")
    IO.puts("💡 Press Ctrl+C to exit")
    
    motion_loop()
  end

  # Private Implementation

  defp demo_loop do
    receive do
      {:spacemouse_connected, device_info} ->
        Logger.info("✅ SpaceMouse connected: #{inspect(device_info)}")
        
        # Turn on LED to show connection
        case SpaceNavigator.set_led(:on) do
          :ok -> Logger.info("💡 LED turned on")
          error -> Logger.warning("💡 LED control failed: #{inspect(error)}")
        end
        
        demo_loop()
        
      {:spacemouse_disconnected, device_info} ->
        Logger.info("❌ SpaceMouse disconnected: #{inspect(device_info)}")
        demo_loop()
        
      {:spacemouse_motion, motion} ->
        # Only log significant motion
        if significant_motion?(motion) do
          Logger.info("🎯 Motion: #{format_motion(motion)}")
        end
        demo_loop()
        
      {:spacemouse_button, button} ->
        Logger.info("🔘 Button: #{format_button(button)}")
        demo_loop()
        
    after
      30_000 ->
        Logger.info("⏰ Demo timeout - stopping...")
        SpaceNavigator.stop_monitoring()
    end
  end

  defp interactive_loop do
    IO.write("💡 Enter command (1/2/3/4/5/q): ")
    
    case IO.gets("") |> String.trim() do
      "1" ->
        case SpaceNavigator.set_led(:on) do
          :ok -> IO.puts("🔆 LED ON")
          error -> IO.puts("❌ LED control failed: #{inspect(error)}")
        end
        check_events()
        interactive_loop()
        
      "2" ->
        case SpaceNavigator.set_led(:off) do
          :ok -> IO.puts("🔅 LED OFF")
          error -> IO.puts("❌ LED control failed: #{inspect(error)}")
        end
        check_events()
        interactive_loop()
        
      "3" ->
        connected = SpaceNavigator.connected?()
        state = SpaceNavigator.connection_state()
        IO.puts("🔌 Connected: #{connected}, State: #{state}")
        check_events()
        interactive_loop()
        
      "4" ->
        platform = SpaceNavigator.platform_info()
        IO.puts("📋 Platform: #{inspect(platform)}")
        check_events()
        interactive_loop()
        
      "5" ->
        motion = SpaceNavigator.get_motion_state()
        IO.puts("🎯 Current motion: #{format_motion(motion)}")
        check_events()
        interactive_loop()
        
      "q" ->
        IO.puts("👋 Stopping demo...")
        SpaceNavigator.stop_monitoring()
        
      _ ->
        IO.puts("❓ Unknown command")
        interactive_loop()
    end
  end

  defp motion_loop do
    receive do
      {:spacemouse_connected, _device_info} ->
        IO.puts("✅ SpaceMouse connected!")
        motion_loop()
        
      {:spacemouse_disconnected, _device_info} ->
        IO.puts("❌ SpaceMouse disconnected!")
        motion_loop()
        
      {:spacemouse_motion, motion} ->
        if significant_motion?(motion) do
          IO.puts("🎯 #{format_motion(motion)}")
        end
        motion_loop()
        
      {:spacemouse_button, button} ->
        IO.puts("🔘 #{format_button(button)}")
        motion_loop()
        
    after
      100 ->
        motion_loop()
    end
  end

  defp check_events do
    # Check for any pending events
    receive do
      {:spacemouse_connected, _} -> IO.puts("📢 SpaceMouse connected!")
      {:spacemouse_disconnected, _} -> IO.puts("📢 SpaceMouse disconnected!")
      {:spacemouse_motion, motion} -> 
        if significant_motion?(motion) do
          IO.puts("📢 Motion: #{format_motion(motion)}")
        end
      {:spacemouse_button, button} -> IO.puts("📢 Button: #{format_button(button)}")
    after
      10 -> :ok
    end
  end

  defp significant_motion?(motion) do
    # Only show motion if any axis has significant movement
    threshold = 100
    
    abs(motion[:x] || 0) > threshold or
    abs(motion[:y] || 0) > threshold or  
    abs(motion[:z] || 0) > threshold or
    abs(motion[:rx] || 0) > threshold or
    abs(motion[:ry] || 0) > threshold or
    abs(motion[:rz] || 0) > threshold
  end

  defp format_motion(motion) do
    x = motion[:x] || 0
    y = motion[:y] || 0
    z = motion[:z] || 0
    rx = motion[:rx] || 0
    ry = motion[:ry] || 0
    rz = motion[:rz] || 0
    
    "X:#{x} Y:#{y} Z:#{z} | RX:#{rx} RY:#{ry} RZ:#{rz}"
  end

  defp format_button(button) do
    id = button[:id] || 0
    state = button[:state] || :unknown
    
    "Button #{id} #{state}"
  end
end
