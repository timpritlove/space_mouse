# SpaceMouse Usage Guide

This guide shows how to use the SpaceMouse library in your Elixir applications for cross-platform SpaceMouse support.

## Quick Start

### Installation

Add SpaceMouse to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:space_mouse, "~> 1.0"}
  ]
end
```

Run `mix deps.get` to install.

### Basic Usage

```elixir
# Start monitoring for SpaceMouse devices
SpaceMouse.start_monitoring()

# Subscribe to events
SpaceMouse.subscribe()

# Check if a device is connected
if SpaceMouse.connected?() do
  IO.puts("SpaceMouse is ready!")
end

# Control the LED
SpaceMouse.set_led(:on)
SpaceMouse.set_led(:off)
```

### Receiving Events

Once subscribed, your process will receive these messages:

```elixir
receive do
  {:spacemouse_connected, device_info} ->
    IO.puts("SpaceMouse connected: #{inspect(device_info)}")
    
  {:spacemouse_disconnected, device_info} ->
    IO.puts("SpaceMouse disconnected: #{inspect(device_info)}")
    
  {:spacemouse_motion, motion} ->
    %{x: x, y: y, z: z, rx: rx, ry: ry, rz: rz} = motion
    IO.puts("Motion: X=#{x} Y=#{y} Z=#{z} RX=#{rx} RY=#{ry} RZ=#{rz}")
    
  {:spacemouse_button, button} ->
    %{id: id, state: state} = button
    IO.puts("Button #{id}: #{state}")
    
  {:spacemouse_led_changed, led_change} ->
    %{from: from, to: to} = led_change
    IO.puts("LED changed: #{from} -> #{to}")
end
```

## Complete API Reference

### Device Management

#### `start_monitoring()`
Start monitoring for SpaceMouse devices. This begins watching for device connections.

```elixir
case SpaceMouse.start_monitoring() do
  :ok -> IO.puts("Monitoring started")
  {:error, reason} -> IO.puts("Failed to start: #{reason}")
end
```

#### `stop_monitoring()`
Stop monitoring and disconnect from any connected devices.

```elixir
SpaceMouse.stop_monitoring()
```

#### `connected?()`
Check if a SpaceMouse is currently connected.

```elixir
if SpaceMouse.connected?() do
  # Device is ready for use
end
```

#### `connection_state()`
Get detailed connection state.

```elixir
case SpaceMouse.connection_state() do
  :disconnected -> IO.puts("No device")
  :connecting -> IO.puts("Connecting...")
  :connected -> IO.puts("Device ready")
  :error -> IO.puts("Connection error")
end
```

### Event Subscription

#### `subscribe(pid \\ self())`
Subscribe a process to SpaceMouse events.

```elixir
# Subscribe current process
SpaceMouse.subscribe()

# Subscribe different process
SpaceMouse.subscribe(other_pid)
```

#### `unsubscribe(pid \\ self())`
Unsubscribe from events.

```elixir
SpaceMouse.unsubscribe()
```

### LED Control

#### `set_led(state)`
Control the SpaceMouse LED.

```elixir
SpaceMouse.set_led(:on)   # Turn LED on
SpaceMouse.set_led(:off)  # Turn LED off
```

#### `get_led_state()`
Get current LED state.

```elixir
{:ok, state} = SpaceMouse.get_led_state()
# state is :on, :off, or :unknown
```

### Platform Information

#### `platform_info()`
Get information about the current platform implementation.

```elixir
info = SpaceMouse.platform_info()
# %{platform: :macos, method: :iokit_hid, version: "1.0.0"}
```

### Motion State

#### `get_motion_state()`
Get the last received motion data.

```elixir
motion = SpaceMouse.get_motion_state()
# %{x: 0, y: 0, z: 0, rx: 0, ry: 0, rz: 0}
```

### Configuration

#### `set_auto_reconnect(enabled)`
Configure automatic reconnection behavior.

```elixir
SpaceMouse.set_auto_reconnect(true)   # Enable auto-reconnect (default)
SpaceMouse.set_auto_reconnect(false)  # Disable auto-reconnect
```

## Event Types and Data Formats

### Device Events

#### Connection Event
```elixir
{:spacemouse_connected, device_info}

# device_info example:
%{
  platform: :macos,
  method: :iokit_hid,
  timestamp: 1640995200000
}
```

#### Disconnection Event
```elixir
{:spacemouse_disconnected, device_info}

# Same format as connection event
```

### Motion Events

```elixir
{:spacemouse_motion, motion_data}

# motion_data format:
%{
  x: -0.351,   # Translation X axis (-1.0 to +1.0)
  y: 0.129,    # Translation Y axis (-1.0 to +1.0)
  z: -0.571,   # Translation Z axis (-1.0 to +1.0)
  rx: 0.191,   # Rotation X axis (-1.0 to +1.0)
  ry: -0.254,  # Rotation Y axis (-1.0 to +1.0)
  rz: 0.446    # Rotation Z axis (-1.0 to +1.0)
}
```

**Coordinate System**:
- **X**: Left (-) / Right (+)
- **Y**: Down (-) / Up (+)  
- **Z**: Away (-) / Toward (+)
- **RX**: Pitch down (-) / Pitch up (+)
- **RY**: Yaw left (-) / Yaw right (+)
- **RZ**: Roll left (-) / Roll right (+)

### Button Events

```elixir
{:spacemouse_button, button_data}

# button_data format:
%{
  id: 1,              # Button ID (1, 2, etc.)
  state: :pressed     # :pressed or :released
}
```

### LED Events

```elixir
{:spacemouse_led_changed, led_change}

# led_change format:
%{
  from: :off,                    # Previous LED state (:on, :off, :unknown)
  to: :on,                       # New LED state (:on, :off)
  timestamp: 1640995200000       # System monotonic time in milliseconds
}
```

**LED State Events**:
- Emitted whenever `SpaceMouse.set_led/1` changes the LED state
- Only emitted on actual state changes (no event if setting same state)
- `from` can be `:unknown` on first LED command after connection

## Usage Patterns

### Basic Event Handling

```elixir
defmodule MyApp.SpaceMouseHandler do
  use GenServer
  
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end
  
  def init(_) do
    SpaceMouse.start_monitoring()
    SpaceMouse.subscribe()
    {:ok, %{}}
  end
  
  def handle_info({:spacemouse_connected, _info}, state) do
    IO.puts("SpaceMouse ready!")
    SpaceMouse.set_led(:on)
    {:noreply, state}
  end
  
  def handle_info({:spacemouse_motion, motion}, state) do
    # Process motion data
    handle_motion(motion)
    {:noreply, state}
  end
  
  def handle_info({:spacemouse_button, %{id: 1, state: :pressed}}, state) do
    IO.puts("Menu button pressed!")
    {:noreply, state}
  end
  
  def handle_info(_, state), do: {:noreply, state}
  
  defp handle_motion(%{x: x, y: y, z: z}) do
    # Example: 3D navigation
    if abs(x) > 100 or abs(y) > 100 or abs(z) > 100 do
      IO.puts("Significant movement: X=#{x}, Y=#{y}, Z=#{z}")
    end
  end
end
```

### Motion Filtering and Scaling

```elixir
defmodule MyApp.MotionProcessor do
  # Dead zone to filter small movements (±1.0 range means 0.01-0.05 is a good dead zone)
  @dead_zone 0.03
  
  # Optional additional scaling factor for application (values already ±1.0)
  @scale_factor 2.0  # Example: scale ±1.0 to ±2.0 for more sensitivity
  
  def process_motion(%{x: x, y: y, z: z} = motion) do
    # Apply dead zone
    filtered = %{
      x: apply_dead_zone(x),
      y: apply_dead_zone(y),
      z: apply_dead_zone(z)
    }
    
    # Scale for application use
    scaled = %{
      x: filtered.x * @scale_factor,
      y: filtered.y * @scale_factor,
      z: filtered.z * @scale_factor
    }
    
    scaled
  end
  
  defp apply_dead_zone(value) when abs(value) < @dead_zone, do: 0.0
  defp apply_dead_zone(value), do: value * @scale_factor
end
```

### 3D Camera Control

```elixir
defmodule MyApp.CameraController do
  defstruct position: {0.0, 0.0, 0.0}, rotation: {0.0, 0.0, 0.0}
  
  def update_camera(%__MODULE__{} = camera, motion) do
    # Translation
    {px, py, pz} = camera.position
    new_position = {
      px + motion.x * 0.01,
      py + motion.y * 0.01, 
      pz + motion.z * 0.01
    }
    
    # Rotation
    {rx, ry, rz} = camera.rotation
    new_rotation = {
      rx + motion.rx * 0.001,
      ry + motion.ry * 0.001,
      rz + motion.rz * 0.001
    }
    
    %{camera | position: new_position, rotation: new_rotation}
  end
end
```

### Button-Based Mode Switching

```elixir
defmodule MyApp.ModeController do
  use GenServer
  
  def init(_) do
    {:ok, %{mode: :navigate}}
  end
  
  def handle_info({:spacemouse_button, %{id: 1, state: :pressed}}, state) do
    new_mode = case state.mode do
      :navigate -> :select
      :select -> :navigate
    end
    
    IO.puts("Switched to #{new_mode} mode")
    update_led_for_mode(new_mode)
    
    {:noreply, %{state | mode: new_mode}}
  end
  
  def handle_info({:spacemouse_motion, motion}, %{mode: :navigate} = state) do
    # Handle navigation motion
    MyApp.CameraController.navigate(motion)
    {:noreply, state}
  end
  
  def handle_info({:spacemouse_motion, motion}, %{mode: :select} = state) do
    # Handle selection motion (different behavior)
    MyApp.SelectionController.select(motion)
    {:noreply, state}
  end
  
  defp update_led_for_mode(:navigate), do: SpaceMouse.set_led(:on)
  defp update_led_for_mode(:select), do: SpaceMouse.set_led(:off)
end
```

## Demo Applications

### Basic Demo

Run the basic API demonstration:

```bash
mix run -e "SpaceMouse.Demo.ApiDemo.basic_demo()"
```

### Interactive Demo

Run the interactive demo with LED control:

```bash
mix run -e "SpaceMouse.Demo.ApiDemo.interactive_demo()"
```

### Motion Tracking Demo

Run the motion tracking demo:

```bash
mix run -e "SpaceMouse.Demo.ApiDemo.motion_demo()"
```

## Integration with Phoenix LiveView

```elixir
defmodule MyAppWeb.SpaceMouseLive do
  use Phoenix.LiveView
  
  def mount(_params, _session, socket) do
    if connected?(socket) do
      SpaceMouse.start_monitoring()
      SpaceMouse.subscribe()
    end
    
    {:ok, assign(socket, motion: %{x: 0, y: 0, z: 0}, connected: false)}
  end
  
  def handle_info({:spacemouse_connected, _info}, socket) do
    {:noreply, assign(socket, connected: true)}
  end
  
  def handle_info({:spacemouse_motion, motion}, socket) do
    {:noreply, assign(socket, motion: motion)}
  end
  
  def render(assigns) do
    ~H"""
    <div>
      <h1>SpaceMouse Control</h1>
      
      <div class="status">
        Status: <%= if @connected, do: "Connected", else: "Disconnected" %>
      </div>
      
      <div class="motion">
        <div>X: <%= @motion.x %></div>
        <div>Y: <%= @motion.y %></div>
        <div>Z: <%= @motion.z %></div>
      </div>
      
      <button phx-click="toggle_led">Toggle LED</button>
    </div>
    """
  end
  
  def handle_event("toggle_led", _, socket) do
    # Toggle LED state
    {:ok, current_state} = SpaceMouse.get_led_state()
    new_state = if current_state == :on, do: :off, else: :on
    SpaceMouse.set_led(new_state)
    
    {:noreply, socket}
  end
end
```

## Error Handling

### Connection Errors

```elixir
case SpaceMouse.start_monitoring() do
  :ok ->
    IO.puts("Monitoring started successfully")
    
  {:error, :platform_not_supported} ->
    IO.puts("This platform is not supported")
    
  {:error, :permission_denied} ->
    IO.puts("USB permission denied. Check udev rules on Linux.")
    
  {:error, reason} ->
    IO.puts("Failed to start monitoring: #{inspect(reason)}")
end
```

### Event Processing Errors

```elixir
def handle_info({:spacemouse_motion, motion}, state) do
  try do
    process_motion(motion)
  rescue
    error ->
      Logger.error("Motion processing error: #{inspect(error)}")
  end
  
  {:noreply, state}
end
```

### Device Disconnection Handling

```elixir
def handle_info({:spacemouse_disconnected, _info}, state) do
  IO.puts("Device disconnected - cleaning up...")
  
  # Clean up any device-dependent state
  new_state = %{state | camera_active: false}
  
  # Auto-reconnection is handled automatically
  {:noreply, new_state}
end
```

## Performance Tips

### Motion Event Filtering

```elixir
# Only process significant motion to reduce CPU usage
def handle_info({:spacemouse_motion, motion}, state) do
  if significant_motion?(motion) do
    process_motion(motion)
  end
  
  {:noreply, state}
end

defp significant_motion?(%{x: x, y: y, z: z}) do
  # With ±1.0 range, 0.04-0.06 is a good threshold for significant motion
  abs(x) > 0.05 or abs(y) > 0.05 or abs(z) > 0.05
end
```

### Event Batching

```elixir
# Batch multiple motion events for smoother animation
def handle_info({:spacemouse_motion, motion}, state) do
  new_state = %{state | pending_motion: motion}
  
  # Cancel previous timer and set new one
  if state.motion_timer do
    Process.cancel_timer(state.motion_timer)
  end
  
  timer = Process.send_after(self(), :process_motion, 16)  # ~60 FPS
  
  {:noreply, %{new_state | motion_timer: timer}}
end

def handle_info(:process_motion, state) do
  if state.pending_motion do
    process_motion(state.pending_motion)
  end
  
  {:noreply, %{state | pending_motion: nil, motion_timer: nil}}
end
```

## Troubleshooting

### No Events Received

1. **Check connection**:
   ```elixir
   SpaceMouse.connected?()  # Should return true
   ```

2. **Verify subscription**:
   ```elixir
   SpaceMouse.subscribe()  # Call again to ensure subscription
   ```

3. **Check platform**:
   ```elixir
   SpaceMouse.platform_info()  # Verify correct platform detected
   ```

### LED Control Not Working

LED control may not be supported on all platforms:

```elixir
case SpaceMouse.set_led(:on) do
  :ok -> IO.puts("LED control works")
  {:error, :not_supported} -> IO.puts("LED control not available")
  {:error, reason} -> IO.puts("LED error: #{reason}")
end
```

### Permission Issues (Linux)

If you get permission errors on Linux, check udev rules:

```bash
# Check if udev rule exists
ls /etc/udev/rules.d/*spacemouse*

# Add udev rule for SpaceMouse
sudo nano /etc/udev/rules.d/99-spacemouse.rules

# Content:
SUBSYSTEM=="usb", ATTRS{idVendor}=="256f", ATTRS{idProduct}=="c635", MODE="0666"

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

### macOS Security Warnings

On macOS, you may see security warnings about the C helper program. This is normal - the program only accesses HID devices and has no network or filesystem access.

This usage guide provides comprehensive examples for integrating SpaceMouse into your Elixir applications!
