defmodule SpaceNavigator.HidMonitor do
  @moduledoc """
  Monitor SpaceMouse HID events using macOS system tools and port communication.
  
  This approach uses the fact that your SpaceMouse is visible in the HID Event System
  and can be monitored without requiring direct IOKit access from the Erlang VM.
  """

  use GenServer
  require Logger

  defmodule State do
    defstruct [
      :port,
      :subscribers,
      :last_motion,
      :spacemouse_found,
      :monitor_active
    ]
  end

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_monitoring do
    GenServer.call(__MODULE__, :start_monitoring)
  end

  def stop_monitoring do
    GenServer.call(__MODULE__, :stop_monitoring)
  end

  def subscribe(pid \\ self()) do
    GenServer.call(__MODULE__, {:subscribe, pid})
  end

  def get_last_motion do
    GenServer.call(__MODULE__, :get_last_motion)
  end

  # Server implementation

  @impl true
  def init(_opts) do
    state = %State{
      port: nil,
      subscribers: MapSet.new(),
      last_motion: %{x: 0, y: 0, z: 0, rx: 0, ry: 0, rz: 0},
      spacemouse_found: false,
      monitor_active: false
    }
    
    # Check if SpaceMouse is available
    case check_spacemouse_availability() do
      {:ok, :found} ->
        Logger.info("✓ SpaceMouse detected in HID system")
        {:ok, %{state | spacemouse_found: true}}
        
      {:error, reason} ->
        Logger.warning("SpaceMouse not found: #{inspect(reason)}")
        {:ok, state}
    end
  end

  @impl true
  def handle_call(:start_monitoring, _from, state) do
    if state.spacemouse_found and not state.monitor_active do
      case start_hid_monitor(state) do
        {:ok, new_state} ->
          {:reply, {:ok, :started}, new_state}
          
        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      reason = cond do
        not state.spacemouse_found -> :spacemouse_not_found
        state.monitor_active -> :already_monitoring
        true -> :unknown_error
      end
      {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:stop_monitoring, _from, state) do
    case state.port do
      nil ->
        {:reply, :ok, state}
        
      port ->
        Port.close(port)
        new_state = %{state | port: nil, monitor_active: false}
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    new_subscribers = MapSet.put(state.subscribers, pid)
    new_state = %{state | subscribers: new_subscribers}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_last_motion, _from, state) do
    {:reply, {:ok, state.last_motion}, state}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) when is_binary(data) do
    # Parse HID event data
    case parse_hid_event(data) do
      {:ok, %{type: :motion} = event_data} ->
        # Update state and notify subscribers about motion
        axis_update = Map.put(%{}, event_data.axis, event_data.value)
        updated_motion = Map.merge(state.last_motion, axis_update)
        new_state = %{state | last_motion: updated_motion}
        notify_subscribers(new_state.subscribers, {:motion, event_data})
        {:noreply, new_state}
        
      {:ok, %{type: :button} = event_data} ->
        # Notify subscribers about button events
        notify_subscribers(state.subscribers, {:button, event_data})
        {:noreply, state}
        
      {:ok, %{type: :status} = event_data} ->
        # Log status messages
        Logger.info("SpaceMouse status: #{event_data.message}")
        {:noreply, state}
        
      {:ok, %{type: :debug} = event_data} ->
        # Log debug events (can be disabled in production)
        Logger.debug("HID debug: page=#{event_data.page}, usage=#{event_data.usage}, value=#{event_data.value}")
        {:noreply, state}
        
      {:error, _reason} ->
        # Ignore parsing errors (normal for unrecognized events)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("HID monitor process exited with status #{status}")
    new_state = %{state | port: nil, monitor_active: false}
    {:noreply, new_state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp check_spacemouse_availability do
    # Check if SpaceMouse is in HID device list
    case System.cmd("hidutil", ["list"], stderr_to_stdout: true) do
      {output, 0} ->
        if String.contains?(output, "0x256f") and String.contains?(output, "0xc635") do
          {:ok, :found}
        else
          {:error, :not_in_hid_list}
        end
        
      {_output, _code} ->
        {:error, :hidutil_failed}
    end
  end

  defp start_hid_monitor(state) do
    Logger.info("Starting HID event monitoring for SpaceMouse...")
    
    # Try different approaches to monitor HID events
    case create_monitor_approach_1(state) do
      {:ok, new_state} ->
        {:ok, new_state}
        
      {:error, _reason} ->
        # Fallback to approach 2
        create_monitor_approach_2(state)
    end
  end

  # Approach 1: Use our C helper program (preferred)
  defp create_monitor_approach_1(state) do
    helper_path = Path.join([__DIR__, "..", "..", "priv", "spacemouse_reader"])
    
    if File.exists?(helper_path) do
      try do
        port = Port.open(
          {:spawn_executable, helper_path},
          [:binary, :exit_status, {:line, 1024}]
        )
        
        Logger.info("✓ Started C helper for HID monitoring")
        new_state = %{state | port: port, monitor_active: true}
        {:ok, new_state}
        
      rescue
        error ->
          Logger.error("Failed to start C helper: #{inspect(error)}")
          {:error, :helper_failed}
      end
    else
      Logger.info("C helper not found, trying fallback approach")
      {:error, :no_helper}
    end
  end

  # Approach 2: Create a simple C program that uses IOKit and communicate via Port
  defp create_monitor_approach_2(state) do
    # Check if we have a pre-built C helper program
    helper_path = Path.join([__DIR__, "..", "..", "priv", "spacemouse_reader"])
    
    if File.exists?(helper_path) do
      try do
        port = Port.open(
          {:spawn_executable, helper_path},
          [:binary, :exit_status, {:args, ["--device", "0x256F:0xC635"]}]
        )
        
        Logger.info("✓ Started C helper program for HID monitoring")
        new_state = %{state | port: port, monitor_active: true}
        {:ok, new_state}
        
      rescue
        error ->
          Logger.error("Failed to start C helper: #{inspect(error)}")
          {:error, :helper_failed}
      end
    else
      Logger.info("C helper not found at #{helper_path}")
      {:error, :no_helper}
    end
  end

  defp parse_hid_event(data) do
    line = String.trim(data)
    
    cond do
      # Parse motion events from C helper
      String.starts_with?(line, "motion:") ->
        parse_motion_event(line)
        
      # Parse button events from C helper  
      String.starts_with?(line, "button:") ->
        parse_button_event(line)
        
      # Parse general HID events for debugging
      String.starts_with?(line, "hid_event:") ->
        parse_debug_event(line)
        
      # Status messages
      line in ["ready", "device_found", "device_removed"] ->
        {:ok, %{type: :status, message: line, timestamp: System.monotonic_time(:millisecond)}}
        
      true ->
        {:error, :unknown_format}
    end
  end

  defp parse_motion_event(line) do
    # Parse "motion:page=1,usage=48,value=123"
    case Regex.run(~r/motion:page=(\d+),usage=(\d+),value=(-?\d+)/, line) do
      [_, _page, usage, value] ->
        usage_num = String.to_integer(usage)
        value_num = String.to_integer(value)
        
        motion_data = case usage_num do
          48 -> %{axis: :x, value: value_num}      # X translation
          49 -> %{axis: :y, value: value_num}      # Y translation  
          50 -> %{axis: :z, value: value_num}      # Z translation
          51 -> %{axis: :rx, value: value_num}     # X rotation
          52 -> %{axis: :ry, value: value_num}     # Y rotation
          53 -> %{axis: :rz, value: value_num}     # Z rotation
          _ -> %{axis: :unknown, value: value_num}
        end
        
        {:ok, %{
          type: :motion, 
          axis: motion_data.axis,
          value: motion_data.value,
          timestamp: System.monotonic_time(:millisecond),
          raw: line
        }}
        
      _ ->
        {:error, :invalid_motion_format}
    end
  end

  defp parse_button_event(line) do
    # Parse "button:page=9,usage=1,value=1"
    case Regex.run(~r/button:page=(\d+),usage=(\d+),value=(-?\d+)/, line) do
      [_, _page, usage, value] ->
        button_num = String.to_integer(usage)
        pressed = String.to_integer(value) > 0
        
        {:ok, %{
          type: :button,
          button: button_num,
          pressed: pressed,
          timestamp: System.monotonic_time(:millisecond),
          raw: line
        }}
        
      _ ->
        {:error, :invalid_button_format}
    end
  end

  defp parse_debug_event(line) do
    # Parse "hid_event:page=1,usage=48,value=123" for debugging
    case Regex.run(~r/hid_event:page=(\d+),usage=(\d+),value=(-?\d+)/, line) do
      [_, page, usage, value] ->
        {:ok, %{
          type: :debug,
          page: String.to_integer(page),
          usage: String.to_integer(usage), 
          value: String.to_integer(value),
          timestamp: System.monotonic_time(:millisecond),
          raw: line
        }}
        
      _ ->
        {:error, :invalid_debug_format}
    end
  end

  defp notify_subscribers(subscribers, message) do
    Enum.each(subscribers, fn subscriber_pid ->
      send(subscriber_pid, {:spacemouse_hid_event, message})
    end)
  end

  @doc """
  Test if HID monitoring is working by checking for any SpaceMouse events.
  """
  def test_hid_monitoring do
    Logger.info("=== Testing SpaceMouse HID Event Monitoring ===")
    
    # Subscribe to our own events for testing
    subscribe()
    
    case start_monitoring() do
      {:ok, :started} ->
        Logger.info("✓ HID monitoring started")
        Logger.info("Please move your SpaceMouse for 10 seconds...")
        
        # Wait for events
        receive_events(10_000)
        
        stop_monitoring()
        
      {:error, reason} ->
        Logger.error("✗ Failed to start monitoring: #{inspect(reason)}")
    end
  end

  defp receive_events(timeout) do
    receive do
      {:spacemouse_hid_event, {:motion, motion_data}} ->
        Logger.info("📡 Motion detected: #{inspect(motion_data)}")
        receive_events(1000)  # Continue listening for 1 more second
        
    after
      timeout ->
        Logger.info("No motion events received in #{timeout}ms")
    end
  end

  @doc """
  Create a simple C helper program template.
  """
  def create_c_helper_template do
    c_code = """
    /*
     * SpaceMouse HID Reader using IOKit
     * Compile with: clang -framework IOKit -framework CoreFoundation -o spacemouse_reader spacemouse_reader.c
     */
    #include <IOKit/hid/IOHIDManager.h>
    #include <stdio.h>
    #include <stdlib.h>

    static void device_matching_callback(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
        printf("device_found\\n");
        fflush(stdout);
    }

    static void device_removal_callback(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
        printf("device_removed\\n");
        fflush(stdout);
    }

    static void input_callback(void *context, IOReturn result, void *sender, IOHIDValueRef value) {
        IOHIDElementRef element = IOHIDValueGetElement(value);
        uint32_t usage_page = IOHIDElementGetUsagePage(element);
        uint32_t usage = IOHIDElementGetUsage(element);
        CFIndex int_value = IOHIDValueGetIntegerValue(value);
        
        printf("hid_event:page=%d,usage=%d,value=%ld\\n", usage_page, usage, int_value);
        fflush(stdout);
    }

    int main(int argc, char *argv[]) {
        IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, 0);
        
        // Set device matching for SpaceMouse (VID: 0x256F, PID: 0xC635)
        CFMutableDictionaryRef matching = CFDictionaryCreateMutable(
            kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        
        int vid = 0x256F;
        int pid = 0xC635;
        CFNumberRef vendor_id = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &vid);
        CFNumberRef product_id = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &pid);
        
        CFDictionarySetValue(matching, CFSTR(kIOHIDVendorIDKey), vendor_id);
        CFDictionarySetValue(matching, CFSTR(kIOHIDProductIDKey), product_id);
        
        IOHIDManagerSetDeviceMatching(manager, matching);
        
        // Set callbacks
        IOHIDManagerRegisterDeviceMatchingCallback(manager, device_matching_callback, NULL);
        IOHIDManagerRegisterDeviceRemovalCallback(manager, device_removal_callback, NULL);
        IOHIDManagerRegisterInputValueCallback(manager, input_callback, NULL);
        
        // Schedule with run loop
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        
        // Open manager
        IOReturn ret = IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone);
        if (ret != kIOReturnSuccess) {
            printf("error:failed_to_open_manager\\n");
            return 1;
        }
        
        printf("ready\\n");
        fflush(stdout);
        
        // Run event loop
        CFRunLoopRun();
        
        return 0;
    }
    """
    
    priv_dir = Path.join([__DIR__, "..", "..", "priv"])
    File.mkdir_p!(priv_dir)
    
    c_file = Path.join(priv_dir, "spacemouse_reader.c")
    File.write!(c_file, c_code)
    
    Logger.info("✓ Created C helper template at #{c_file}")
    Logger.info("To compile: cd priv && clang -framework IOKit -framework CoreFoundation -o spacemouse_reader spacemouse_reader.c")
  end
end
