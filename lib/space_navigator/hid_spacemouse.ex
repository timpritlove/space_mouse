defmodule SpaceNavigator.HidSpacemouse do
  @moduledoc """
  HID-specific SpaceMouse implementation using control transfers.
  
  Since the SpaceMouse is claimed by the system as an HID device,
  we need to use HID control requests to get reports instead of
  direct endpoint reads.
  """

  use GenServer
  require Logger
  import Bitwise

  # HID Class Requests
  @hid_get_report 0x01


  # Request types
  @request_type_in 0x81   # Device to Host, Class, Interface


  # Report types
  @report_type_input 0x01


  defmodule State do
    defstruct [
      :device,
      :connected_device,
      :reading,
      :subscribers,
      :last_motion,
      :poll_interval
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

  def get_report_descriptor(pid) do
    GenServer.call(pid, :get_report_descriptor)
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
      poll_interval: 10  # Poll every 10ms
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
          Process.send_after(self(), :poll_hid_reports, state.poll_interval)
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
    {:reply, {:ok, state.last_motion}, state}
  end

  @impl true
  def handle_call(:get_report_descriptor, _from, state) do
    if state.connected_device do
      case get_hid_report_descriptor(state.connected_device) do
        {:ok, descriptor} ->
          {:reply, {:ok, descriptor}, state}
        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl true
  def handle_info(:poll_hid_reports, state) do
    if state.reading and state.connected_device do
      # Schedule next poll
      Process.send_after(self(), :poll_hid_reports, state.poll_interval)
      
      # Try to get HID input report
      case get_input_report(state.connected_device) do
        {:ok, report_data} ->
          case parse_spacemouse_report(report_data) do
            {:ok, motion_data} ->
              if motion_changed?(motion_data, state.last_motion) do
                notify_subscribers(state.subscribers, {:motion, motion_data})
                new_state = %{state | last_motion: motion_data}
                {:noreply, new_state}
              else
                {:noreply, state}
              end
              
            {:error, _reason} ->
              {:noreply, state}
          end
          
        {:error, _reason} ->
          # Normal when no motion - continue polling
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  # Private functions

  defp connect_device(state) do
    case SpaceNavigator.UsbManager.open_device(state.device) do
      {:ok, connected_device} ->
        Logger.info("SpaceMouse HID device connected")
        
        # Set configuration
        case :usb.set_configuration(connected_device.handle, 1) do
          :ok ->
            Logger.info("Configuration set successfully")
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

  defp get_hid_report_descriptor(device) do
    # Get HID Report Descriptor
    # GET_DESCRIPTOR request with Report descriptor type (0x22)
    case :usb.read_control(
      device.handle,
      @request_type_in,  # bmRequestType: Device to Host, Standard, Interface
      0x06,              # bRequest: GET_DESCRIPTOR
      0x2200,            # wValue: Report Descriptor (0x22) + index 0
      0,                 # wIndex: Interface 0
      512,               # wLength: Max descriptor size
      5000               # timeout
    ) do
      {:ok, data} when byte_size(data) > 0 ->
        Logger.info("Got HID Report Descriptor: #{byte_size(data)} bytes")
        {:ok, data}
        
      {:ok, <<>>} ->
        {:error, :empty_descriptor}
        
      {:error, reason} ->
        Logger.warning("Could not get HID report descriptor: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_input_report(device) do
    # Try different report IDs (0-15 are common)
    report_ids = [0, 1, 2, 3, 4, 5]
    
    # Try each report ID
    result = Enum.reduce_while(report_ids, {:error, :no_reports}, fn report_id, _acc ->
      case get_hid_input_report(device, report_id) do
        {:ok, data} when byte_size(data) > 1 ->
          {:halt, {:ok, data}}
          
        _ ->
          {:cont, {:error, :no_reports}}
      end
    end)
    
    result
  end

  defp get_hid_input_report(device, report_id) do
    # HID GET_REPORT request for input report
    wValue = (@report_type_input <<< 8) ||| report_id
    
    case :usb.read_control(
      device.handle,
      @request_type_in,   # bmRequestType
      @hid_get_report,    # bRequest: GET_REPORT
      wValue,             # wValue: Report Type + Report ID
      0,                  # wIndex: Interface 0
      64,                 # wLength: Max report size
      50                  # timeout (short for polling)
    ) do
      {:ok, data} when byte_size(data) > 0 ->
        {:ok, data}
        
      {:error, :timeout} ->
        {:error, :timeout}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_spacemouse_report(data) when byte_size(data) >= 7 do
    # SpaceMouse reports typically start with report ID
    case data do
      # 6DOF motion report (typical format)
      <<report_id, x_low, x_high, y_low, y_high, z_low, z_high, _rest::binary>> ->
        x = signed_16bit(x_low, x_high)
        y = signed_16bit(y_low, y_high) 
        z = signed_16bit(z_low, z_high)
        
        motion_data = %{
          report_id: report_id,
          x: x,
          y: y,
          z: z,
          rx: 0,  # Rotation data might be in additional bytes or separate reports
          ry: 0,
          rz: 0,
          timestamp: System.monotonic_time(:millisecond),
          raw_data: data
        }
        
        {:ok, motion_data}
        
      # Button report (different format)
      <<report_id, buttons, _rest::binary>> when report_id != 1 ->
        # This might be a button report
        {:ok, %{report_id: report_id, buttons: buttons, type: :button}}
        
      _ ->
        {:error, :unknown_format}
    end
  end

  defp parse_spacemouse_report(data) do
    Logger.debug("Unknown report format: #{byte_size(data)} bytes - #{inspect(data)}")
    {:error, :invalid_size}
  end

  defp signed_16bit(low, high) do
    import Bitwise
    unsigned = (high <<< 8) ||| low
    
    if unsigned > 32767 do
      unsigned - 65536
    else
      unsigned
    end
  end

  defp motion_changed?(new_motion, last_motion) do
    threshold = 3  # Small threshold for noise filtering
    
    abs(new_motion.x - last_motion.x) > threshold or
    abs(new_motion.y - last_motion.y) > threshold or
    abs(new_motion.z - last_motion.z) > threshold
  end

  defp notify_subscribers(subscribers, message) do
    Enum.each(subscribers, fn subscriber_pid ->
      send(subscriber_pid, {:spacemouse_hid, message})
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
  Analyze the HID report descriptor to understand the device structure.
  """
  def analyze_hid_descriptor(pid) do
    case get_report_descriptor(pid) do
      {:ok, descriptor} ->
        Logger.info("=== HID Report Descriptor Analysis ===")
        Logger.info("Descriptor size: #{byte_size(descriptor)} bytes")
        
        # Parse basic HID descriptor elements
        parse_hid_descriptor(descriptor)
        
      {:error, reason} ->
        Logger.error("Could not get HID descriptor: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_hid_descriptor(data) do
    Logger.info("Raw descriptor (first 50 bytes):")
    first_bytes = binary_part(data, 0, min(50, byte_size(data)))
    
    # Display as hex for analysis
    hex_string = first_bytes
    |> :binary.bin_to_list()
    |> Enum.map(&Integer.to_string(&1, 16))
    |> Enum.map(&String.pad_leading(&1, 2, "0"))
    |> Enum.join(" ")
    
    Logger.info("  #{hex_string}")
    
    # Look for common HID elements
    analyze_hid_elements(data)
  end

  defp analyze_hid_elements(data) do
    Logger.info("\\nAnalyzing HID descriptor elements...")
    
    # Look for usage page and usage ID
    if String.contains?(data, <<0x05, 0x01>>) do
      Logger.info("✓ Found Generic Desktop usage page")
    end
    
    if String.contains?(data, <<0x09, 0x08>>) do
      Logger.info("✓ Found Multi-axis Controller usage")
    end
    
    # Look for input/output reports
    input_count = count_occurrences(data, <<0x81>>)  # Input items
    output_count = count_occurrences(data, <<0x91>>) # Output items
    
    Logger.info("HID Report Structure:")
    Logger.info("  Input reports found: #{input_count}")
    Logger.info("  Output reports found: #{output_count}")
  end

  defp count_occurrences(binary, pattern) do
    binary
    |> :binary.matches(pattern)
    |> length()
  end
end
