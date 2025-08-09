defmodule SpaceNavigator.DeviceExample do
  @moduledoc """
  Example module demonstrating how to use the USB functionality.
  
  This module shows common patterns for:
  - Finding USB devices
  - Opening connections
  - Reading and writing data
  - Handling device-specific protocols
  """

  alias SpaceNavigator.UsbManager
  require Logger

  @doc """
  Example: Find and list all USB devices.
  """
  def list_all_devices do
    case UsbManager.list_devices() do
      {:ok, devices} ->
        Logger.info("Found #{length(devices)} USB devices:")
        
        Enum.each(devices, fn device ->
          Logger.info("  Device: VID=0x#{Integer.to_string(device.vendor_id, 16)}, " <>
                     "PID=0x#{Integer.to_string(device.product_id, 16)}, " <>
                     "Bus=#{device.bus_number}, Address=#{device.device_address}")
        end)
        
        {:ok, devices}
      
      {:error, reason} ->
        Logger.error("Failed to list devices: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Example: Find a specific device by vendor and product ID.
  
  This example looks for a 3Dconnexion SpaceNavigator device.
  """
  def find_space_navigator do
    # 3Dconnexion vendor ID and SpaceNavigator product ID
    filter = %{vendor_id: 0x046d, product_id: 0xc626}
    
    case UsbManager.find_devices(filter) do
      {:ok, []} ->
        Logger.info("No SpaceNavigator devices found")
        {:error, :device_not_found}
      
      {:ok, devices} ->
        device = List.first(devices)
        Logger.info("Found SpaceNavigator: #{inspect(device)}")
        {:ok, device}
      
      {:error, reason} ->
        Logger.error("Error finding SpaceNavigator: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Example: Connect to a device and perform basic communication.
  """
  def connect_and_read_device(vendor_id, product_id) do
    filter = %{vendor_id: vendor_id, product_id: product_id}
    
    with {:ok, [device | _]} <- UsbManager.find_devices(filter),
         {:ok, opened_device} <- UsbManager.open_device(device) do
      
      Logger.info("Successfully connected to device")
      
      # Example: Read from endpoint 0x81 (typical input endpoint)
      case UsbManager.read_data(opened_device, 0x81, 64, 1000) do
        {:ok, data} ->
          Logger.info("Read data: #{inspect(data, base: :hex)}")
          
          # Clean up: close the device
          UsbManager.close_device(opened_device)
          {:ok, data}
        
        {:error, reason} ->
          Logger.error("Failed to read data: #{inspect(reason)}")
          UsbManager.close_device(opened_device)
          {:error, reason}
      end
    else
      {:ok, []} ->
        Logger.error("Device not found")
        {:error, :device_not_found}
      
      {:error, reason} ->
        Logger.error("Error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Example: Send data to a device.
  """
  def send_data_to_device(vendor_id, product_id, data) do
    filter = %{vendor_id: vendor_id, product_id: product_id}
    
    with {:ok, [device | _]} <- UsbManager.find_devices(filter),
         {:ok, opened_device} <- UsbManager.open_device(device) do
      
      Logger.info("Sending data to device: #{inspect(data, base: :hex)}")
      
      # Example: Write to endpoint 0x01 (typical output endpoint)
      case UsbManager.write_data(opened_device, 0x01, data, 1000) do
        :ok ->
          Logger.info("Data sent successfully")
          UsbManager.close_device(opened_device)
          :ok
        
        {:error, reason} ->
          Logger.error("Failed to send data: #{inspect(reason)}")
          UsbManager.close_device(opened_device)
          {:error, reason}
      end
    else
      {:ok, []} ->
        Logger.error("Device not found")
        {:error, :device_not_found}
      
      {:error, reason} ->
        Logger.error("Error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Example: Monitor a device for continuous input (like a SpaceNavigator).
  
  This function demonstrates how to set up a continuous reading loop.
  """
  def monitor_device(vendor_id, product_id, callback_fun) do
    filter = %{vendor_id: vendor_id, product_id: product_id}
    
    with {:ok, [device | _]} <- UsbManager.find_devices(filter),
         {:ok, opened_device} <- UsbManager.open_device(device) do
      
      Logger.info("Starting device monitoring...")
      monitor_loop(opened_device, callback_fun)
    else
      {:ok, []} ->
        Logger.error("Device not found")
        {:error, :device_not_found}
      
      {:error, reason} ->
        Logger.error("Error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private function for the monitoring loop
  defp monitor_loop(device, callback_fun) do
    case UsbManager.read_data(device, 0x81, 64, 100) do
      {:ok, data} when byte_size(data) > 0 ->
        # Call the provided callback function with the received data
        callback_fun.(data)
        monitor_loop(device, callback_fun)
      
      {:ok, _empty_data} ->
        # No data received, continue monitoring
        monitor_loop(device, callback_fun)
      
      {:error, :timeout} ->
        # Timeout is expected, continue monitoring
        monitor_loop(device, callback_fun)
      
      {:error, reason} ->
        Logger.error("Monitoring stopped due to error: #{inspect(reason)}")
        UsbManager.close_device(device)
        {:error, reason}
    end
  end

  @doc """
  Example callback function for processing SpaceNavigator data.
  """
  def space_navigator_callback(data) do
    case parse_space_navigator_data(data) do
      {:ok, %{x: x, y: y, z: z, rx: rx, ry: ry, rz: rz}} ->
        Logger.info("SpaceNavigator input - Translation: (#{x}, #{y}, #{z}), Rotation: (#{rx}, #{ry}, #{rz})")
      
      {:error, reason} ->
        Logger.debug("Failed to parse data: #{inspect(reason)}")
    end
  end

  # Example parser for SpaceNavigator data format
  defp parse_space_navigator_data(<<1, x::signed-little-16, y::signed-little-16, z::signed-little-16, _rest::binary>>) do
    {:ok, %{x: x, y: y, z: z, rx: 0, ry: 0, rz: 0}}
  end

  defp parse_space_navigator_data(<<2, rx::signed-little-16, ry::signed-little-16, rz::signed-little-16, _rest::binary>>) do
    {:ok, %{x: 0, y: 0, z: 0, rx: rx, ry: ry, rz: rz}}
  end

  defp parse_space_navigator_data(_data) do
    {:error, :unknown_format}
  end
end
