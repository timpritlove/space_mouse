defmodule SpaceNavigator.HidExplorer do
  @moduledoc """
  Explore HID-specific functionality for SpaceMouse devices.
  
  Since SpaceMouse devices are HID devices, we need to explore
  their configuration and endpoint structure to understand
  how to read data properly.
  """

  require Logger

  @doc """
  Explore the full configuration of a SpaceMouse device.
  """
  def explore_hid_configuration do
    Logger.info("=== SpaceMouse HID Configuration Explorer ===")
    
    case SpaceNavigator.UsbManager.find_devices(%{vendor_id: 0x256F}) do
      {:ok, [device | _]} ->
        case SpaceNavigator.UsbManager.open_device(device) do
          {:ok, connected_device} ->
            explore_device_config(connected_device)
            explore_interfaces(connected_device)
            explore_endpoints(connected_device)
            test_hid_approaches(connected_device)
            
          {:error, reason} ->
            Logger.error("Failed to open device: #{inspect(reason)}")
        end
        
      {:ok, []} ->
        Logger.error("No SpaceMouse found")
        
      {:error, reason} ->
        Logger.error("Error finding device: #{inspect(reason)}")
    end
  end

  defp explore_device_config(device) do
    Logger.info("\\n=== Device Configuration ===")
    
    # Try to get all configurations
    Enum.each(0..2, fn config_num ->
      case safe_call(:usb, :get_config_descriptor, [device.device, config_num]) do
        {:ok, config} ->
          Logger.info("Configuration #{config_num}:")
          Logger.info("  Total Length: #{Map.get(config, :total_length, "unknown")}")
          Logger.info("  Num Interfaces: #{Map.get(config, :num_interfaces, "unknown")}")
          Logger.info("  Configuration Value: #{Map.get(config, :configuration_value, "unknown")}")
          Logger.info("  Attributes: 0x#{Integer.to_string(Map.get(config, :attributes, 0), 16)}")
          Logger.info("  Max Power: #{Map.get(config, :max_power, "unknown")} mA")
          
        _ ->
          Logger.debug("Configuration #{config_num} not available")
      end
    end)
  end

  defp explore_interfaces(device) do
    Logger.info("\\n=== Interface Exploration ===")
    
    # Try to explore interfaces
    Enum.each(0..3, fn interface_num ->
      Logger.info("Testing Interface #{interface_num}:")
      
      # Check if we can claim this interface
      case safe_call(:usb, :claim_interface, [device.handle, interface_num]) do
        :ok ->
          Logger.info("  ✓ Successfully claimed interface #{interface_num}")
          
          # Try to release it immediately
          case safe_call(:usb, :release_interface, [device.handle, interface_num]) do
            :ok -> Logger.info("  ✓ Released interface #{interface_num}")
            error -> Logger.info("  Warning: Could not release interface: #{inspect(error)}")
          end
          
        {:error, reason} ->
          Logger.info("  ✗ Could not claim interface #{interface_num}: #{inspect(reason)}")
      end
    end)
  end

  defp explore_endpoints(device) do
    Logger.info("\\n=== Endpoint Discovery ===")
    
    # Common HID endpoint addresses to try
    endpoints = [
      # Input endpoints (device to host)
      0x81, 0x82, 0x83, 0x84,
      # Output endpoints (host to device)  
      0x01, 0x02, 0x03, 0x04,
      # Additional possible endpoints
      0x85, 0x86, 0x87, 0x88
    ]
    
    # Try different transfer types
    transfer_types = [
      {:interrupt, :read_interrupt},
      {:bulk, :read_bulk}
    ]
    
    # Test each combination
    Enum.each(endpoints, fn endpoint ->
      Enum.each(transfer_types, fn {type, function} ->
        # Try different data sizes
        Enum.each([1, 7, 8, 13, 16, 32], fn size ->
          case safe_call(:usb, function, [device.handle, endpoint, size, 50]) do
            {:ok, data} ->
              Logger.info("✓ #{type} read from 0x#{Integer.to_string(endpoint, 16)}: #{byte_size(data)} bytes")
              Logger.info("  Data: #{inspect(data)}")
              
            {:error, :timeout} ->
              # This is actually good - means the endpoint exists but no data
              Logger.debug("  Timeout on 0x#{Integer.to_string(endpoint, 16)} (endpoint exists)")
              
            {:error, reason} ->
              Logger.debug("  Error 0x#{Integer.to_string(endpoint, 16)}: #{inspect(reason)}")
          end
        end)
      end)
    end)
  end

  defp test_hid_approaches(device) do
    Logger.info("\\n=== Alternative HID Approaches ===")
    
    # Test 1: Try control transfers (for HID class requests)
    test_control_transfers(device)
    
    # Test 2: Try without claiming interfaces
    test_unclaimed_reads(device)
    
    # Test 3: Try different configurations
    test_configurations(device)
  end

  defp test_control_transfers(device) do
    Logger.info("Testing HID control transfers...")
    
    # HID Class-Specific Requests
    # GET_REPORT = 0x01, SET_REPORT = 0x09
    
    # Try to get HID report descriptor
    # bmRequestType = 0x81 (Device to Host, Class, Interface)
    # bRequest = 0x06 (GET_DESCRIPTOR)  
    # wValue = 0x2200 (Report Descriptor type)
    # wIndex = 0 (Interface)
    # wLength = 256 (Max length)
    
    case safe_call(:usb, :read_control, [
      device.handle, 
      0x81,  # bmRequestType
      0x06,  # bRequest (GET_DESCRIPTOR)
      0x2200,  # wValue (Report descriptor)
      0,     # wIndex (Interface 0)
      256,   # wLength
      1000   # timeout
    ]) do
      {:ok, data} ->
        Logger.info("✓ Got HID Report Descriptor: #{byte_size(data)} bytes")
        Logger.info("  First 32 bytes: #{inspect(binary_part(data, 0, min(32, byte_size(data))))}")
        
      {:error, reason} ->
        Logger.info("✗ Could not get HID Report Descriptor: #{inspect(reason)}")
    end
  end

  defp test_unclaimed_reads(device) do
    Logger.info("Testing reads without claiming interface...")
    
    # Try reading from common HID endpoints without claiming
    common_endpoints = [0x81, 0x01]
    
    Enum.each(common_endpoints, fn endpoint ->
      case safe_call(:usb, :read_interrupt, [device.handle, endpoint, 8, 100]) do
        {:ok, data} ->
          Logger.info("✓ Read without claim from 0x#{Integer.to_string(endpoint, 16)}: #{inspect(data)}")
          
        {:error, :timeout} ->
          Logger.info("  Timeout on unclaimed 0x#{Integer.to_string(endpoint, 16)} (normal)")
          
        {:error, reason} ->
          Logger.info("  Error on unclaimed 0x#{Integer.to_string(endpoint, 16)}: #{inspect(reason)}")
      end
    end)
  end

  defp test_configurations(device) do
    Logger.info("Testing different configurations...")
    
    # Try to set different configurations
    Enum.each([0, 1], fn config ->
      case safe_call(:usb, :set_configuration, [device.handle, config]) do
        :ok ->
          Logger.info("✓ Set configuration #{config}")
          
          # Now try reading after setting config
          case safe_call(:usb, :read_interrupt, [device.handle, 0x81, 7, 100]) do
            {:ok, data} ->
              Logger.info("  ✓ Read after config #{config}: #{inspect(data)}")
              
            {:error, reason} ->
              Logger.info("  Read after config #{config}: #{inspect(reason)}")
          end
          
        {:error, reason} ->
          Logger.info("✗ Could not set configuration #{config}: #{inspect(reason)}")
      end
    end)
  end

  defp safe_call(module, function, args) do
    try do
      apply(module, function, args)
    rescue
      e -> {:error, e}
    catch
      :error, reason -> {:error, reason}
    end
  end

  @doc """
  Test different approaches to get SpaceMouse data working.
  """
  def test_data_approaches do
    Logger.info("=== Testing Data Reading Approaches ===")
    
    case SpaceNavigator.UsbManager.find_devices(%{vendor_id: 0x256F}) do
      {:ok, [device | _]} ->
        case SpaceNavigator.UsbManager.open_device(device) do
          {:ok, connected_device} ->
            # Approach 1: Try reading immediately after connection
            attempt_immediate_read(connected_device)
            
            # Approach 2: Try with configuration set
            attempt_configured_read(connected_device)
            
            # Approach 3: Try continuous polling
            attempt_continuous_polling(connected_device)
            
          {:error, reason} ->
            Logger.error("Could not open device: #{inspect(reason)}")
        end
        
      error ->
        Logger.error("Could not find device: #{inspect(error)}")
    end
  end

  defp attempt_immediate_read(device) do
    Logger.info("\\n--- Approach 1: Immediate Read ---")
    
    # Try reading from endpoint 0x81 with different sizes
    sizes = [6, 7, 8, 13]
    
    Enum.each(sizes, fn size ->
      case safe_call(:usb, :read_interrupt, [device.handle, 0x81, size, 500]) do
        {:ok, data} ->
          Logger.info("✓ Immediate read (#{size} bytes): #{inspect(data)}")
          
        {:error, reason} ->
          Logger.debug("Immediate read (#{size} bytes) failed: #{inspect(reason)}")
      end
    end)
  end

  defp attempt_configured_read(device) do
    Logger.info("\\n--- Approach 2: Configured Read ---")
    
    # Set configuration 1
    case safe_call(:usb, :set_configuration, [device.handle, 1]) do
      :ok ->
        Logger.info("Set configuration 1")
        
        # Try reading after configuration
        case safe_call(:usb, :read_interrupt, [device.handle, 0x81, 7, 500]) do
          {:ok, data} ->
            Logger.info("✓ Configured read: #{inspect(data)}")
            
          {:error, reason} ->
            Logger.info("Configured read failed: #{inspect(reason)}")
        end
        
      {:error, reason} ->
        Logger.info("Could not set configuration: #{inspect(reason)}")
    end
  end

  defp attempt_continuous_polling(device) do
    Logger.info("\\n--- Approach 3: Continuous Polling ---")
    Logger.info("Polling for 5 seconds... move your SpaceMouse!")
    
    poll_count = 0
    start_time = System.monotonic_time(:millisecond)
    
    poll_for_data(device, start_time, poll_count)
  end

  defp poll_for_data(device, start_time, poll_count) do
    current_time = System.monotonic_time(:millisecond)
    elapsed = current_time - start_time
    
    if elapsed < 5000 do
      case safe_call(:usb, :read_interrupt, [device.handle, 0x81, 7, 10]) do
        {:ok, data} ->
          Logger.info("✓ Poll #{poll_count}: #{inspect(data)}")
          
        {:error, :timeout} ->
          # Normal - continue polling
          nil
          
        {:error, reason} ->
          Logger.debug("Poll #{poll_count} error: #{inspect(reason)}")
      end
      
      # Small delay and continue
      Process.sleep(5)
      poll_for_data(device, start_time, poll_count + 1)
    else
      Logger.info("Polling complete after #{poll_count} attempts")
    end
  end
end
