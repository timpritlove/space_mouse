defmodule SpaceNavigator.Platform.Behaviour do
  @moduledoc """
  Behaviour for platform-specific SpaceMouse communication implementations.
  
  This behaviour defines the interface that all platform implementations must follow,
  allowing the core system to work across different operating systems with different
  access methods (direct USB on Linux, IOKit HID on macOS, etc.).
  """

  @doc """
  Initialize the platform-specific communication system.
  
  This should set up any required resources, start background processes,
  and prepare the system for device detection.
  
  Returns:
  - `{:ok, state}` on successful initialization
  - `{:error, reason}` if initialization fails
  """
  @callback platform_init(opts :: keyword()) :: {:ok, term()} | {:error, term()}

  @doc """
  Start monitoring for SpaceMouse device connections.
  
  The implementation should begin watching for device connections and
  disconnections, sending appropriate messages to the calling process.
  
  Expected messages:
  - `{:device_connected, device_info}`
  - `{:device_disconnected, device_info}`
  - `{:motion_event, motion_data}`
  - `{:button_event, button_data}`
  
  Returns:
  - `:ok` if monitoring started successfully
  - `{:error, reason}` if monitoring could not be started
  """
  @callback start_monitoring(state :: term()) :: {:ok, term()} | {:error, term()}

  @doc """
  Stop monitoring for SpaceMouse devices.
  
  This should clean up resources and stop all background processes.
  """
  @callback stop_monitoring(state :: term()) :: :ok

  @doc """
  Send a command to control the SpaceMouse LED.
  
  Args:
  - `state`: Platform state
  - `command`: LED command (`:on`, `:off`)
  
  Returns:
  - `:ok` if command was sent successfully
  - `{:error, reason}` if command failed
  """
  @callback send_led_command(state :: term(), command :: :on | :off) :: {:ok, term()} | {:error, term()}

  @doc """
  Get the current LED state if supported by the platform.
  
  Returns:
  - `{:ok, :on | :off | :unknown}` 
  - `{:error, :not_supported}` if LED state cannot be queried
  """
  @callback get_led_state(state :: term()) :: {:ok, :on | :off | :unknown} | {:error, term()}

  @doc """
  Check if a SpaceMouse device is currently connected.
  
  Returns:
  - `{:ok, true}` if a device is connected
  - `{:ok, false}` if no device is connected
  - `{:error, reason}` if status cannot be determined
  """
  @callback device_connected?(state :: term()) :: {:ok, boolean()} | {:error, term()}

  @doc """
  Get platform-specific information.
  
  Returns a map with platform details like:
  - `:platform` - Platform name (`:macos`, `:linux`, etc.)
  - `:method` - Access method (`:iokit_hid`, `:direct_usb`, etc.)
  - `:version` - Implementation version
  """
  @callback platform_info() :: %{
    platform: atom(),
    method: atom(),
    version: String.t()
  }
end
