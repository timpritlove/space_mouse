defmodule SpaceNavigator.SpacemouseDemo do
  @moduledoc """
  Demonstration module specifically for working with 3Dconnexion SpaceMouse devices.
  
  This module shows how to:
  - Detect SpaceMouse devices
  - Connect to them
  - Identify specific SpaceMouse models
  - Prepare for data reading (requires transfer function implementation)
  """

  alias SpaceNavigator.UsbManager
  require Logger

  @spacemouse_vendor_id 0x256F  # 3Dconnexion vendor ID
  
  # Known SpaceMouse product IDs
  @spacemouse_products %{
    0xC603 => "SpaceMouse Plus",
    0xC605 => "CADMan",
    0xC606 => "SpaceMouse Classic", 
    0xC621 => "SpaceBall 5000",
    0xC623 => "SpaceTraveler",
    0xC625 => "SpacePilot",
    0xC626 => "SpaceNavigator",
    0xC627 => "SpaceExplorer",
    0xC628 => "SpaceNavigator for Notebooks",
    0xC629 => "SpacePilot Pro",
    0xC62B => "SpaceMouse Pro",
    0xC631 => "SpaceMouse Wireless", 
    0xC632 => "SpaceMouse Wireless Receiver",
    0xC635 => "SpaceMouse Compact",  # Your device!
    0xC636 => "SpaceMouse Module",
    0xC640 => "nulooq",
    0xC652 => "SpaceMouse Pro Wireless",
    0xC657 => "SpaceMouse Pro Wireless Receiver"
  }

  @doc """
  Find all connected SpaceMouse devices.
  """
  def find_spacemouse_devices do
    Logger.info("=== SpaceMouse Device Discovery ===")
    
    case UsbManager.find_devices(%{vendor_id: @spacemouse_vendor_id}) do
      {:ok, devices} ->
        Logger.info("Found #{length(devices)} 3Dconnexion device(s)")
        
        spacemouse_devices = 
          devices
          |> Enum.map(fn device ->
            product_name = Map.get(@spacemouse_products, device.product_id, "Unknown SpaceMouse (0x#{Integer.to_string(device.product_id, 16)})")
            
            Logger.info("  Device: #{product_name}")
            Logger.info("    VID: 0x#{Integer.to_string(device.vendor_id, 16)}")
            Logger.info("    PID: 0x#{Integer.to_string(device.product_id, 16)}")
            Logger.info("    Bus: #{device.bus_number}")
            Logger.info("    Address: #{device.device_address}")
            Logger.info("    USB Version: #{device.device_descriptor.usb_version}")
            Logger.info("    Device Version: #{device.device_descriptor.device_version}")
            
            Map.put(device, :product_name, product_name)
          end)
        
        {:ok, spacemouse_devices}
        
      {:error, reason} ->
        Logger.error("Failed to find SpaceMouse devices: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Connect to the first available SpaceMouse device.
  """
  def connect_to_spacemouse do
    Logger.info("=== SpaceMouse Connection ===")
    
    case find_spacemouse_devices() do
      {:ok, [device | _]} ->
        Logger.info("Attempting to connect to #{device.product_name}...")
        
        case UsbManager.open_device(device) do
          {:ok, connected_device} ->
            Logger.info("✓ Successfully connected to SpaceMouse!")
            Logger.info("  Device handle: #{inspect(connected_device.handle)}")
            {:ok, connected_device}
            
          {:error, reason} ->
            Logger.error("✗ Failed to connect to SpaceMouse: #{inspect(reason)}")
            {:error, reason}
        end
        
      {:ok, []} ->
        Logger.warning("No SpaceMouse devices found")
        {:error, :no_devices}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get detailed information about your SpaceMouse Compact.
  """
  def get_spacemouse_info do
    Logger.info("=== SpaceMouse Compact Information ===")
    
    case find_spacemouse_devices() do
      {:ok, [device | _]} ->
        descriptor = device.device_descriptor
        
        product_name = Map.get(@spacemouse_products, device.product_id, "Unknown SpaceMouse (0x#{Integer.to_string(device.product_id, 16)})")
        Logger.info("Device: #{product_name}")
        Logger.info("Vendor: 3Dconnexion (0x#{Integer.to_string(device.vendor_id, 16)})")
        Logger.info("Product ID: 0x#{Integer.to_string(device.product_id, 16)}")
        Logger.info("USB Version: #{format_usb_version(descriptor.usb_version)}")
        Logger.info("Device Version: #{format_device_version(descriptor.device_version)}")
        Logger.info("Max Packet Size: #{descriptor.max_packet_size0} bytes")
        Logger.info("Number of Configurations: #{descriptor.num_configurations}")
        Logger.info("Device Class: #{descriptor.class_code}")
        Logger.info("Device Sub-Class: #{descriptor.sub_class_code}")
        Logger.info("Device Protocol: #{descriptor.protocol_code}")
        Logger.info("Manufacturer String Index: #{descriptor.manufacturer_string_index}")
        Logger.info("Product String Index: #{descriptor.product_string_index}")
        Logger.info("Serial Number String Index: #{descriptor.serial_number_string_index}")
        
        {:ok, device}
        
      {:ok, []} ->
        Logger.warning("No SpaceMouse devices found")
        {:error, :no_devices}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Demonstrate the complete workflow: find, connect, and get ready for data reading.
  """
  def demo_workflow do
    Logger.info("=== SpaceMouse Complete Demo Workflow ===")
    
    with {:ok, _devices} <- find_spacemouse_devices(),
         {:ok, connected_device} <- connect_to_spacemouse() do
      
      Logger.info("🎉 SpaceMouse is ready for use!")
      Logger.info("Next steps:")
      Logger.info("  1. Implement USB transfer functions for reading motion data")
      Logger.info("  2. Parse the HID reports to extract 6DOF motion (X,Y,Z translation + rotation)")
      Logger.info("  3. Handle button presses and device-specific features")
      
      # When we implement transfer functions, we would read from endpoints like:
      # UsbManager.read_data(connected_device, 0x81, 7, 1000)  # Read 7 bytes from endpoint 0x81
      
      {:ok, connected_device}
    else
      error ->
        Logger.error("Demo workflow failed: #{inspect(error)}")
        error
    end
  end

  # Helper functions

  defp format_usb_version(version) do
    major = div(version, 256)
    minor = rem(version, 256)
    "#{major}.#{minor}"
  end

  defp format_device_version(version) do
    major = div(version, 256)
    minor = rem(version, 256)
    "#{major}.#{minor}"
  end
end
