defmodule SpaceNavigator do
  @moduledoc """
  SpaceNavigator - USB device communication library.
  
  This library provides functionality to discover, connect to, and communicate
  with USB devices using libusb. It's particularly designed for working with
  3D input devices like the SpaceNavigator, but can be used with any USB device.
  
  ## Basic Usage
  
      # List all USB devices
      {:ok, devices} = SpaceNavigator.list_devices()
      
      # Find specific devices
      {:ok, devices} = SpaceNavigator.find_devices(%{vendor_id: 0x046d, product_id: 0xc626})
      
      # Connect and read from a device
      {:ok, data} = SpaceNavigator.connect_and_read(0x046d, 0xc626)
  
  ## Advanced Usage
  
  For more advanced usage patterns, see `SpaceNavigator.UsbManager` and 
  `SpaceNavigator.DeviceExample`.
  """

  alias SpaceNavigator.UsbManager
  alias SpaceNavigator.DeviceExample

  @doc """
  Lists all USB devices currently connected to the system.
  """
  defdelegate list_devices(), to: UsbManager

  @doc """
  Finds USB devices matching the given filter criteria.
  
  ## Examples
  
      # Find devices by vendor and product ID
      SpaceNavigator.find_devices(%{vendor_id: 0x046d, product_id: 0xc626})
      
      # Find all devices from a specific vendor
      SpaceNavigator.find_devices(%{vendor_id: 0x046d})
  """
  defdelegate find_devices(filter \\ %{}), to: UsbManager

  @doc """
  Opens a connection to a USB device.
  """
  defdelegate open_device(device), to: UsbManager

  @doc """
  Closes a connection to a USB device.
  """
  defdelegate close_device(device), to: UsbManager

  @doc """
  Reads data from a USB device endpoint.
  """
  defdelegate read_data(device, endpoint, length, timeout \\ 1000), to: UsbManager

  @doc """
  Writes data to a USB device endpoint.
  """
  defdelegate write_data(device, endpoint, data, timeout \\ 1000), to: UsbManager

  @doc """
  Convenience function to find and connect to a device, then read data from it.
  
  This is useful for simple one-off reads from a device.
  """
  defdelegate connect_and_read_device(vendor_id, product_id), to: DeviceExample

  @doc """
  Convenience function to find and connect to a device, then send data to it.
  
  This is useful for simple one-off writes to a device.
  """
  defdelegate send_data_to_device(vendor_id, product_id, data), to: DeviceExample

  @doc """
  Starts monitoring a device for continuous input.
  
  The callback function will be called with each packet of data received.
  """
  defdelegate monitor_device(vendor_id, product_id, callback_fun), to: DeviceExample

  @doc """
  Finds a 3Dconnexion SpaceNavigator device.
  
  Returns the first SpaceNavigator device found, or an error if none are found.
  """
  defdelegate find_space_navigator(), to: DeviceExample
end
