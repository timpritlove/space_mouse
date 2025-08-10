defmodule SpaceNavigator.Demo do
  @moduledoc """
  Demo script to test USB device functionality.
  
  Run in iex with:
      iex> SpaceNavigator.Demo.test_usb_functionality()
  """

  require Logger

  @doc """
  Test basic USB functionality - list devices and show their information.
  """
  def test_usb_functionality do
    Logger.info("=== SpaceNavigator USB Demo ===")
    
    Logger.info("1. Testing device enumeration...")
    case SpaceNavigator.list_devices() do
      {:ok, devices} ->
        Logger.info("Found #{length(devices)} USB devices:")
        
        Enum.with_index(devices, 1)
        |> Enum.each(fn {device, index} ->
          Logger.info("  #{index}. VID: 0x#{Integer.to_string(device.vendor_id, 16) |> String.pad_leading(4, "0")}, " <>
                     "PID: 0x#{Integer.to_string(device.product_id, 16) |> String.pad_leading(4, "0")}, " <>
                     "Bus: #{device.bus_number}, Address: #{device.device_address}")
        end)
        
        Logger.info("2. Looking for 3Dconnexion devices (VID: 0x046d)...")
        test_find_3dconnexion_devices()
        
      {:error, reason} ->
        Logger.error("Failed to list devices: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Test finding specific 3Dconnexion devices.
  """
  def test_find_3dconnexion_devices do
    # 3Dconnexion vendor ID
    filter = %{vendor_id: 0x046d}
    
    case SpaceNavigator.find_devices(filter) do
      {:ok, []} ->
        Logger.info("   No 3Dconnexion devices found")
        :no_devices
      
      {:ok, devices} ->
        Logger.info("   Found #{length(devices)} 3Dconnexion device(s):")
        
        Enum.each(devices, fn device ->
          product_name = get_product_name(device.product_id)
          Logger.info("     - #{product_name} (PID: 0x#{Integer.to_string(device.product_id, 16)})")
        end)
        
        # Test connecting to the first device
        test_device_connection(List.first(devices))
        
      {:error, reason} ->
        Logger.error("   Error finding 3Dconnexion devices: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Test connecting to a specific device.
  """
  def test_device_connection(device) do
    Logger.info("3. Testing device connection...")
    
    case SpaceNavigator.open_device(device) do
      {:ok, opened_device} ->
        Logger.info("   Successfully opened device!")
        
        # Try to read some data (this might fail if device requires special setup)
        Logger.info("   Attempting to read data...")
        case SpaceNavigator.read_data(opened_device, 0x81, 8, 100) do
          {:ok, data} ->
            Logger.info("   Read data: #{inspect(data, base: :hex)}")
          
          {:error, reason} ->
            Logger.info("   No data read (this is normal): #{inspect(reason)}")
        end
        
        # Close the device
        case SpaceNavigator.close_device(opened_device) do
          {:ok, _} ->
            Logger.info("   Device closed successfully")
          
          {:error, reason} ->
            Logger.error("   Failed to close device: #{inspect(reason)}")
        end
        
      {:error, reason} ->
        Logger.info("   Could not open device: #{inspect(reason)}")
        Logger.info("   (This might be due to permissions or device being in use)")
    end
  end

  # Helper function to get friendly names for known 3Dconnexion products
  defp get_product_name(product_id) do
    case product_id do
      0xc626 -> "SpaceNavigator"
      0xc627 -> "SpaceExplorer"
      0xc628 -> "SpaceNavigator for Notebooks"
      0xc629 -> "SpacePilot"
      0xc62b -> "SpacePilot Pro"
      0xc640 -> "SpaceMousePro"
      _ -> "Unknown 3Dconnexion Device"
    end
  end

  @doc """
  Quick test to just list devices without trying to connect.
  """
  def quick_test do
    case SpaceNavigator.list_devices() do
      {:ok, devices} ->
        IO.puts("Found #{length(devices)} USB devices")
        {:ok, length(devices)}
      
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
        {:error, reason}
    end
  end
end


