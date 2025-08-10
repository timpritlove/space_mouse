defmodule SpaceNavigator do
  @moduledoc """
  SpaceNavigator - Cross-platform SpaceMouse device support for Elixir.
  
  This library provides a clean, unified interface for working with 3Dconnexion
  SpaceMouse devices across different operating systems. It automatically handles
  platform-specific access methods and provides real-time motion and button events.
  
  ## Features
  
  - Cross-platform SpaceMouse support (macOS, Linux, Windows)
  - Real-time 6DOF motion tracking (X, Y, Z translation + rotation)
  - Button press/release event handling
  - LED control (when supported)
  - Automatic device connection/reconnection
  - Clean GenServer-based architecture
  - Platform-specific optimizations
  
  ## Quick Start
  
      # Start monitoring for SpaceMouse devices
      SpaceNavigator.start_monitoring()
      
      # Subscribe to events
      SpaceNavigator.subscribe()
      
      # Control LED
      SpaceNavigator.set_led(:on)
      SpaceNavigator.set_led(:off)
      
      # Check if device is connected
      SpaceNavigator.connected?()
  
  ## Event Messages
  
  When subscribed, your process will receive:
  
  - `{:spacemouse_connected, device_info}` - Device connected
  - `{:spacemouse_disconnected, device_info}` - Device disconnected
  - `{:spacemouse_motion, motion_data}` - 6DOF motion data  
  - `{:spacemouse_button, button_data}` - Button events
  - `{:spacemouse_led_changed, led_change}` - LED state change events
  
  ## Motion Data Format
  
      %{
        x: float(),   # Translation X (-1.0 to +1.0)
        y: float(),   # Translation Y (-1.0 to +1.0)
        z: float(),   # Translation Z (-1.0 to +1.0)
        rx: float(),  # Rotation X (-1.0 to +1.0)
        ry: float(),  # Rotation Y (-1.0 to +1.0)
        rz: float()   # Rotation Z (-1.0 to +1.0)
      }
  
  ## Platform Support
  
  - **macOS**: Uses IOKit HID Manager (bypasses kernel HID driver)
  - **Linux**: Direct libusb access (planned)
  - **Windows**: HID API (planned)
  
  The appropriate platform implementation is automatically selected at runtime.
  """

  # Delegate all public API functions to the Core.Api module
  defdelegate start_monitoring(), to: SpaceNavigator.Core.Api
  defdelegate stop_monitoring(), to: SpaceNavigator.Core.Api
  defdelegate subscribe(pid \\ self()), to: SpaceNavigator.Core.Api
  defdelegate unsubscribe(pid \\ self()), to: SpaceNavigator.Core.Api
  defdelegate set_led(state), to: SpaceNavigator.Core.Api
  defdelegate get_led_state(), to: SpaceNavigator.Core.Api
  defdelegate connected?(), to: SpaceNavigator.Core.Api
  defdelegate connection_state(), to: SpaceNavigator.Core.Api
  defdelegate platform_info(), to: SpaceNavigator.Core.Api
  defdelegate get_motion_state(), to: SpaceNavigator.Core.Api
  defdelegate set_auto_reconnect(enabled), to: SpaceNavigator.Core.Api
end