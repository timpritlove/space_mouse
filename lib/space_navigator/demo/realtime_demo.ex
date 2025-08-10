defmodule SpaceNavigator.RealtimeDemo do
  @moduledoc """
  Real-time demonstration of SpaceMouse data capture.
  
  This module shows how to:
  - Connect to a SpaceMouse device
  - Start real-time data reading
  - Process motion and button events
  - Display live data updates
  """

  require Logger

  @doc """
  Start capturing real-time data from the SpaceMouse.
  """
  def start_realtime_capture do
    Logger.info("=== SpaceMouse Real-time Data Capture ===")
    
    case SpaceNavigator.SpacemouseReader.start_for_first_device(name: :spacemouse_reader) do
      {:ok, reader_pid} ->
        Logger.info("✓ SpaceMouse reader started")
        
        # Subscribe to data updates
        :ok = SpaceNavigator.SpacemouseReader.subscribe(reader_pid)
        Logger.info("✓ Subscribed to data updates")
        
        # Start reading
        case SpaceNavigator.SpacemouseReader.start_reading(reader_pid) do
          {:ok, :started} ->
            Logger.info("✓ Started reading SpaceMouse data")
            Logger.info("\\n🎮 Move your SpaceMouse to see real-time data!")
            Logger.info("Press Ctrl+C to stop")
            
            # Start the data processing loop
            data_loop(reader_pid)
            
          {:error, reason} ->
            Logger.error("✗ Failed to start reading: #{inspect(reason)}")
            {:error, reason}
        end
        
      {:error, :no_spacemouse_found} ->
        Logger.error("✗ No SpaceMouse device found")
        Logger.info("Please ensure your SpaceMouse is connected")
        {:error, :no_device}
        
      {:error, reason} ->
        Logger.error("✗ Failed to start SpaceMouse reader: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Simple data capture test - read a few samples.
  """
  def test_data_reading do
    Logger.info("=== SpaceMouse Data Reading Test ===")
    
    case SpaceNavigator.SpacemouseReader.start_for_first_device() do
      {:ok, reader_pid} ->
        # Subscribe to updates
        :ok = SpaceNavigator.SpacemouseReader.subscribe(reader_pid)
        
        # Start reading
        case SpaceNavigator.SpacemouseReader.start_reading(reader_pid) do
          {:ok, :started} ->
            Logger.info("Reading SpaceMouse data for 10 seconds...")
            Logger.info("Move your SpaceMouse to generate data")
            
            # Collect data for 10 seconds
            samples = collect_samples(10_000, [])
            
            # Stop reading
            SpaceNavigator.SpacemouseReader.stop_reading(reader_pid)
            
            Logger.info("\\nCollected #{length(samples)} motion samples:")
            if length(samples) > 0 do
              show_sample_summary(samples)
            else
              Logger.info("No motion detected - try moving the SpaceMouse")
            end
            
            {:ok, samples}
            
          {:error, reason} ->
            Logger.error("Failed to start reading: #{inspect(reason)}")
            {:error, reason}
        end
        
      {:error, reason} ->
        Logger.error("Failed to start reader: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Test basic device connection and configuration.
  """
  def test_device_connection do
    Logger.info("=== SpaceMouse Connection Test ===")
    
    # Find SpaceMouse device
    case SpaceNavigator.UsbManager.find_devices(%{vendor_id: 0x256F}) do
      {:ok, [device | _]} ->
        Logger.info("✓ Found SpaceMouse device")
        
        # Try to open the device
        case SpaceNavigator.UsbManager.open_device(device) do
          {:ok, connected_device} ->
            Logger.info("✓ Successfully opened device")
            Logger.info("  Device handle: #{inspect(connected_device.handle)}")
            
            # Try to read configuration
            test_device_configuration(connected_device)
            
            # Try a single data read
            test_single_read(connected_device)
            
            {:ok, connected_device}
            
          {:error, reason} ->
            Logger.error("✗ Failed to open device: #{inspect(reason)}")
            {:error, reason}
        end
        
      {:ok, []} ->
        Logger.error("✗ No SpaceMouse device found")
        {:error, :no_device}
        
      {:error, reason} ->
        Logger.error("✗ Failed to find devices: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp test_device_configuration(device) do
    Logger.info("\\nTesting device configuration...")
    
    # Try to claim interface 0 (typical for HID devices)
    case :usb.claim_interface(device.handle, 0) do
      :ok ->
        Logger.info("✓ Successfully claimed interface 0")
        
        # Try to get configuration descriptor
        case :usb.get_config_descriptor(device.device, 0) do
          {:ok, config} ->
            Logger.info("✓ Got configuration descriptor")
            Logger.info("  Interfaces: #{Map.get(config, :num_interfaces, "unknown")}")
            
          {:error, reason} ->
            Logger.warning("Could not get config descriptor: #{inspect(reason)}")
        end
        
        :ok
        
      {:error, reason} ->
        Logger.warning("Could not claim interface: #{inspect(reason)}")
        Logger.info("(This might be normal for some systems)")
        :ok
    end
  end

  defp test_single_read(device) do
    Logger.info("\\nTesting single data read...")
    
    # Try different endpoint addresses and report sizes
    endpoints = [0x81, 0x01, 0x82, 0x02]
    sizes = [7, 8, 13, 16]
    
    Enum.each(endpoints, fn endpoint ->
      Enum.each(sizes, fn size ->
        case SpaceNavigator.UsbManager.read_data(device, endpoint, size, 100) do
          {:ok, data} ->
            Logger.info("✓ Read #{byte_size(data)} bytes from endpoint 0x#{Integer.to_string(endpoint, 16)}")
            Logger.info("  Data: #{inspect(data)}")
            
          {:error, :timeout} ->
            Logger.debug("  Timeout on endpoint 0x#{Integer.to_string(endpoint, 16)} (normal)")
            
          {:error, reason} ->
            Logger.debug("  Error on endpoint 0x#{Integer.to_string(endpoint, 16)}: #{inspect(reason)}")
        end
      end)
    end)
  end

  defp data_loop(reader_pid) do
    receive do
      {:spacemouse_data, {:motion, motion_data}} ->
        display_motion_data(motion_data)
        data_loop(reader_pid)
        
      {:spacemouse_data, {:button, button_data}} ->
        display_button_data(button_data)
        data_loop(reader_pid)
        
    after
      5000 ->
        # Check if still reading
        case SpaceNavigator.SpacemouseReader.get_motion_state(reader_pid) do
          {:ok, state} ->
            if state.reading do
              Logger.info("📡 Still listening for SpaceMouse data...")
              data_loop(reader_pid)
            else
              Logger.info("Reading stopped")
            end
            
          {:error, _} ->
            Logger.info("Reader stopped")
        end
    end
  end

  defp collect_samples(time_left, samples) when time_left <= 0, do: samples

  defp collect_samples(time_left, samples) do
    receive do
      {:spacemouse_data, {:motion, motion_data}} ->
        collect_samples(time_left, [motion_data | samples])
        
    after
      100 ->
        collect_samples(time_left - 100, samples)
    end
  end

  defp display_motion_data(motion) do
    # Display motion data in a readable format
    Logger.info("🎮 Motion: X=#{String.pad_leading(to_string(motion.x), 6)} " <>
                "Y=#{String.pad_leading(to_string(motion.y), 6)} " <>
                "Z=#{String.pad_leading(to_string(motion.z), 6)} " <>
                "[#{motion.timestamp}]")
  end

  defp display_button_data(button) do
    Logger.info("🔘 Button: #{inspect(button)}")
  end

  defp show_sample_summary(samples) do
    if length(samples) > 0 do
      # Calculate some basic statistics
      x_values = Enum.map(samples, & &1.x)
      y_values = Enum.map(samples, & &1.y)
      z_values = Enum.map(samples, & &1.z)
      
      Logger.info("  X range: #{Enum.min(x_values)} to #{Enum.max(x_values)}")
      Logger.info("  Y range: #{Enum.min(y_values)} to #{Enum.max(y_values)}")
      Logger.info("  Z range: #{Enum.min(z_values)} to #{Enum.max(z_values)}")
      
      # Show first few samples
      Logger.info("\\nFirst few samples:")
      samples
      |> Enum.reverse()
      |> Enum.take(5)
      |> Enum.each(fn sample ->
        Logger.info("  #{sample.x}, #{sample.y}, #{sample.z}")
      end)
    end
  end

  @doc """
  Quick test to verify everything is working.
  """
  def quick_test do
    Logger.info("=== SpaceMouse Quick Test ===")
    
    # Test 1: Device discovery
    Logger.info("1. Testing device discovery...")
    case SpaceNavigator.UsbManager.find_devices(%{vendor_id: 0x256F}) do
      {:ok, [_ | _] = devices} ->
        Logger.info("✓ Found #{length(devices)} SpaceMouse device(s)")
        
        # Test 2: Device connection
        Logger.info("2. Testing device connection...")
        test_device_connection()
        
      {:ok, []} ->
        Logger.error("✗ No SpaceMouse devices found")
        
      {:error, reason} ->
        Logger.error("✗ Error finding devices: #{inspect(reason)}")
    end
  end
end
