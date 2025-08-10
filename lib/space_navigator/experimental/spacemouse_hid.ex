defmodule SpaceNavigator.SpacemouseHid do
  @moduledoc """
  Correct SpaceMouse HID implementation based on parsed descriptor.
  
  Key findings from HID descriptor analysis:
  - Report ID 1: Translation data (X, Y, Z) - 52 bytes total
  - Report ID 2: Rotation data (Rx, Ry, Rz) - 52 bytes total  
  - Report ID 3: Button data
  - Multiple vendor-specific reports (IDs 4-26)
  
  Communication method: HID GET_REPORT control transfers, NOT endpoints
  """

  use GenServer
  require Logger
  import Bitwise

  defmodule State do
    defstruct [
      :device,
      :connected_device,
      :reading,
      :subscribers,
      :last_motion,
      :poll_interval,
      :translation_data,
      :rotation_data
    ]
  end

  # Client API

  def start_link(device, opts \\ []) do
    GenServer.start_link(__MODULE__, device, opts)
  end

  def start_reading(pid) do
    GenServer.call(pid, :start_reading)
  end

  def stop_reading(pid) do
    GenServer.call(pid, :stop_reading)
  end

  def subscribe(pid, subscriber_pid \\ self()) do
    GenServer.call(pid, {:subscribe, subscriber_pid})
  end

  def get_motion_state(pid) do
    GenServer.call(pid, :get_motion_state)
  end

  # Server implementation

  @impl true
  def init(device) do
    state = %State{
      device: device,
      connected_device: nil,
      reading: false,
      subscribers: MapSet.new(),
      last_motion: %{x: 0, y: 0, z: 0, rx: 0, ry: 0, rz: 0},
      poll_interval: 20,  # Poll every 20ms (50 Hz)
      translation_data: %{x: 0, y: 0, z: 0},
      rotation_data: %{rx: 0, ry: 0, rz: 0}
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call(:start_reading, _from, state) do
    if state.reading do
      {:reply, {:ok, :already_reading}, state}
    else
      case connect_device(state) do
        {:ok, new_state} ->
          # Start the HID polling loop
          Process.send_after(self(), :poll_hid_reports, 100)  # Small delay before first poll
          reading_state = %{new_state | reading: true}
          {:reply, {:ok, :started}, reading_state}
          
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
  def handle_call(:get_motion_state, _from, state) do
    motion_state = Map.merge(state.translation_data, state.rotation_data)
    {:reply, {:ok, motion_state}, state}
  end

  @impl true
  def handle_info(:poll_hid_reports, state) do
    if state.reading and state.connected_device do
      # Schedule next poll
      Process.send_after(self(), :poll_hid_reports, state.poll_interval)
      
      # Read translation and rotation reports
      new_state = state
      |> poll_translation_report()
      |> poll_rotation_report()
      |> check_and_notify_motion_changes()
      
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  # Private functions

  defp connect_device(state) do
    case SpaceNavigator.UsbManager.open_device(state.device) do
      {:ok, connected_device} ->
        Logger.info("SpaceMouse HID device connected successfully")
        
        # Set configuration 1 (as we found this works)
        case :usb.set_configuration(connected_device.handle, 1) do
          :ok ->
            Logger.info("Configuration 1 set successfully")
          {:error, reason} ->
            Logger.warning("Could not set configuration: #{inspect(reason)}")
        end
        
        new_state = %{state | connected_device: connected_device}
        {:ok, new_state}
        
      {:error, reason} ->
        Logger.error("Failed to connect SpaceMouse HID device: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp poll_translation_report(state) do
    # Report ID 1: Translation data (X, Y, Z)
    case get_hid_report(state.connected_device, 1) do
      {:ok, report_data} ->
        case parse_translation_report(report_data) do
          {:ok, translation} ->
            %{state | translation_data: translation}
          
          {:error, _reason} ->
            state
        end
        
      {:error, _reason} ->
        # No data available or timeout - normal
        state
    end
  end

  defp poll_rotation_report(state) do
    # Report ID 2: Rotation data (Rx, Ry, Rz)
    case get_hid_report(state.connected_device, 2) do
      {:ok, report_data} ->
        case parse_rotation_report(report_data) do
          {:ok, rotation} ->
            %{state | rotation_data: rotation}
          
          {:error, _reason} ->
            state
        end
        
      {:error, _reason} ->
        # No data available or timeout - normal
        state
    end
  end

  defp get_hid_report(device, report_id) do
    # HID GET_REPORT control transfer
    # bmRequestType = 0x81 (Device to Host, Class, Interface)
    # bRequest = 0x01 (GET_REPORT)
    # wValue = (Input Report Type << 8) | Report ID = (1 << 8) | report_id
    # wIndex = 0 (Interface 0)
    # wLength = 64 (Max report size, we know it's 52 bytes)
    
    wValue = (0x01 <<< 8) ||| report_id
    
    case :usb.read_control(
      device.handle,
      0x81,    # bmRequestType
      0x01,    # bRequest: GET_REPORT
      wValue,  # wValue: Report Type + Report ID
      0,       # wIndex: Interface 0
      64,      # wLength: Max report size
      10       # timeout: Short timeout for polling
    ) do
      {:ok, data} when byte_size(data) > 1 ->
        {:ok, data}
        
      {:ok, _small_data} ->
        {:error, :no_data}
        
      {:error, :timeout} ->
        {:error, :timeout}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_translation_report(data) when byte_size(data) >= 7 do
    # Based on HID descriptor analysis:
    # Report ID 1 contains X, Y, Z translation data
    # Each axis is 16 bits (2 bytes), 3 axes = 6 bytes + 1 byte report ID = 7 bytes minimum
    # Range: 65186 to 350 (signed 16-bit values)
    
    case data do
      <<report_id, x_low, x_high, y_low, y_high, z_low, z_high, _rest::binary>> when report_id == 1 ->
        x = signed_16bit_le(x_low, x_high)
        y = signed_16bit_le(y_low, y_high)
        z = signed_16bit_le(z_low, z_high)
        
        # Scale the values if needed (the range 65186-350 suggests 16-bit signed)
        translation = %{
          x: x,
          y: y,
          z: z,
          timestamp: System.monotonic_time(:millisecond)
        }
        
        {:ok, translation}
        
      _ ->
        {:error, :invalid_format}
    end
  end

  defp parse_translation_report(_data) do
    {:error, :insufficient_data}
  end

  defp parse_rotation_report(data) when byte_size(data) >= 7 do
    # Report ID 2 contains Rx, Ry, Rz rotation data
    # Same format as translation
    
    case data do
      <<report_id, rx_low, rx_high, ry_low, ry_high, rz_low, rz_high, _rest::binary>> when report_id == 2 ->
        rx = signed_16bit_le(rx_low, rx_high)
        ry = signed_16bit_le(ry_low, ry_high)
        rz = signed_16bit_le(rz_low, rz_high)
        
        rotation = %{
          rx: rx,
          ry: ry,
          rz: rz,
          timestamp: System.monotonic_time(:millisecond)
        }
        
        {:ok, rotation}
        
      _ ->
        {:error, :invalid_format}
    end
  end

  defp parse_rotation_report(_data) do
    {:error, :insufficient_data}
  end

  defp signed_16bit_le(low, high) do
    # Little-endian signed 16-bit integer
    unsigned = (high <<< 8) ||| low
    
    # Convert to signed (two's complement)
    if unsigned > 32767 do
      unsigned - 65536
    else
      unsigned
    end
  end

  defp check_and_notify_motion_changes(state) do
    # Combine translation and rotation data
    current_motion = Map.merge(state.translation_data, state.rotation_data)
    
    # Check if motion has changed significantly
    if motion_changed?(current_motion, state.last_motion) do
      # Notify subscribers
      notify_subscribers(state.subscribers, {:motion, current_motion})
      
      %{state | last_motion: current_motion}
    else
      state
    end
  end

  defp motion_changed?(new_motion, last_motion) do
    threshold = 5  # Minimum change to register as motion
    
    abs((new_motion.x || 0) - (last_motion.x || 0)) > threshold or
    abs((new_motion.y || 0) - (last_motion.y || 0)) > threshold or
    abs((new_motion.z || 0) - (last_motion.z || 0)) > threshold or
    abs((new_motion.rx || 0) - (last_motion.rx || 0)) > threshold or
    abs((new_motion.ry || 0) - (last_motion.ry || 0)) > threshold or
    abs((new_motion.rz || 0) - (last_motion.rz || 0)) > threshold
  end

  defp notify_subscribers(subscribers, message) do
    Enum.each(subscribers, fn subscriber_pid ->
      send(subscriber_pid, {:spacemouse_motion, message})
    end)
  end

  @doc """
  Start HID SpaceMouse reader for the first found device.
  """
  def start_for_first_device(opts \\ []) do
    case SpaceNavigator.UsbManager.find_devices(%{vendor_id: 0x256F}) do
      {:ok, [device | _]} ->
        start_link(device, opts)
        
      {:ok, []} ->
        {:error, :no_spacemouse_found}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Test reading specific HID reports manually.
  """
  def test_report_reading(report_id \\ 1) do
    Logger.info("=== Testing HID Report #{report_id} Reading ===")
    
    case SpaceNavigator.UsbManager.find_devices(%{vendor_id: 0x256F}) do
      {:ok, [device | _]} ->
        case SpaceNavigator.UsbManager.open_device(device) do
          {:ok, connected_device} ->
            Logger.info("✓ Device connected")
            
            # Set configuration
            :usb.set_configuration(connected_device.handle, 1)
            
            # Try to read the report multiple times
            Logger.info("Reading report #{report_id} (move your SpaceMouse)...")
            
            Enum.each(1..20, fn attempt ->
              case get_hid_report(connected_device, report_id) do
                {:ok, data} ->
                  hex_data = data 
                  |> :binary.bin_to_list() 
                  |> Enum.take(16)  # Show first 16 bytes
                  |> Enum.map(&Integer.to_string(&1, 16))
                  |> Enum.map(&String.pad_leading(&1, 2, "0"))
                  |> Enum.join(" ")
                  
                  Logger.info("  #{attempt}: #{byte_size(data)} bytes - #{hex_data}")
                  
                  if report_id == 1 do
                    case parse_translation_report(data) do
                      {:ok, translation} ->
                        Logger.info("    → X=#{translation.x}, Y=#{translation.y}, Z=#{translation.z}")
                      {:error, reason} ->
                        Logger.info("    → Parse error: #{inspect(reason)}")
                    end
                  end
                  
                {:error, :timeout} ->
                  Logger.debug("  #{attempt}: Timeout (normal)")
                  
                {:error, reason} ->
                  Logger.info("  #{attempt}: Error - #{inspect(reason)}")
              end
              
              Process.sleep(100)  # 100ms between attempts
            end)
            
          {:error, reason} ->
            Logger.error("Could not connect: #{inspect(reason)}")
        end
        
      error ->
        Logger.error("Could not find device: #{inspect(error)}")
    end
  end
end
