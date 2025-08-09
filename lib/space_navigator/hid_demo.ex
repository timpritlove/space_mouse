defmodule SpaceNavigator.HidDemo do
  @moduledoc """
  Demo for HID-based SpaceMouse communication.
  """

  require Logger
  import Bitwise

  @doc """
  Test the HID-based SpaceMouse implementation.
  """
  def test_hid_spacemouse do
    Logger.info("=== HID SpaceMouse Test ===")
    
    case SpaceNavigator.HidSpacemouse.start_for_first_device(name: :hid_spacemouse) do
      {:ok, pid} ->
        Logger.info("✓ HID SpaceMouse started")
        
        # Analyze the HID descriptor first
        SpaceNavigator.HidSpacemouse.analyze_hid_descriptor(pid)
        
        # Subscribe to data
        :ok = SpaceNavigator.HidSpacemouse.subscribe(pid)
        Logger.info("✓ Subscribed to HID data")
        
        # Start reading
        case SpaceNavigator.HidSpacemouse.start_reading(pid) do
          {:ok, :started} ->
            Logger.info("✓ Started HID reading")
            Logger.info("\\n🎮 Move your SpaceMouse to see HID data!")
            
            # Listen for data for 15 seconds
            listen_for_hid_data(15_000)
            
            # Stop reading
            SpaceNavigator.HidSpacemouse.stop_reading(pid)
            Logger.info("✓ Stopped HID reading")
            
          {:error, reason} ->
            Logger.error("✗ Failed to start HID reading: #{inspect(reason)}")
        end
        
      {:error, reason} ->
        Logger.error("✗ Failed to start HID SpaceMouse: #{inspect(reason)}")
    end
  end

  @doc """
  Quick test of HID report descriptor only.
  """
  def test_hid_descriptor do
    Logger.info("=== HID Descriptor Test ===")
    
    case SpaceNavigator.HidSpacemouse.start_for_first_device() do
      {:ok, pid} ->
        case SpaceNavigator.HidSpacemouse.get_report_descriptor(pid) do
          {:ok, descriptor} ->
            Logger.info("✓ Got HID report descriptor: #{byte_size(descriptor)} bytes")
            
            # Show first 100 bytes in hex
            show_hex_dump(descriptor, 100)
            
            # Try to analyze the structure
            SpaceNavigator.HidSpacemouse.analyze_hid_descriptor(pid)
            
          {:error, reason} ->
            Logger.error("✗ Could not get HID descriptor: #{inspect(reason)}")
        end
        
      {:error, reason} ->
        Logger.error("✗ Could not start HID device: #{inspect(reason)}")
    end
  end

  @doc """
  Test raw HID report reading without motion parsing.
  """
  def test_raw_hid_reports do
    Logger.info("=== Raw HID Reports Test ===")
    
    case SpaceNavigator.UsbManager.find_devices(%{vendor_id: 0x256F}) do
      {:ok, [device | _]} ->
        case SpaceNavigator.UsbManager.open_device(device) do
          {:ok, connected_device} ->
            Logger.info("✓ Device connected")
            
            # Try to get different HID reports manually
            test_manual_hid_reports(connected_device)
            
          {:error, reason} ->
            Logger.error("✗ Could not connect: #{inspect(reason)}")
        end
        
      error ->
        Logger.error("✗ Could not find device: #{inspect(error)}")
    end
  end

  defp listen_for_hid_data(time_left) when time_left <= 0 do
    Logger.info("✓ HID listening session complete")
  end

  defp listen_for_hid_data(time_left) do
    receive do
      {:spacemouse_hid, {:motion, motion_data}} ->
        display_hid_motion(motion_data)
        listen_for_hid_data(time_left - 50)
        
      {:spacemouse_hid, message} ->
        Logger.info("HID Message: #{inspect(message)}")
        listen_for_hid_data(time_left - 50)
        
    after
      1000 ->
        Logger.info("📡 Listening for HID data... #{div(time_left, 1000)}s left")
        listen_for_hid_data(time_left - 1000)
    end
  end

  defp display_hid_motion(motion) do
    Logger.info("🎮 HID Motion [ID:#{motion.report_id}]: " <>
                "X=#{String.pad_leading(to_string(motion.x), 6)} " <>
                "Y=#{String.pad_leading(to_string(motion.y), 6)} " <>
                "Z=#{String.pad_leading(to_string(motion.z), 6)}")
    
    # Also show raw data for debugging
    if byte_size(motion.raw_data) <= 16 do
      raw_hex = motion.raw_data
      |> :binary.bin_to_list()
      |> Enum.map(&Integer.to_string(&1, 16))
      |> Enum.map(&String.pad_leading(&1, 2, "0"))
      |> Enum.join(" ")
      
      Logger.debug("  Raw: #{raw_hex}")
    end
  end

  defp show_hex_dump(data, max_bytes) do
    bytes_to_show = min(max_bytes, byte_size(data))
    chunk = binary_part(data, 0, bytes_to_show)
    
    Logger.info("\\nHex dump (first #{bytes_to_show} bytes):")
    
    chunk
    |> :binary.bin_to_list()
    |> Enum.chunk_every(16)
    |> Enum.with_index()
    |> Enum.each(fn {row, index} ->
      offset = Integer.to_string(index * 16, 16) |> String.pad_leading(4, "0")
      hex_part = row
      |> Enum.map(&Integer.to_string(&1, 16))
      |> Enum.map(&String.pad_leading(&1, 2, "0"))
      |> Enum.join(" ")
      |> String.pad_trailing(47)  # 16 * 3 - 1 = 47
      
      ascii_part = row
      |> Enum.map(fn byte -> 
        if byte >= 32 and byte <= 126, do: <<byte>>, else: "."
      end)
      |> Enum.join()
      
      Logger.info("#{offset}: #{hex_part} |#{ascii_part}|")
    end)
  end

  defp test_manual_hid_reports(device) do
    Logger.info("\\nTesting manual HID report requests...")
    
    # Try different HID GET_REPORT requests
    report_types = [
      {0x01, "Input"},
      {0x02, "Output"}, 
      {0x03, "Feature"}
    ]
    
    Enum.each(report_types, fn {report_type, type_name} ->
      Logger.info("\\nTesting #{type_name} reports:")
      
      Enum.each(0..5, fn report_id ->
        wValue = (report_type <<< 8) ||| report_id
        
        case :usb.read_control(
          device.handle,
          0x81,    # Device to Host, Class, Interface
          0x01,    # GET_REPORT
          wValue,  # Report Type + ID
          0,       # Interface 0
          64,      # Max length
          100      # Short timeout
        ) do
          {:ok, data} when byte_size(data) > 0 ->
            Logger.info("  ✓ #{type_name} Report #{report_id}: #{byte_size(data)} bytes")
            if byte_size(data) <= 16 do
              hex = data |> :binary.bin_to_list() |> Enum.map(&Integer.to_string(&1, 16)) |> Enum.join(" ")
              Logger.info("    Data: #{hex}")
            end
            
          {:error, :timeout} ->
            Logger.debug("    Timeout on #{type_name} #{report_id}")
            
          {:error, reason} ->
            Logger.debug("    Error #{type_name} #{report_id}: #{inspect(reason)}")
        end
      end)
    end)
  end

  @doc """
  Comprehensive test of all HID functionality.
  """
  def run_full_test do
    Logger.info("=== Complete HID SpaceMouse Test Suite ===")
    
    Logger.info("\\n1. Testing HID descriptor...")
    test_hid_descriptor()
    
    Process.sleep(1000)
    
    Logger.info("\\n2. Testing raw HID reports...")
    test_raw_hid_reports()
    
    Process.sleep(1000)
    
    Logger.info("\\n3. Testing HID SpaceMouse implementation...")
    test_hid_spacemouse()
    
    Logger.info("\\n✓ Full HID test complete")
  end
end
