defmodule SpaceNavigator.InterfaceDetacher do
  @moduledoc """
  Attempts to detach macOS kernel drivers from USB interfaces to enable direct access.
  
  This module provides several strategies to unclaim interfaces that have been
  automatically claimed by macOS system drivers (like the Generic HID driver).
  
  Methods attempted:
  1. Kernel driver detachment (if supported)
  2. Interface claiming with force
  3. Alternative configurations
  4. Device reset and reclaim
  """

  require Logger

  @doc """
  Attempts to detach the kernel driver from a USB interface.
  
  This is the most direct approach - if the USB library supports it,
  we can detach the kernel driver and claim the interface ourselves.
  """
  def detach_kernel_driver(device, interface_num \\ 0) do
    Logger.info("=== Attempting Kernel Driver Detachment ===")
    Logger.info("Device: #{inspect_device(device)}")
    Logger.info("Interface: #{interface_num}")
    
    # Check if we can detach kernel driver
    case check_detach_support(device, interface_num) do
      {:ok, :can_detach} ->
        perform_kernel_detach(device, interface_num)
        
      {:ok, :already_detached} ->
        Logger.info("✓ Kernel driver already detached")
        claim_interface_direct(device, interface_num)
        
      {:error, :not_supported} ->
        Logger.info("⚠ Kernel driver detach not supported by USB library")
        try_alternative_methods(device, interface_num)
        
      {:error, reason} ->
        Logger.error("✗ Cannot detach kernel driver: #{inspect(reason)}")
        try_alternative_methods(device, interface_num)
    end
  end

  defp check_detach_support(device, interface_num) do
    # Try to check if kernel driver is active
    # Note: The :usb package might not expose this functionality
    case try_usb_function(:usb, :kernel_driver_active, [device.handle, interface_num]) do
      {:ok, true} ->
        Logger.info("Kernel driver is active on interface #{interface_num}")
        {:ok, :can_detach}
        
      {:ok, false} ->
        Logger.info("No kernel driver active on interface #{interface_num}")
        {:ok, :already_detached}
        
      {:error, :function_not_found} ->
        Logger.info("USB library doesn't support kernel driver detection")
        {:error, :not_supported}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp perform_kernel_detach(device, interface_num) do
    Logger.info("Attempting to detach kernel driver...")
    
    case try_usb_function(:usb, :detach_kernel_driver, [device.handle, interface_num]) do
      {:ok, _} ->
        Logger.info("✓ Successfully detached kernel driver")
        claim_interface_direct(device, interface_num)
        
      {:error, :function_not_found} ->
        Logger.info("⚠ USB library doesn't support kernel driver detachment")
        try_alternative_methods(device, interface_num)
        
      {:error, reason} ->
        Logger.error("✗ Failed to detach kernel driver: #{inspect(reason)}")
        try_alternative_methods(device, interface_num)
    end
  end

  defp claim_interface_direct(device, interface_num) do
    Logger.info("Attempting to claim interface #{interface_num}...")
    
    case :usb.claim_interface(device.handle, interface_num) do
      :ok ->
        Logger.info("✓ Successfully claimed interface #{interface_num}")
        {:ok, :claimed}
        
      {:error, :busy} ->
        Logger.info("✗ Interface still busy (kernel driver still active)")
        {:error, :still_claimed}
        
      {:error, reason} ->
        Logger.error("✗ Failed to claim interface: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp try_alternative_methods(device, interface_num) do
    Logger.info("\\n=== Trying Alternative Methods ===")
    
    # Method 1: Reset device and try to claim quickly
    result1 = try_reset_and_claim(device, interface_num)
    
    # Method 2: Try different configurations
    result2 = try_alternative_configurations(device, interface_num)
    
    # Method 3: Force claim with different alt settings
    result3 = try_alt_settings(device, interface_num)
    
    # Return the first successful result
    case {result1, result2, result3} do
      {{:ok, :claimed}, _, _} -> {:ok, :claimed}
      {_, {:ok, :claimed}, _} -> {:ok, :claimed}
      {_, _, {:ok, :claimed}} -> {:ok, :claimed}
      _ -> {:error, :all_methods_failed}
    end
  end

  defp try_reset_and_claim(device, interface_num) do
    Logger.info("Method 1: Reset device and quick claim...")
    
    # Try to reset the device (this might disconnect kernel drivers temporarily)
    case try_usb_function(:usb, :reset_device, [device.handle]) do
      {:ok, _} ->
        Logger.info("✓ Device reset successful")
        
        # Small delay to let system stabilize
        Process.sleep(50)
        
        # Try to claim interface quickly before kernel driver reattaches
        case :usb.claim_interface(device.handle, interface_num) do
          :ok ->
            Logger.info("✓ Quick claim successful after reset!")
            {:ok, :claimed}
            
          {:error, reason} ->
            Logger.info("✗ Quick claim failed: #{inspect(reason)}")
            {:error, reason}
        end
        
      {:error, reason} ->
        Logger.info("✗ Device reset failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp try_alternative_configurations(device, interface_num) do
    Logger.info("Method 2: Trying alternative configurations...")
    
    # Get available configurations
    configurations = get_available_configurations(device)
    
    Logger.info("Found #{length(configurations)} configurations")
    
    Enum.reduce_while(configurations, {:error, :no_configs}, fn config_value, _acc ->
      Logger.info("Trying configuration #{config_value}...")
      
      case :usb.set_configuration(device.handle, config_value) do
        :ok ->
          Logger.info("✓ Set configuration #{config_value}")
          
          # Try to claim interface with this configuration
          case :usb.claim_interface(device.handle, interface_num) do
            :ok ->
              Logger.info("✓ Claimed interface with config #{config_value}!")
              {:halt, {:ok, :claimed}}
              
            {:error, reason} ->
              Logger.info("✗ Still cannot claim interface: #{inspect(reason)}")
              {:cont, {:error, reason}}
          end
          
        {:error, reason} ->
          Logger.info("✗ Cannot set configuration #{config_value}: #{inspect(reason)}")
          {:cont, {:error, reason}}
      end
    end)
  end

  defp try_alt_settings(device, interface_num) do
    Logger.info("Method 3: Trying alternative interface settings...")
    
    # Try different alternate settings for the interface
    alt_settings = [0, 1, 2]
    
    Enum.reduce_while(alt_settings, {:error, :no_alt_settings}, fn alt_setting, _acc ->
      Logger.info("Trying alt setting #{alt_setting}...")
      
      case try_usb_function(:usb, :set_interface_alt_setting, [device.handle, interface_num, alt_setting]) do
        {:ok, _} ->
          Logger.info("✓ Set alt setting #{alt_setting}")
          
          # Try to claim interface
          case :usb.claim_interface(device.handle, interface_num) do
            :ok ->
              Logger.info("✓ Claimed interface with alt setting #{alt_setting}!")
              {:halt, {:ok, :claimed}}
              
            {:error, reason} ->
              Logger.info("✗ Still cannot claim: #{inspect(reason)}")
              {:cont, {:error, reason}}
          end
          
        {:error, reason} ->
          Logger.info("✗ Cannot set alt setting #{alt_setting}: #{inspect(reason)}")
          {:cont, {:error, reason}}
      end
    end)
  end

  defp get_available_configurations(device) do
    # Try configurations 0, 1, 2 (most common)
    [0, 1, 2]
    |> Enum.filter(fn config_value ->
      case try_usb_function(:usb, :get_config_descriptor, [device.device, config_value]) do
        {:ok, _config} -> true
        _ -> false
      end
    end)
  end

  @doc """
  Test all detachment methods on a SpaceMouse device.
  """
  def test_spacemouse_detachment do
    Logger.info("=== SpaceMouse Interface Detachment Test ===")
    
    case SpaceNavigator.UsbManager.find_devices(%{vendor_id: 0x256F}) do
      {:ok, [device | _]} ->
        case SpaceNavigator.UsbManager.open_device(device) do
          {:ok, connected_device} ->
            Logger.info("✓ SpaceMouse device connected")
            
            # Test detachment on interface 0 (HID interface)
            result = detach_kernel_driver(connected_device, 0)
            
            case result do
              {:ok, :claimed} ->
                Logger.info("\\n🎉 SUCCESS! Interface 0 is now claimed by our application!")
                test_claimed_interface_access(connected_device)
                
                # Release interface when done
                case :usb.release_interface(connected_device.handle, 0) do
                  :ok -> Logger.info("✓ Released interface")
                  error -> Logger.info("Warning: Could not release interface: #{inspect(error)}")
                end
                
              {:error, reason} ->
                Logger.error("\\n❌ FAILED: Could not detach interface - #{inspect(reason)}")
                Logger.info("\\nThis means:")
                Logger.info("• macOS Generic HID driver has exclusive access")
                Logger.info("• Direct USB access is blocked")
                Logger.info("• Need to use IOKit HID API instead")
            end
            
          {:error, reason} ->
            Logger.error("Could not connect to device: #{inspect(reason)}")
        end
        
      {:ok, []} ->
        Logger.error("No SpaceMouse devices found")
        
      {:error, reason} ->
        Logger.error("Error finding devices: #{inspect(reason)}")
    end
  end

  defp test_claimed_interface_access(device) do
    Logger.info("\\n=== Testing Direct Interface Access ===")
    
    # Now that we have the interface claimed, try HID requests again
    Logger.info("Testing HID report access with claimed interface...")
    
    # Try HID GET_REPORT request
    case :usb.read_control(
      device.handle,
      0x81,    # bmRequestType
      0x01,    # bRequest: GET_REPORT
      0x0101,  # wValue: Input Report Type + Report ID 1
      0,       # wIndex: Interface 0
      64,      # wLength
      1000     # timeout
    ) do
      {:ok, data} when byte_size(data) > 1 ->
        Logger.info("🎉 SUCCESS! Got HID report data: #{byte_size(data)} bytes")
        
        hex_data = data 
        |> :binary.bin_to_list() 
        |> Enum.take(16)
        |> Enum.map(&Integer.to_string(&1, 16))
        |> Enum.map(&String.pad_leading(&1, 2, "0"))
        |> Enum.join(" ")
        
        Logger.info("Data: #{hex_data}")
        
      {:error, reason} ->
        Logger.info("Still getting error: #{inspect(reason)}")
        Logger.info("Interface claimed but HID reports still blocked")
    end
    
    # Try interrupt endpoint access
    test_interrupt_endpoints(device)
  end

  defp test_interrupt_endpoints(device) do
    Logger.info("Testing interrupt endpoints with claimed interface...")
    
    # Common HID interrupt endpoints
    endpoints = [0x81, 0x01, 0x82, 0x02]
    
    Enum.each(endpoints, fn endpoint ->
      case :usb.read_interrupt(device.handle, endpoint, 16, 100) do
        {:ok, data} ->
          Logger.info("✓ Endpoint 0x#{Integer.to_string(endpoint, 16)}: #{byte_size(data)} bytes")
          
        {:error, :timeout} ->
          Logger.debug("  Endpoint 0x#{Integer.to_string(endpoint, 16)}: Timeout (normal)")
          
        {:error, :not_found} ->
          Logger.debug("  Endpoint 0x#{Integer.to_string(endpoint, 16)}: Not found")
          
        {:error, reason} ->
          Logger.info("  Endpoint 0x#{Integer.to_string(endpoint, 16)}: #{inspect(reason)}")
      end
    end)
  end

  # Helper function to safely try USB functions that might not be implemented
  defp try_usb_function(module, function, args) do
    case function_exported?(module, function, length(args)) do
      true ->
        try do
          result = apply(module, function, args)
          {:ok, result}
        rescue
          UndefinedFunctionError ->
            {:error, :function_not_found}
          error ->
            {:error, error}
        catch
          :error, :undef ->
            {:error, :function_not_found}
          :error, reason ->
            {:error, reason}
        end
        
      false ->
        {:error, :function_not_found}
    end
  end

  defp inspect_device(device) do
    "VID:#{Integer.to_string(device.vendor_id, 16)} PID:#{Integer.to_string(device.product_id, 16)}"
  end

  @doc """
  Quick test to see if interface detachment is possible on this system.
  """
  def quick_detachment_test do
    Logger.info("=== Quick Interface Detachment Test ===")
    
    # Test if the USB library supports detachment functions
    detach_functions = [
      {:kernel_driver_active, 2},
      {:detach_kernel_driver, 2},
      {:attach_kernel_driver, 2},
      {:reset_device, 1},
      {:set_interface_alt_setting, 3}
    ]
    
    Logger.info("Checking USB library capabilities:")
    
    Enum.each(detach_functions, fn {func_name, arity} ->
      exists = function_exported?(:usb, func_name, arity)
      status = if exists, do: "✓", else: "✗"
      Logger.info("  #{status} :usb.#{func_name}/#{arity}")
    end)
    
    Logger.info("\\nIf most functions show ✗, kernel driver detachment is not supported.")
    Logger.info("In that case, you'll need to use IOKit HID API for SpaceMouse access.")
  end
end
