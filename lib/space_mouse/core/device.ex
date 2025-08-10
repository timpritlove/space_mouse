defmodule SpaceMouse.Core.Device do
  @moduledoc """
  Main SpaceMouse device abstraction.
  
  This module provides a unified interface for SpaceMouse interaction across
  different platforms, automatically selecting the appropriate platform
  implementation based on the runtime environment.
  
  Features:
  - Cross-platform device detection and connection management
  - Real-time motion and button event streaming
  - LED control (when supported by platform)  
  - Automatic reconnection handling
  - Clean supervisor integration
  """

  use GenServer
  require Logger



  defmodule State do
    @moduledoc false
    defstruct [
      :platform_module,
      :platform_state,
      :connection_state,
      :subscribers,
      :led_state,
      :last_motion,
      :last_button_state,
      :auto_reconnect
    ]
  end

  @type connection_state :: :disconnected | :connecting | :connected | :error
  @type motion_data :: %{x: integer(), y: integer(), z: integer(), rx: integer(), ry: integer(), rz: integer()}
  @type button_data :: %{id: integer(), state: :pressed | :released}

  # Client API

  @doc """
  Start the SpaceMouse device manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start monitoring for SpaceMouse devices.
  """
  def start_monitoring do
    GenServer.call(__MODULE__, :start_monitoring)
  end

  @doc """
  Stop monitoring for SpaceMouse devices.
  """
  def stop_monitoring do
    GenServer.call(__MODULE__, :stop_monitoring)
  end

  @doc """
  Subscribe to SpaceMouse events.
  
  The subscriber will receive:
  - `{:spacemouse_connected, device_info}`
  - `{:spacemouse_disconnected, device_info}`
  - `{:spacemouse_motion, motion_data}`
  - `{:spacemouse_button, button_data}`
  """
  def subscribe(pid \\ self()) do
    GenServer.call(__MODULE__, {:subscribe, pid})
  end

  @doc """
  Unsubscribe from SpaceMouse events.
  """
  def unsubscribe(pid \\ self()) do
    GenServer.call(__MODULE__, {:unsubscribe, pid})
  end

  @doc """
  Set LED state (on/off).
  """
  def set_led(state) when state in [:on, :off] do
    GenServer.call(__MODULE__, {:set_led, state})
  end

  @doc """
  Get current LED state.
  """
  def get_led_state do
    GenServer.call(__MODULE__, :get_led_state)
  end

  @doc """
  Check if a SpaceMouse is currently connected.
  """
  def connected? do
    GenServer.call(__MODULE__, :connected?)
  end

  @doc """
  Get current connection state.
  """
  def connection_state do
    GenServer.call(__MODULE__, :connection_state)
  end

  @doc """
  Get platform information.
  """
  def platform_info do
    GenServer.call(__MODULE__, :platform_info)
  end

  # GenServer Implementation

  @impl true
  def init(opts) do
    # Select platform implementation
    platform_module = select_platform()
    auto_reconnect = Keyword.get(opts, :auto_reconnect, true)
    
    # Initialize platform
    {:ok, platform_state} = platform_module.platform_init(owner_pid: self())
    
    state = %State{
      platform_module: platform_module,
      platform_state: platform_state,
      connection_state: :disconnected,
      subscribers: MapSet.new(),
      led_state: :unknown,
      last_motion: %{x: 0.0, y: 0.0, z: 0.0, rx: 0.0, ry: 0.0, rz: 0.0},
      last_button_state: %{},
      auto_reconnect: auto_reconnect
    }
    
    Logger.info("SpaceMouse device manager initialized (platform: #{platform_module})")
    {:ok, state}
  end

  @impl true
  def handle_call(:start_monitoring, _from, state) do
    case state.platform_module.start_monitoring(state.platform_state) do
      {:ok, new_platform_state} ->
        new_state = %{state | connection_state: :connecting, platform_state: new_platform_state}
        {:reply, :ok, new_state}
        
      {:error, reason} ->
        new_state = %{state | connection_state: :error}
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call(:stop_monitoring, _from, state) do
    :ok = state.platform_module.stop_monitoring(state.platform_state)
    new_state = %{state | connection_state: :disconnected}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    new_subscribers = MapSet.put(state.subscribers, pid)
    new_state = %{state | subscribers: new_subscribers}
    
    # Send current state to new subscriber
    if state.connection_state == :connected do
      send(pid, {:spacemouse_connected, get_device_info(state)})
    end
    
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:unsubscribe, pid}, _from, state) do
    new_subscribers = MapSet.delete(state.subscribers, pid)
    new_state = %{state | subscribers: new_subscribers}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:set_led, led_state}, _from, state) do
    case state.platform_module.send_led_command(state.platform_state, led_state) do
      {:ok, new_platform_state} ->
        # Check if LED state actually changed
        if state.led_state != led_state do
          # Emit LED state change event
          led_event = {:spacemouse_led_changed, %{
            from: state.led_state,
            to: led_state,
            timestamp: System.monotonic_time(:millisecond)
          }}
          broadcast_to_subscribers(state.subscribers, led_event)
        end
        
        new_state = %{state | led_state: led_state, platform_state: new_platform_state}
        {:reply, :ok, new_state}
        
      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:get_led_state, _from, state) do
    {:reply, {:ok, state.led_state}, state}
  end

  @impl true
  def handle_call(:connected?, _from, state) do
    connected = state.connection_state == :connected
    {:reply, connected, state}
  end

  @impl true
  def handle_call(:connection_state, _from, state) do
    {:reply, state.connection_state, state}
  end

  @impl true
  def handle_call(:platform_info, _from, state) do
    info = state.platform_module.platform_info()
    {:reply, info, state}
  end

  @impl true
  def handle_info({:hid_event, %{type: :status, message: "ready"}}, state) do
    Logger.info("HID reader ready")
    {:noreply, state}
  end

  @impl true
  def handle_info({:hid_event, %{type: :status, message: "device_connected"}}, state) do
    Logger.info("SpaceMouse device connected via HID")
    
    # Update platform state to reflect device connection
    new_platform_state = %{state.platform_state | device_connected: true}
    new_state = %{state | connection_state: :connected, platform_state: new_platform_state}
    
    # Notify subscribers
    device_info = %{platform: :macos, method: :iokit_hid, timestamp: System.monotonic_time(:millisecond)}
    message = {:spacemouse_connected, device_info}
    broadcast_to_subscribers(state.subscribers, message)
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:hid_event, %{type: :status, message: "device_disconnected"}}, state) do
    Logger.info("SpaceMouse device disconnected via HID")
    
    # Update platform state to reflect device disconnection
    new_platform_state = %{state.platform_state | device_connected: false}
    new_state = %{state | connection_state: :disconnected, led_state: :unknown, platform_state: new_platform_state}
    
    # Notify subscribers
    device_info = %{platform: :macos, method: :iokit_hid, timestamp: System.monotonic_time(:millisecond)}
    message = {:spacemouse_disconnected, device_info}
    broadcast_to_subscribers(state.subscribers, message)
    
    # Auto-reconnect if enabled
    if state.auto_reconnect do
      Process.send_after(self(), :attempt_reconnect, 2000)
    end
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:hid_event, %{type: :motion, data: motion_data}}, state) do
    # Scale motion values from ±350 integer range to ±1.0 float range
    scaled_motion_data = scale_motion_values(motion_data)
    
    # Update last motion state with scaled values
    new_motion = Map.merge(state.last_motion, scaled_motion_data)
    new_state = %{state | last_motion: new_motion}
    
    # Notify subscribers with scaled values
    message = {:spacemouse_motion, new_motion}
    broadcast_to_subscribers(state.subscribers, message)
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:hid_event, %{type: :button, data: button_data}}, state) do
    # Update button state
    button_id = Map.get(button_data, :id, 0)
    button_state = Map.get(button_data, :state, :unknown)
    
    new_button_state = Map.put(state.last_button_state, button_id, button_state)
    new_state = %{state | last_button_state: new_button_state}
    
    # Notify subscribers
    message = {:spacemouse_button, button_data}
    broadcast_to_subscribers(state.subscribers, message)
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:hid_event, _event}, state) do
    # Ignore unknown HID events
    {:noreply, state}
  end

  @impl true
  def handle_info({:device_connected, device_info}, state) do
    Logger.info("SpaceMouse connected: #{inspect(device_info)}")
    
    new_state = %{state | connection_state: :connected}
    
    # Notify subscribers
    message = {:spacemouse_connected, device_info}
    broadcast_to_subscribers(state.subscribers, message)
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:device_disconnected, device_info}, state) do
    Logger.info("SpaceMouse disconnected: #{inspect(device_info)}")
    
    new_state = %{state | connection_state: :disconnected, led_state: :unknown}
    
    # Notify subscribers
    message = {:spacemouse_disconnected, device_info}
    broadcast_to_subscribers(state.subscribers, message)
    
    # Auto-reconnect if enabled
    if state.auto_reconnect do
      Process.send_after(self(), :attempt_reconnect, 2000)
    end
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:motion_event, event}, state) do
    # Extract motion data
    motion_data = Map.get(event, :data, %{})
    
    # Update last motion state
    new_motion = Map.merge(state.last_motion, motion_data)
    new_state = %{state | last_motion: new_motion}
    
    # Notify subscribers
    message = {:spacemouse_motion, new_motion}
    broadcast_to_subscribers(state.subscribers, message)
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:button_event, event}, state) do
    # Extract button data
    button_data = Map.get(event, :data, %{})
    
    # Update button state
    button_id = Map.get(button_data, :id, 0)
    button_state = Map.get(button_data, :state, :unknown)
    
    new_button_state = Map.put(state.last_button_state, button_id, button_state)
    new_state = %{state | last_button_state: new_button_state}
    
    # Notify subscribers
    message = {:spacemouse_button, button_data}
    broadcast_to_subscribers(state.subscribers, message)
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:attempt_reconnect, state) do
    if state.connection_state == :disconnected do
      Logger.info("Attempting to reconnect SpaceMouse...")
      
      case state.platform_module.start_monitoring(state.platform_state) do
        {:ok, new_platform_state} ->
          new_state = %{state | connection_state: :connecting, platform_state: new_platform_state}
          {:noreply, new_state}
          
        {:error, reason} ->
          Logger.warning("Reconnection failed: #{inspect(reason)}")
          
          # Try again later if auto-reconnect is enabled
          if state.auto_reconnect do
            Process.send_after(self(), :attempt_reconnect, 5000)
          end
          
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  # Private Implementation

  defp select_platform do
    case :os.type() do
      {:unix, :darwin} ->
        SpaceMouse.Platform.MacOS.HidBridge
        
      {:unix, :linux} ->
        # Future Linux implementation
        raise "Linux support not yet implemented. Currently only macOS is supported."
        
      {:win32, _} ->
        # Future Windows implementation  
        raise "Windows support not yet implemented. Currently only macOS is supported."
        
      other ->
        raise "Unsupported platform: #{inspect(other)}. Currently only macOS is supported."
    end
  end

  defp get_device_info(state) do
    base_info = state.platform_module.platform_info()
    Map.merge(base_info, %{
      led_state: state.led_state,
      last_motion: state.last_motion,
      timestamp: System.monotonic_time(:millisecond)
    })
  end

  defp broadcast_to_subscribers(subscribers, message) do
    Enum.each(subscribers, fn pid ->
      send(pid, message)
    end)
  end

  # Scale motion values from ±350 integer range to ±1.0 float range
  defp scale_motion_values(motion_data) do
    # Hardware range is ±350, scale to ±1.0
    scale_factor = 1.0 / 350.0
    
    motion_data
    |> Enum.map(fn {axis, value} ->
      # Convert integer to float and scale
      scaled_value = value * scale_factor
      {axis, scaled_value}
    end)
    |> Enum.into(%{})
  end
end
