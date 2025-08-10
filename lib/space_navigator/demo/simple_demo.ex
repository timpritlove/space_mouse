defmodule SpaceNavigator.SimpleDemo do
  @moduledoc """
  Simple demo to test basic USB device discovery functionality.
  
  This module focuses on the core functionality that we know works:
  - Listing USB devices
  - Getting device descriptors
  - Basic device information
  """

  require Logger

  @doc """
  Simple test to list all USB devices using the usb module directly.
  """
  def list_usb_devices do
    Logger.info("=== Simple USB Device Discovery ===")
    
    case :usb.get_device_list() do
      {:ok, devices} ->
        Logger.info("Found #{length(devices)} USB devices:")
        
        devices
        |> Enum.with_index(1)
        |> Enum.each(fn {device, index} ->
          case :usb.get_device_descriptor(device) do
            {:ok, descriptor} ->
              vendor_id = Map.get(descriptor, :vendor_id, 0)
              product_id = Map.get(descriptor, :product_id, 0)
              device_class = Map.get(descriptor, :class_code, 0)
              
              Logger.info("  #{index}. VID: 0x#{Integer.to_string(vendor_id, 16) |> String.pad_leading(4, "0")}, " <>
                         "PID: 0x#{Integer.to_string(product_id, 16) |> String.pad_leading(4, "0")}, " <>
                         "Class: #{device_class}")
              
              # Check if it's a 3Dconnexion device (vendor ID 0x256F)
              if vendor_id == 0x256F do
                product_name = get_3dconnexion_product_name(product_id)
                Logger.info("     -> 3Dconnexion Device: #{product_name}")
              end
            
            {:error, reason} ->
              Logger.error("  #{index}. Failed to get descriptor: #{inspect(reason)}")
          end
        end)
        
        {:ok, length(devices)}
      
      {:error, reason} ->
        Logger.error("Failed to get device list: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Test opening a specific device to see what functions are available.
  """
  def test_device_opening do
    Logger.info("=== Testing Device Opening ===")
    
    case :usb.get_device_list() do
      {:ok, devices} ->
        # Try to find any device to test opening
        case List.first(devices) do
          nil ->
            Logger.info("No devices found to test")
            {:error, :no_devices}
          
          device ->
            Logger.info("Testing device opening...")
            
            case :usb.open_device(device) do
              {:ok, handle} ->
                Logger.info("Successfully opened device!")
                
                # Try to close it
                case :usb.close_device(handle) do
                  :ok ->
                    Logger.info("Successfully closed device")
                    :ok
                  
                  {:error, reason} ->
                    Logger.error("Failed to close device: #{inspect(reason)}")
                    {:error, reason}
                end
              
              {:error, reason} ->
                Logger.info("Could not open device: #{inspect(reason)}")
                Logger.info("This might be due to permissions or the device being in use")
                {:error, reason}
            end
        end
      
      {:error, reason} ->
        Logger.error("Failed to get device list: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Find and display information about 3Dconnexion devices specifically.
  """
  def find_3dconnexion_devices do
    Logger.info("=== Looking for 3Dconnexion Devices ===")
    
    case :usb.get_device_list() do
      {:ok, devices} ->
        # Filter for 3Dconnexion devices (vendor ID 0x046d)
        devices_3dconnexion = 
          devices
          |> Enum.filter(fn device ->
            case :usb.get_device_descriptor(device) do
              {:ok, descriptor} ->
                Map.get(descriptor, :vendor_id) == 0x256F
              
              {:error, _} ->
                false
            end
          end)
        
        case devices_3dconnexion do
          [] ->
            Logger.info("No 3Dconnexion devices found")
            {:ok, []}
          
          found_devices ->
            Logger.info("Found #{length(found_devices)} 3Dconnexion device(s):")
            
            Enum.each(found_devices, fn device ->
              {:ok, descriptor} = :usb.get_device_descriptor(device)
              product_id = Map.get(descriptor, :idProduct)
              product_name = get_3dconnexion_product_name(product_id)
              
              Logger.info("  - #{product_name} (PID: 0x#{Integer.to_string(product_id, 16)})")
            end)
            
            {:ok, found_devices}
        end
      
      {:error, reason} ->
        Logger.error("Failed to get device list: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Check what functions are available in the usb module.
  """
  def inspect_usb_module do
    Logger.info("=== USB Module Functions ===")
    
    exports = :usb.module_info(:exports)
    
    Logger.info("Available functions in :usb module:")
    Enum.each(exports, fn {function_name, arity} ->
      Logger.info("  :usb.#{function_name}/#{arity}")
    end)
    
    {:ok, exports}
  end

  # Helper function to get friendly names for 3Dconnexion products
  defp get_3dconnexion_product_name(product_id) do
    case product_id do
      0xc626 -> "SpaceNavigator"
      0xc627 -> "SpaceExplorer"
      0xc628 -> "SpaceNavigator for Notebooks"
      0xc629 -> "SpacePilot"
      0xc62b -> "SpacePilot Pro"
      0xc640 -> "SpaceMousePro"
      0xc652 -> "SpaceMouse Wireless"
      _ -> "Unknown 3Dconnexion Device (0x#{Integer.to_string(product_id, 16)})"
    end
  end

  @doc """
  Run all tests in sequence.
  """
  def run_all_tests do
    Logger.info("Starting USB functionality tests...")
    
    inspect_usb_module()
    list_usb_devices()
    find_3dconnexion_devices()
    test_device_opening()
    
    Logger.info("Tests completed!")
  end
end
