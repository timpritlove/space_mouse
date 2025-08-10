defmodule SpaceNavigator.Core.Api do
  @moduledoc """
  Clean, simple public API for SpaceMouse interaction.
  
  This module provides the main interface that external applications should use
  to interact with SpaceMouse devices. It abstracts away all platform-specific
  details and provides a consistent experience across different operating systems.
  
  ## Basic Usage
  
      # Start monitoring for devices
      SpaceNavigator.start_monitoring()
      
      # Subscribe to events  
      SpaceNavigator.subscribe()
      
      # Control LED
      SpaceNavigator.set_led(:on)
      SpaceNavigator.set_led(:off)
      
      # Check connection status
      SpaceNavigator.connected?()
  
  ## Event Messages
  
  When subscribed, your process will receive these messages:
  
  - `{:spacemouse_connected, device_info}` - Device connected
  - `{:spacemouse_disconnected, device_info}` - Device disconnected  
  - `{:spacemouse_motion, motion_data}` - 6DOF motion data
  - `{:spacemouse_button, button_data}` - Button press/release events
  
  ## Motion Data Format
  
      %{
        x: integer(),   # Translation X axis
        y: integer(),   # Translation Y axis  
        z: integer(),   # Translation Z axis
        rx: integer(),  # Rotation X axis
        ry: integer(),  # Rotation Y axis
        rz: integer()   # Rotation Z axis
      }
  
  ## Button Data Format
  
      %{
        id: integer(),              # Button ID (1, 2, etc.)
        state: :pressed | :released # Button state
      }
  """

  alias SpaceNavigator.Core.Device

  @doc """
  Start monitoring for SpaceMouse devices.
  
  This begins watching for device connections and will automatically
  connect when a SpaceMouse is detected.
  
  Returns `:ok` on success or `{:error, reason}` if monitoring fails.
  """
  @spec start_monitoring() :: :ok | {:error, term()}
  def start_monitoring do
    Device.start_monitoring()
  end

  @doc """
  Stop monitoring for SpaceMouse devices.
  
  This will disconnect from any connected device and stop watching
  for new connections.
  """
  @spec stop_monitoring() :: :ok
  def stop_monitoring do
    Device.stop_monitoring()
  end

  @doc """
  Subscribe to SpaceMouse events.
  
  The calling process will receive event messages for device connections,
  motion data, and button events.
  
  Optionally specify a different process PID to receive the events.
  """
  @spec subscribe(pid()) :: :ok
  def subscribe(pid \\ self()) do
    Device.subscribe(pid)
  end

  @doc """
  Unsubscribe from SpaceMouse events.
  
  Stops sending event messages to the specified process.
  """
  @spec unsubscribe(pid()) :: :ok  
  def unsubscribe(pid \\ self()) do
    Device.unsubscribe(pid)
  end

  @doc """
  Set the SpaceMouse LED state.
  
  Args:
  - `:on` - Turn LED on
  - `:off` - Turn LED off
  
  Returns `:ok` on success or `{:error, reason}` if the command fails.
  Note that LED control may not be supported on all platforms or device models.
  """
  @spec set_led(:on | :off) :: :ok | {:error, term()}
  def set_led(state) when state in [:on, :off] do
    Device.set_led(state)
  end

  @doc """
  Get the current LED state.
  
  Returns `{:ok, led_state}` where led_state is `:on`, `:off`, or `:unknown`.
  """
  @spec get_led_state() :: {:ok, :on | :off | :unknown}
  def get_led_state do
    Device.get_led_state()
  end

  @doc """
  Check if a SpaceMouse device is currently connected.
  
  Returns `true` if connected, `false` if not connected.
  """
  @spec connected?() :: boolean()
  def connected? do
    Device.connected?()
  end

  @doc """
  Get the current connection state.
  
  Returns one of:
  - `:disconnected` - No device connected
  - `:connecting` - Attempting to connect
  - `:connected` - Device connected and ready
  - `:error` - Connection error occurred
  """
  @spec connection_state() :: :disconnected | :connecting | :connected | :error
  def connection_state do
    Device.connection_state()
  end

  @doc """
  Get information about the current platform implementation.
  
  Returns a map with platform details including the access method being used.
  """
  @spec platform_info() :: %{platform: atom(), method: atom(), version: String.t()}
  def platform_info do
    Device.platform_info()
  end

  @doc """
  Get the current motion state.
  
  Returns the last received motion data, or zeros if no motion has been detected.
  """
  @spec get_motion_state() :: %{x: integer(), y: integer(), z: integer(), rx: integer(), ry: integer(), rz: integer()}
  def get_motion_state do
    # This would need to be added to the Device module
    {:ok, motion} = GenServer.call(Device, :get_motion_state)
    motion
  end

  @doc """
  Configure automatic reconnection behavior.
  
  When enabled (default), the system will automatically attempt to reconnect
  when a device is disconnected.
  """
  @spec set_auto_reconnect(boolean()) :: :ok
  def set_auto_reconnect(enabled) when is_boolean(enabled) do
    GenServer.call(Device, {:set_auto_reconnect, enabled})
  end
end
