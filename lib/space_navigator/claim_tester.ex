defmodule SpaceNavigator.ClaimTester do
  @moduledoc """
  Test whether the SpaceMouse device is actually claimed by the system
  or if there are other issues preventing data access.
  """

  require Logger

  @doc """
  Test if the device is actually claimed by checking various indicators.
  """
  def test_device_claim_status do
    Logger.info("=== Device Claim Status Investigation ===")
    
    case SpaceNavigator.UsbManager.find_devices(%{vendor_id: 0x256F}) do
      {:ok, [device | _]} ->
        case SpaceNavigator.UsbManager.open_device(device) do
          {:ok, connected_device} ->
            test_claim_indicators(connected_device)
            test_interface_access(connected_device)
            test_endpoint_enumeration(connected_device)
            test_configuration_access(connected_device)
            
          {:error, reason} ->
            Logger.error("Could not open device: #{inspect(reason)}")
        end
        
      error ->
        Logger.error("Could not find device: #{inspect(error)}")
    end
  end

  defp test_claim_indicators(device) do
    Logger.info("\\n--- Testing Claim Indicators ---")
    
    # Test 1: Can we get device information?
    Logger.info("1. Device handle access:")
    Logger.info("   Handle: #{inspect(device.handle)}")
    Logger.info("   ✓ Device handle obtained (suggests device is accessible)")
    
    # Test 2: Can we get configuration info?
    case :usb.get_config_descriptor(device.device, 0) do
      {:ok, config} ->
        Logger.info("2. Configuration descriptor access:")
        Logger.info("   ✓ Can read configuration (device not fully claimed)")
        Logger.info("   Interfaces: #{Map.get(config, :num_interfaces, "unknown")}")
        
      {:error, reason} ->
        Logger.info("2. Configuration descriptor access:")
        Logger.error("   ✗ Cannot read configuration: #{inspect(reason)}")
    end
    
    # Test 3: Check current configuration
    {:error, reason} = get_active_configuration(device)
    Logger.info("3. Active configuration error: #{inspect(reason)}")
  end

  defp test_interface_access(device) do
    Logger.info("\\n--- Testing Interface Access ---")
    
    # Try to claim each interface and see what specific errors we get
    Enum.each(0..2, fn interface_num ->
      Logger.info("Testing interface #{interface_num}:")
      
      case :usb.claim_interface(device.handle, interface_num) do
        :ok ->
          Logger.info("  ✓ Successfully claimed interface #{interface_num}")
          Logger.info("    This suggests the interface was NOT claimed by system!")
          
          # Try to release it
          case :usb.release_interface(device.handle, interface_num) do
            :ok ->
              Logger.info("  ✓ Successfully released interface #{interface_num}")
            {:error, reason} ->
              Logger.warning("  Warning: Could not release interface: #{inspect(reason)}")
          end
          
        {:error, :access} ->
          Logger.info("  ✗ Access denied - interface #{interface_num} IS claimed by system")
          
        {:error, :not_found} ->
          Logger.info("  - Interface #{interface_num} does not exist")
          
        {:error, :busy} ->
          Logger.info("  ✗ Interface #{interface_num} is busy (claimed by system)")
          
        {:error, reason} ->
          Logger.info("  ✗ Interface #{interface_num} error: #{inspect(reason)}")
      end
    end)
  end

  defp test_endpoint_enumeration(device) do
    Logger.info("\\n--- Testing Endpoint Discovery ---")
    
    # If the device is unclaimed, we should be able to find some endpoints
    # Let's be more systematic about endpoint discovery
    
    Logger.info("Testing endpoint accessibility...")
    
    # Try more endpoint addresses and be more specific about errors
    endpoints = [
      {0x81, "IN endpoint 1"},
      {0x01, "OUT endpoint 1"}, 
      {0x82, "IN endpoint 2"},
      {0x02, "OUT endpoint 2"},
      {0x83, "IN endpoint 3"},
      {0x03, "OUT endpoint 3"}
    ]
    
    found_endpoints = Enum.reduce(endpoints, [], fn {endpoint, desc}, acc ->
      # Try interrupt transfer first
      case :usb.read_interrupt(device.handle, endpoint, 8, 10) do
        {:ok, data} ->
          Logger.info("  ✓ #{desc} (0x#{Integer.to_string(endpoint, 16)}): Got #{byte_size(data)} bytes")
          [endpoint | acc]
          
        {:error, :timeout} ->
          Logger.info("  ~ #{desc} (0x#{Integer.to_string(endpoint, 16)}): Timeout (endpoint exists, no data)")
          [endpoint | acc]
          
        {:error, :not_found} ->
          Logger.debug("  - #{desc} (0x#{Integer.to_string(endpoint, 16)}): Not found")
          acc
          
        {:error, :pipe} ->
          Logger.info("  ✗ #{desc} (0x#{Integer.to_string(endpoint, 16)}): Pipe error (claimed/busy)")
          acc
          
        {:error, :io} ->
          Logger.info("  ✗ #{desc} (0x#{Integer.to_string(endpoint, 16)}): I/O error (device issue)")
          acc
          
        {:error, reason} ->
          Logger.info("  ? #{desc} (0x#{Integer.to_string(endpoint, 16)}): #{inspect(reason)}")
          acc
      end
    end)
    
    if Enum.empty?(found_endpoints) do
      Logger.warning("No accessible endpoints found - this suggests system claiming OR endpoint issues")
    else
      Logger.info("Found #{length(found_endpoints)} accessible endpoints: #{inspect(found_endpoints)}")
    end
  end

  defp test_configuration_access(device) do
    Logger.info("\\n--- Testing Configuration Management ---")
    
    # Test if we can change configurations (unclaimed devices allow this)
    Logger.info("Testing configuration changes...")
    
    # Get current configuration first
    {:error, _} = get_active_configuration(device)
    current_config = "unknown"
    
    Logger.info("Current configuration: #{current_config}")
    
    # Try to set different configurations
    Enum.each([0, 1], fn config_num ->
      case :usb.set_configuration(device.handle, config_num) do
        :ok ->
          Logger.info("  ✓ Successfully set configuration #{config_num}")
          Logger.info("    This suggests device is NOT claimed by system!")
          
        {:error, :busy} ->
          Logger.info("  ✗ Configuration #{config_num} busy (system claimed)")
          
        {:error, reason} ->
          Logger.info("  ? Configuration #{config_num}: #{inspect(reason)}")
      end
    end)
  end

  defp get_active_configuration(_device) do
    # get_configuration is not available in the usb package
    {:error, :not_supported}
  end

  @doc """
  Test alternative approaches to verify if the device is accessible.
  """
  def test_alternative_access_methods do
    Logger.info("=== Alternative Access Method Tests ===")
    
    case SpaceNavigator.UsbManager.find_devices(%{vendor_id: 0x256F}) do
      {:ok, [device | _]} ->
        case SpaceNavigator.UsbManager.open_device(device) do
          {:ok, connected_device} ->
            test_bulk_transfers(connected_device)
            test_control_transfers_detailed(connected_device)
            test_different_transfer_sizes(connected_device)
            
          error ->
            Logger.error("Could not open device: #{inspect(error)}")
        end
        
      error ->
        Logger.error("Could not find device: #{inspect(error)}")
    end
  end

  defp test_bulk_transfers(device) do
    Logger.info("\\n--- Testing Bulk Transfers ---")
    
    # If interrupt transfers fail, maybe bulk transfers work?
    endpoints = [0x81, 0x01, 0x82, 0x02]
    
    Enum.each(endpoints, fn endpoint ->
      case :usb.read_bulk(device.handle, endpoint, 8, 100) do
        {:ok, data} ->
          Logger.info("  ✓ Bulk read 0x#{Integer.to_string(endpoint, 16)}: #{byte_size(data)} bytes")
          
        {:error, :timeout} ->
          Logger.info("  ~ Bulk timeout 0x#{Integer.to_string(endpoint, 16)} (endpoint exists)")
          
        {:error, reason} ->
          Logger.debug("  - Bulk 0x#{Integer.to_string(endpoint, 16)}: #{inspect(reason)}")
      end
    end)
  end

  defp test_control_transfers_detailed(device) do
    Logger.info("\\n--- Testing Control Transfers (Detailed) ---")
    
    # Test standard USB requests that should work if device is unclaimed
    
    # 1. GET_STATUS
    case :usb.read_control(device.handle, 0x80, 0x00, 0, 0, 2, 1000) do
      {:ok, data} ->
        Logger.info("  ✓ GET_STATUS: #{inspect(data)}")
      {:error, reason} ->
        Logger.info("  ✗ GET_STATUS failed: #{inspect(reason)}")
    end
    
    # 2. GET_DESCRIPTOR (Device)
    case :usb.read_control(device.handle, 0x80, 0x06, 0x0100, 0, 18, 1000) do
      {:ok, data} ->
        Logger.info("  ✓ GET_DESCRIPTOR (Device): #{byte_size(data)} bytes")
      {:error, reason} ->
        Logger.info("  ✗ GET_DESCRIPTOR failed: #{inspect(reason)}")
    end
    
    # 3. HID-specific requests (should fail if claimed)
    case :usb.read_control(device.handle, 0x81, 0x06, 0x2200, 0, 100, 1000) do
      {:ok, data} ->
        Logger.info("  ✓ HID Report Descriptor: #{byte_size(data)} bytes (NOT claimed by HID system)")
      {:error, reason} ->
        Logger.info("  ✗ HID Report Descriptor failed: #{inspect(reason)}")
    end
  end

  defp test_different_transfer_sizes(device) do
    Logger.info("\\n--- Testing Different Transfer Sizes ---")
    
    # Maybe the issue is transfer size, not claiming
    sizes = [1, 4, 7, 8, 16, 32, 64]
    endpoint = 0x81
    
    Enum.each(sizes, fn size ->
      case :usb.read_interrupt(device.handle, endpoint, size, 50) do
        {:ok, data} ->
          Logger.info("  ✓ Size #{size}: Got #{byte_size(data)} bytes")
          
        {:error, :timeout} ->
          Logger.debug("  ~ Size #{size}: Timeout")
          
        {:error, reason} ->
          Logger.debug("  - Size #{size}: #{inspect(reason)}")
      end
    end)
  end

  @doc """
  Compare with a known working USB device (if available) to verify our approach.
  """
  def test_usb_library_functionality do
    Logger.info("=== USB Library Functionality Test ===")
    
    # Test the USB library with the SpaceMouse to see what works
    case SpaceNavigator.UsbManager.list_devices() do
      {:ok, devices} ->
        Logger.info("USB library can enumerate #{length(devices)} device(s)")
        
        # Try with our SpaceMouse
        spacemouse = Enum.find(devices, fn d -> d.vendor_id == 0x256F end)
        
        if spacemouse do
          Logger.info("SpaceMouse found in enumeration")
          test_spacemouse_specific_access(spacemouse)
        else
          Logger.warning("SpaceMouse not found in enumeration")
        end
        
      {:error, reason} ->
        Logger.error("USB enumeration failed: #{inspect(reason)}")
    end
  end

  defp test_spacemouse_specific_access(device) do
    Logger.info("\\n--- SpaceMouse-Specific Access Test ---")
    
    case SpaceNavigator.UsbManager.open_device(device) do
      {:ok, connected} ->
        Logger.info("✓ SpaceMouse opened successfully")
        
        # The fact that we can open it suggests it's not claimed
        Logger.info("Device opened - this indicates it's likely NOT claimed by system")
        
        # Test basic operations
        test_basic_spacemouse_operations(connected)
        
      {:error, reason} ->
        Logger.error("✗ Could not open SpaceMouse: #{inspect(reason)}")
        
        case reason do
          :access -> Logger.info("  → Device IS claimed by system")
          :busy -> Logger.info("  → Device IS busy/claimed")
          _ -> Logger.info("  → Other issue: #{inspect(reason)}")
        end
    end
  end

  defp test_basic_spacemouse_operations(device) do
    Logger.info("Testing basic SpaceMouse operations...")
    
    # If we can do these operations, the device is definitely not claimed
    operations = [
      # reset_device and set_interface_alt_setting are not available in the usb package
      {"Clear halt on EP 0x81", fn -> :usb.clear_halt(device.handle, 0x81) end}
    ]
    
    Enum.each(operations, fn {desc, operation} ->
      try do
        case operation.() do
          :ok ->
            Logger.info("  ✓ #{desc} succeeded")
          {:error, reason} ->
            Logger.info("  ✗ #{desc} failed: #{inspect(reason)}")
        end
      rescue
        UndefinedFunctionError ->
          Logger.debug("  - #{desc} function not available")
      catch
        :error, reason ->
          Logger.info("  ✗ #{desc} error: #{inspect(reason)}")
      end
    end)
  end

  @doc """
  Run comprehensive device claim analysis.
  """
  def run_comprehensive_test do
    Logger.info("🔍 COMPREHENSIVE DEVICE CLAIM ANALYSIS")
    Logger.info("=====================================")
    
    test_device_claim_status()
    
    Logger.info("\\n" <> String.duplicate("=", 50))
    test_alternative_access_methods()
    
    Logger.info("\\n" <> String.duplicate("=", 50))  
    test_usb_library_functionality()
    
    Logger.info("\\n🎯 ANALYSIS COMPLETE")
    Logger.info("Check the results above to determine if the device is actually claimed by macOS")
  end
end
