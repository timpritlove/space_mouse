defmodule SpaceNavigator.SpacemouseReader do
  @moduledoc """
  Real-time data reader for SpaceMouse devices.
  
  This module handles:
  - Continuous reading of HID reports from SpaceMouse
  - Parsing 6DOF motion data (X, Y, Z translation + rotation)
  - Button press/release events
  - Real-time data streaming to subscribers
  """

  use GenServer
  alias SpaceNavigator.UsbManager
  require Logger
  import Bitwise

  @spacemouse_vendor_id 0x256F

  # SpaceMouse HID report structure (typical for 3Dconnexion devices)
  # Motion reports are usually 7 bytes:
  # [report_id, x_low, x_high, y_low, y_high, z_low, z_high]
  # Button reports vary by device model

  @motion_report_size 7
  @read_timeout 100  # 100ms timeout for non-blocking reads

  defmodule State do
    defstruct [
      :device,
      :connected_device,
      :motion_endpoint,
      :button_endpoint,
      :subscribers,
      :reading,
      :last_motion,
      :last_buttons
    ]
  end

  # Client API

  @doc """
  Start the SpaceMouse reader for a specific device.
  """
  def start_link(device, opts \\ []) do
    GenServer.start_link(__MODULE__, device, opts)
  end

  @doc """
  Start reading data from the SpaceMouse.
  """
  def start_reading(pid) do
    GenServer.call(pid, :start_reading)
  end

  @doc """
  Stop reading data from the SpaceMouse.
  """
  def stop_reading(pid) do
    GenServer.call(pid, :stop_reading)
  end

  @doc """
  Subscribe to SpaceMouse data updates.
  """
  def subscribe(pid, subscriber_pid \\ self()) do
    GenServer.call(pid, {:subscribe, subscriber_pid})
  end

  @doc """
  Unsubscribe from SpaceMouse data updates.
  """
  def unsubscribe(pid, subscriber_pid \\ self()) do
    GenServer.call(pid, {:unsubscribe, subscriber_pid})
  end

  @doc """
  Get the current motion state.
  """
  def get_motion_state(pid) do
    GenServer.call(pid, :get_motion_state)
  end

  # Server implementation

  @impl true
  def init(device) do
    state = %State{
      device: device,
      connected_device: nil,
      motion_endpoint: 0x81,     # Typical HID input endpoint
      button_endpoint: 0x81,     # Usually same as motion
      subscribers: MapSet.new(),
      reading: false,
      last_motion: %{x: 0, y: 0, z: 0, rx: 0, ry: 0, rz: 0},
      last_buttons: 0
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call(:start_reading, _from, state) do
    if state.reading do
      {:reply, {:ok, :already_reading}, state}
    else
      case connect_and_start_reading(state) do
        {:ok, new_state} ->
          {:reply, {:ok, :started}, new_state}
        
        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call(:stop_reading, _from, state) do
    new_state = %{state | reading: false}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:subscribe, subscriber_pid}, _from, state) do
    new_subscribers = MapSet.put(state.subscribers, subscriber_pid)
    new_state = %{state | subscribers: new_subscribers}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:unsubscribe, subscriber_pid}, _from, state) do
    new_subscribers = MapSet.delete(state.subscribers, subscriber_pid)
    new_state = %{state | subscribers: new_subscribers}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_motion_state, _from, state) do
    motion_data = %{
      motion: state.last_motion,
      buttons: state.last_buttons,
      reading: state.reading,
      device_connected: state.connected_device != nil
    }
    {:reply, {:ok, motion_data}, state}
  end

  @impl true
  def handle_info(:read_data, state) do
    if state.reading and state.connected_device do
      # Schedule next read
      Process.send_after(self(), :read_data, 5)  # Read every 5ms for high frequency
      
      # Try to read motion data
      case read_motion_data(state) do
        {:ok, new_state} ->
          {:noreply, new_state}
        
        {:error, reason} ->
          Logger.warning("Failed to read motion data: #{inspect(reason)}")
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  # Private functions

  defp connect_and_start_reading(state) do
    # First, open the device
    case UsbManager.open_device(state.device) do
      {:ok, connected_device} ->
        Logger.info("SpaceMouse connected successfully")
        
        # Try to claim the HID interface (usually interface 0)
        :ok = claim_interface(connected_device, 0)
        
        new_state = %{state | 
          connected_device: connected_device, 
          reading: true
        }
        
        # Start the reading loop
        Process.send_after(self(), :read_data, 10)
        
        {:ok, new_state}
        
      {:error, reason} ->
        Logger.error("Failed to open SpaceMouse device: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp claim_interface(device, interface_number) do
    case :usb.claim_interface(device.handle, interface_number) do
      :ok ->
        Logger.info("Successfully claimed interface #{interface_number}")
        :ok
        
      {:error, reason} ->
        Logger.warning("Failed to claim interface #{interface_number}: #{inspect(reason)}")
        # For some devices, claiming interface might not be necessary
        :ok  # Continue anyway
    end
  end

  defp read_motion_data(state) do
    # Try to read from motion endpoint
    case UsbManager.read_data(
      state.connected_device, 
      state.motion_endpoint, 
      @motion_report_size, 
      @read_timeout
    ) do
      {:ok, data} ->
        # Parse the motion data
        case parse_motion_report(data) do
          {:ok, motion_data} ->
            # Check if motion data has changed
            if motion_changed?(motion_data, state.last_motion) do
              # Notify subscribers
              notify_subscribers(state.subscribers, {:motion, motion_data})
              
              new_state = %{state | last_motion: motion_data}
              {:ok, new_state}
            else
              {:ok, state}
            end
            
          {:error, reason} ->
            Logger.debug("Failed to parse motion data: #{inspect(reason)}")
            {:error, reason}
        end
        
      {:error, :timeout} ->
        # Timeout is normal for HID devices when no motion
        {:ok, state}
        
      {:error, reason} ->
        Logger.debug("Failed to read motion data: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_motion_report(data) when byte_size(data) >= 7 do
    # SpaceMouse motion reports are typically 7 bytes:
    # [report_id, x_low, x_high, y_low, y_high, z_low, z_high]
    <<report_id, x_low, x_high, y_low, y_high, z_low, z_high, _rest::binary>> = data
    
    # Convert from signed 16-bit little-endian values
    x = signed_16bit(x_low, x_high)
    y = signed_16bit(y_low, y_high)
    z = signed_16bit(z_low, z_high)
    
    motion_data = %{
      report_id: report_id,
      x: x,      # Translation X
      y: y,      # Translation Y  
      z: z,      # Translation Z
      rx: 0,     # Rotation X (may be in additional reports)
      ry: 0,     # Rotation Y
      rz: 0,     # Rotation Z
      timestamp: System.monotonic_time(:millisecond)
    }
    
    {:ok, motion_data}
  end

  defp parse_motion_report(data) do
    Logger.warning("Unexpected motion report size: #{byte_size(data)} bytes, data: #{inspect(data)}")
    {:error, :invalid_report_size}
  end

  defp signed_16bit(low, high) do
    # Combine low and high bytes into 16-bit signed integer
    unsigned = (high <<< 8) ||| low
    
    # Convert to signed
    if unsigned > 32767 do
      unsigned - 65536
    else
      unsigned
    end
  end

  defp motion_changed?(new_motion, last_motion) do
    # Check if any motion axis has changed significantly
    threshold = 5  # Ignore very small movements (noise)
    
    abs(new_motion.x - last_motion.x) > threshold or
    abs(new_motion.y - last_motion.y) > threshold or
    abs(new_motion.z - last_motion.z) > threshold or
    abs(new_motion.rx - last_motion.rx) > threshold or
    abs(new_motion.ry - last_motion.ry) > threshold or
    abs(new_motion.rz - last_motion.rz) > threshold
  end

  defp notify_subscribers(subscribers, message) do
    Enum.each(subscribers, fn subscriber_pid ->
      send(subscriber_pid, {:spacemouse_data, message})
    end)
  end

  @doc """
  Convenience function to start a SpaceMouse reader for the first found device.
  """
  def start_for_first_device(opts \\ []) do
    case UsbManager.find_devices(%{vendor_id: @spacemouse_vendor_id}) do
      {:ok, [device | _]} ->
        start_link(device, opts)
        
      {:ok, []} ->
        {:error, :no_spacemouse_found}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
end
