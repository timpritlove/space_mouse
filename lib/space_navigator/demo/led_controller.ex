defmodule SpaceNavigator.LedController do
  @moduledoc """
  Control the SpaceMouse Compact LED light.
  
  The SpaceMouse has an LED that can be controlled via HID output reports.
  Based on our HID descriptor analysis, we found output reports that likely control the LED.
  """

  require Logger
  import Bitwise

  @doc """
  Turn the SpaceMouse LED on or off.
  """
  def set_led(state) when state in [:on, :off] do
    Logger.info("🔆 Setting SpaceMouse LED: #{state}")
    
    case get_connected_device() do
      {:ok, device} ->
        send_led_command(device, state)
        
      {:error, reason} ->
        Logger.error("Could not connect to SpaceMouse: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Blink the LED a few times.
  """
  def blink_led(times \\ 3) do
    Logger.info("✨ Blinking SpaceMouse LED #{times} times")
    
    case get_connected_device() do
      {:ok, device} ->
        Enum.each(1..times, fn i ->
          Logger.info("Blink #{i}/#{times}")
          send_led_command(device, :on)
          Process.sleep(300)
          send_led_command(device, :off)
          Process.sleep(300)
        end)
        {:ok, :blinked}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Test different LED commands to see which one works.
  """
  def test_led_commands do
    Logger.info("🧪 Testing SpaceMouse LED commands...")
    
    case get_connected_device() do
      {:ok, device} ->
        # Test various output reports that might control the LED
        test_commands = [
          # Based on 3Dconnexion documentation, common LED commands:
          {4, [1]},           # Report ID 4, LED on
          {4, [0]},           # Report ID 4, LED off
          {5, [1]},           # Report ID 5, LED on  
          {5, [0]},           # Report ID 5, LED off
          {6, [1]},           # Report ID 6, LED on
          {6, [0]},           # Report ID 6, LED off
          {7, [255]},         # Report ID 7, LED bright
          {7, [0]},           # Report ID 7, LED off
          {8, [1, 0, 0]},     # Report ID 8, RGB LED red
          {8, [0, 1, 0]},     # Report ID 8, RGB LED green  
          {8, [0, 0, 1]},     # Report ID 8, RGB LED blue
          {8, [0, 0, 0]},     # Report ID 8, RGB LED off
        ]
        
        Enum.each(test_commands, fn {report_id, data} ->
          Logger.info("Testing Report ID #{report_id} with data #{inspect(data)}")
          send_output_report(device, report_id, data)
          Process.sleep(1000)  # Wait 1 second between commands
        end)
        
        {:ok, :test_complete}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_connected_device do
    case SpaceNavigator.UsbManager.find_devices(%{vendor_id: 0x256F}) do
      {:ok, [device | _]} ->
        SpaceNavigator.UsbManager.open_device(device)
        
      {:ok, []} ->
        {:error, :no_spacemouse_found}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_led_command(device, state) do
    # Try the most common LED control methods
    led_value = case state do
      :on -> 1
      :off -> 0
    end
    
    # Method 1: Try Report ID 4 (common for 3Dconnexion devices)
    case send_output_report(device, 4, [led_value]) do
      :ok -> 
        Logger.info("✅ LED command sent via Report ID 4")
        :ok
        
      {:error, _} ->
        # Method 2: Try Report ID 5
        case send_output_report(device, 5, [led_value]) do
          :ok ->
            Logger.info("✅ LED command sent via Report ID 5") 
            :ok
            
          {:error, _} ->
            # Method 3: Try LED brightness control
            brightness = if state == :on, do: 255, else: 0
            case send_output_report(device, 7, [brightness]) do
              :ok ->
                Logger.info("✅ LED command sent via Report ID 7")
                :ok
                
              {:error, reason} ->
                Logger.warning("❌ All LED methods failed: #{inspect(reason)}")
                {:error, :led_control_failed}
            end
        end
    end
  end

  defp send_output_report(device, report_id, data) do
    # HID SET_REPORT control transfer
    # bmRequestType = 0x21 (Host to Device, Class, Interface)
    # bRequest = 0x09 (SET_REPORT)  
    # wValue = (Output Report Type << 8) | Report ID = (2 << 8) | report_id
    # wIndex = 0 (Interface 0)
    
    wValue = (0x02 <<< 8) ||| report_id
    report_data = [report_id | data] |> :binary.list_to_bin()
    
    case :usb.write_control(
      device.handle,
      0x21,           # bmRequestType: Host to Device, Class, Interface
      0x09,           # bRequest: SET_REPORT
      wValue,         # wValue: Report Type + Report ID
      0,              # wIndex: Interface 0
      report_data,    # Data
      1000            # timeout
    ) do
      {:ok, _bytes_written} ->
        Logger.debug("Output report #{report_id} sent: #{inspect(data)}")
        :ok
        
      {:error, reason} ->
        Logger.debug("Failed to send output report #{report_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Interactive LED control demo.
  """
  def interactive_demo do
    IO.puts("""
    🔆 SpaceMouse LED Controller Demo
    
    Commands:
      1 - Turn LED ON
      2 - Turn LED OFF  
      3 - Blink 3 times
      4 - Test all LED commands
      q - Quit
    """)
    
    case get_connected_device() do
      {:ok, device} ->
        IO.puts("✅ SpaceMouse connected!")
        interactive_loop(device)
        
      {:error, reason} ->
        IO.puts("❌ Could not connect: #{inspect(reason)}")
    end
  end

  defp interactive_loop(device) do
    IO.write("💡 Enter command (1/2/3/4/q): ")
    
    case IO.gets("") |> String.trim() do
      "1" ->
        send_led_command(device, :on)
        IO.puts("🔆 LED ON command sent")
        interactive_loop(device)
        
      "2" ->
        send_led_command(device, :off)
        IO.puts("🔅 LED OFF command sent")
        interactive_loop(device)
        
      "3" ->
        blink_led_device(device, 3)
        interactive_loop(device)
        
      "4" ->
        test_led_commands()
        interactive_loop(device)
        
      "q" ->
        IO.puts("👋 Goodbye!")
        
      _ ->
        IO.puts("❓ Unknown command")
        interactive_loop(device)
    end
  end

  defp blink_led_device(device, times) do
    IO.puts("✨ Blinking #{times} times...")
    
    Enum.each(1..times, fn i ->
      IO.puts("  Blink #{i}/#{times}")
      send_led_command(device, :on)
      Process.sleep(300)
      send_led_command(device, :off)
      Process.sleep(300)
    end)
    
    IO.puts("✅ Blink complete!")
  end

  @doc """
  Set LED to a specific brightness level (0-255).
  """
  def set_brightness(level) when level >= 0 and level <= 255 do
    Logger.info("🔆 Setting SpaceMouse LED brightness: #{level}")
    
    case get_connected_device() do
      {:ok, device} ->
        # Try brightness control via Report ID 7
        case send_output_report(device, 7, [level]) do
          :ok ->
            Logger.info("✅ Brightness set to #{level}")
            :ok
            
          {:error, reason} ->
            Logger.warning("❌ Brightness control failed: #{inspect(reason)}")
            {:error, reason}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Pulse the LED smoothly.
  """
  def pulse_led(duration_ms \\ 2000) do
    Logger.info("💓 Pulsing SpaceMouse LED for #{duration_ms}ms")
    
    case get_connected_device() do
      {:ok, device} ->
        steps = 20
        step_duration = div(duration_ms, steps * 2)  # Up and down
        
        # Fade up
        Enum.each(0..steps, fn i ->
          brightness = round(i / steps * 255)
          send_output_report(device, 7, [brightness])
          Process.sleep(step_duration)
        end)
        
        # Fade down  
        Enum.each(steps..0, fn i ->
          brightness = round(i / steps * 255)
          send_output_report(device, 7, [brightness])
          Process.sleep(step_duration)
        end)
        
        {:ok, :pulsed}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
end
