defmodule SpaceNavigator.UsbManager do
  @moduledoc """
  USB device manager for discovering and communicating with USB devices.
  
  This module provides functionality to:
  - Enumerate USB devices
  - Filter devices by vendor ID, product ID, or other criteria
  - Open and close device connections
  - Read from and write to USB devices
  """

  use GenServer
  require Logger

  @type device_filter :: %{
    vendor_id: integer() | nil,
    product_id: integer() | nil,
    class: integer() | nil,
    subclass: integer() | nil
  }

  @type usb_device :: %{
    vendor_id: integer(),
    product_id: integer(),
    device_address: integer(),
    bus_number: integer(),
    device_descriptor: map(),
    handle: reference() | nil
  }

  # Client API

  @doc """
  Starts the USB manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Lists all USB devices currently connected to the system.
  """
  def list_devices do
    GenServer.call(__MODULE__, :list_devices)
  end

  @doc """
  Finds USB devices matching the given filter criteria.
  
  ## Examples
  
      # Find devices by vendor and product ID
      SpaceNavigator.UsbManager.find_devices(%{vendor_id: 0x046d, product_id: 0xc626})
      
      # Find all devices from a specific vendor
      SpaceNavigator.UsbManager.find_devices(%{vendor_id: 0x046d})
  """
  def find_devices(filter \\ %{}) do
    GenServer.call(__MODULE__, {:find_devices, filter})
  end

  @doc """
  Opens a connection to a USB device.
  """
  def open_device(device) do
    GenServer.call(__MODULE__, {:open_device, device})
  end

  @doc """
  Closes a connection to a USB device.
  """
  def close_device(device) do
    GenServer.call(__MODULE__, {:close_device, device})
  end

  @doc """
  Reads data from a USB device endpoint.
  """
  def read_data(device, endpoint, length, timeout \\ 1000) do
    GenServer.call(__MODULE__, {:read_data, device, endpoint, length, timeout})
  end

  @doc """
  Writes data to a USB device endpoint.
  """
  def write_data(device, endpoint, data, timeout \\ 1000) do
    GenServer.call(__MODULE__, {:write_data, device, endpoint, data, timeout})
  end

  # Server implementation

  @impl true
  def init(_opts) do
    # The usb module doesn't require explicit initialization
    Logger.info("USB Manager initialized successfully")
    {:ok, %{devices: [], context: nil}}
  end

  @impl true
  def handle_call(:list_devices, _from, state) do
    case enumerate_devices() do
      {:ok, devices} ->
        {:reply, {:ok, devices}, %{state | devices: devices}}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:find_devices, filter}, _from, state) do
    case enumerate_devices() do
      {:ok, devices} ->
        filtered_devices = filter_devices(devices, filter)
        {:reply, {:ok, filtered_devices}, %{state | devices: devices}}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:open_device, device}, _from, state) do
    case :usb.open_device(device.device) do
      {:ok, handle} ->
        updated_device = %{device | handle: handle}
        {:reply, {:ok, updated_device}, state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:close_device, device}, _from, state) do
    case device.handle do
      nil ->
        {:reply, {:error, :device_not_open}, state}
      
      handle ->
        case :usb.close_device(handle) do
          :ok ->
            updated_device = %{device | handle: nil}
            {:reply, {:ok, updated_device}, state}
          
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:read_data, device, endpoint, length, timeout}, _from, state) do
    case device.handle do
      nil ->
        {:reply, {:error, :device_not_open}, state}
      
      handle ->
        case :usb.read_interrupt(handle, endpoint, length, timeout) do
          {:ok, data} ->
            {:reply, {:ok, data}, state}
          
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:write_data, device, endpoint, data, timeout}, _from, state) do
    case device.handle do
      nil ->
        {:reply, {:error, :device_not_open}, state}
      
      handle ->
        case :usb.write_interrupt(handle, endpoint, data, timeout) do
          {:ok, bytes_written} ->
            {:reply, {:ok, bytes_written}, state}
          
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def terminate(_reason, _state) do
    # No explicit cleanup needed for usb module
    :ok
  end

  # Private functions

  defp enumerate_devices do
    case :usb.get_device_list() do
      {:ok, device_list} ->
        devices = Enum.map(device_list, &parse_device/1)
        {:ok, devices}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_device(device) do
    case :usb.get_device_descriptor(device) do
      {:ok, descriptor} ->
        %{
          vendor_id: Map.get(descriptor, :vendor_id, 0),
          product_id: Map.get(descriptor, :product_id, 0),
          device_address: extract_device_address(device),
          bus_number: extract_bus_number(device),
          device_descriptor: descriptor,
          device: device,
          handle: nil
        }
      
      {:error, _reason} ->
        %{
          vendor_id: 0,
          product_id: 0,
          device_address: 0,
          bus_number: 0,
          device_descriptor: %{},
          device: device,
          handle: nil
        }
    end
  end

  defp filter_devices(devices, filter) do
    Enum.filter(devices, fn device ->
      matches_filter?(device, filter)
    end)
  end

  defp matches_filter?(device, filter) do
    Enum.all?(filter, fn {key, value} ->
      case {key, value} do
        {_, nil} -> true
        {:vendor_id, vendor_id} -> device.vendor_id == vendor_id
        {:product_id, product_id} -> device.product_id == product_id
        {:class, class} -> Map.get(device.device_descriptor, :device_class) == class
        {:subclass, subclass} -> Map.get(device.device_descriptor, :device_subclass) == subclass
        _ -> true
      end
    end)
  end

  # Helper functions to safely extract device info
  defp extract_bus_number(device) do
    case :usb.get_bus_number(device) do
      {:ok, num} -> num
      num when is_integer(num) -> num
      _ -> 0
    end
  end

  defp extract_device_address(device) do
    case :usb.get_device_address(device) do
      {:ok, addr} -> addr
      addr when is_integer(addr) -> addr
      _ -> 0
    end
  end
end
