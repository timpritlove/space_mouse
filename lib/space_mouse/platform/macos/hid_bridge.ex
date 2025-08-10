defmodule SpaceMouse.Platform.MacOS.HidBridge do
  @moduledoc """
  macOS platform implementation using IOKit HID Manager.
  
  This module bridges between Elixir and the minimal C HID reader program,
  providing SpaceMouse access through macOS IOKit when direct USB access
  is blocked by the kernel HID driver.
  
  The C program handles the low-level IOKit communication and outputs
  structured events that this module parses and forwards to the core system.
  """

  @behaviour SpaceMouse.Platform.Behaviour
  
  require Logger

  alias SpaceMouse.Platform.MacOS.PortManager

  defmodule State do
    @moduledoc false
    defstruct [
      :port_manager,
      :owner_pid,
      :device_connected,
      :led_state
    ]
  end

  # Platform Behaviour Implementation

  @impl SpaceMouse.Platform.Behaviour
  def platform_init(opts) do
    owner_pid = Keyword.get(opts, :owner_pid, self())
    
    state = %State{
      port_manager: nil,
      owner_pid: owner_pid,
      device_connected: false,
      led_state: :unknown
    }
    
    {:ok, state}
  end

  @impl SpaceMouse.Platform.Behaviour
  def start_monitoring(state) do
    case PortManager.start_hid_reader(owner_pid: state.owner_pid) do
      {:ok, port_manager} ->
        new_state = %{state | port_manager: port_manager}
        {:ok, new_state}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl SpaceMouse.Platform.Behaviour
  def stop_monitoring(state) do
    case state.port_manager do
      nil -> 
        :ok
        
      port_manager ->
        PortManager.stop_hid_reader(port_manager)
        :ok
    end
  end

  @impl SpaceMouse.Platform.Behaviour
  def send_led_command(state, command) do
    case send_led_command_impl(state, command) do
      :ok -> {:ok, %{state | led_state: command}}
      error -> error
    end
  end

  @impl SpaceMouse.Platform.Behaviour
  def get_led_state(state) do
    {:ok, state.led_state}
  end

  @impl SpaceMouse.Platform.Behaviour
  def device_connected?(state) do
    {:ok, state.device_connected}
  end

  @impl SpaceMouse.Platform.Behaviour
  def platform_info do
    %{
      platform: :macos,
      method: :iokit_hid,
      version: "1.0.0"
    }
  end

  # Private Implementation

  defp send_led_command_impl(state, command) do
    case {state.device_connected, state.port_manager} do
      {false, _} ->
        {:error, :device_not_connected}
        
      {true, nil} ->
        {:error, :port_manager_not_available}
        
      {true, port_manager} ->
        # Send LED command to the C HID reader program
        led_cmd = case command do
          :on -> "LED:on"
          :off -> "LED:off"
          _ -> "LED:off"
        end
        
        case PortManager.send_command(port_manager, led_cmd) do
          :ok ->
            Logger.debug("LED command sent: #{command}")
            :ok
            
          {:error, reason} ->
            Logger.error("Failed to send LED command: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end
end
