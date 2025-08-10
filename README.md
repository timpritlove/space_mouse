# SpaceNavigator

Cross-platform SpaceMouse device support for Elixir applications.

[![Hex.pm](https://img.shields.io/hexpm/v/space_navigator.svg)](https://hex.pm/packages/space_navigator)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/space_navigator)

## Overview

SpaceNavigator is an Elixir library that provides unified access to 3Dconnexion SpaceMouse devices across different operating systems. It handles the platform-specific complexities of USB/HID communication and presents a clean, consistent API for real-time 6DOF (six degrees of freedom) input and device control.

## Features

- 🎮 **Real-time 6DOF Motion Tracking**: X, Y, Z translation + rotation
- 🔘 **Button Event Handling**: Press/release events for all device buttons  
- 💡 **LED Control**: Turn device LED on/off (platform dependent)
- 🔄 **Auto-reconnection**: Automatic device detection and reconnection
- 🏗️ **Cross-platform**: macOS (implemented), Linux (planned), Windows (planned)
- ⚡ **Low Latency**: <5ms from device to application
- 🛡️ **Fault Tolerant**: Robust error handling and recovery

## Quick Start

### Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:space_navigator, "~> 1.0"}
  ]
end
```

### Basic Usage

```elixir
# Start monitoring for SpaceMouse devices
SpaceNavigator.start_monitoring()

# Subscribe to events
SpaceNavigator.subscribe()

# Handle events
receive do
  {:spacemouse_connected, _info} ->
    IO.puts("SpaceMouse connected!")
    SpaceNavigator.set_led(:on)
    
  {:spacemouse_motion, %{x: x, y: y, z: z}} ->
    IO.puts("Motion: X=#{x}, Y=#{y}, Z=#{z}")
    
  {:spacemouse_button, %{id: 1, state: :pressed}} ->
    IO.puts("Button 1 pressed!")
end
```

## Supported Devices

Currently tested with:
- 3Dconnexion SpaceMouse Compact (VID: 0x256F, PID: 0xC635)

Other 3Dconnexion devices should work with minimal modifications.

## Platform Support

| Platform | Status | Access Method | Requirements |
|----------|--------|---------------|--------------|
| **macOS** | ✅ Implemented | IOKit HID Manager | Xcode Command Line Tools |
| **Linux** | 🔄 Planned | Direct libusb | udev rules for permissions |
| **Windows** | 🔄 Planned | Windows HID API | Windows SDK |

### macOS Implementation

macOS requires a special approach because the kernel HID driver claims SpaceMouse devices, preventing direct USB access. Our solution uses a minimal C program that communicates with Elixir via IOKit HID Manager.

## Architecture

```
Application Layer
       ↓
  Public API (SpaceNavigator.Core.Api)
       ↓ 
  Core Device (SpaceNavigator.Core.Device)
       ↓
  Platform Layer (Behaviour-based)
       ↓
  Platform Implementation (macOS/Linux/Windows)
```

## Documentation

- 📚 [**Usage Guide**](docs/usage.md) - Complete API reference and examples
- 🏗️ [**Architecture**](docs/architecture.md) - System design and components  
- 🎮 [**6DOF System**](docs/spacemouse_6dof.md) - Complete 6DOF technical reference and value ranges
- 🔌 [**USB Protocol**](docs/usb_protocol.md) - Technical details of SpaceMouse communication
- 🖥️ [**Platform Support**](docs/platform_support.md) - Platform-specific implementations and workarounds

## Examples

### 3D Camera Control

```elixir
defmodule MyApp.CameraController do
  use GenServer
  
  def init(_) do
    SpaceNavigator.start_monitoring()
    SpaceNavigator.subscribe()
    {:ok, %{camera: {0, 0, 0}}}
  end
  
  def handle_info({:spacemouse_motion, motion}, state) do
    new_camera = update_camera_position(state.camera, motion)
    render_3d_scene(new_camera)
    {:noreply, %{state | camera: new_camera}}
  end
  
  defp update_camera_position({x, y, z}, %{x: dx, y: dy, z: dz}) do
    {x + dx * 0.01, y + dy * 0.01, z + dz * 0.01}
  end
end
```

### Phoenix LiveView Integration

```elixir
defmodule MyAppWeb.SpaceMouseLive do
  use Phoenix.LiveView
  
  def mount(_params, _session, socket) do
    if connected?(socket) do
      SpaceNavigator.start_monitoring()
      SpaceNavigator.subscribe()
    end
    
    {:ok, assign(socket, motion: %{x: 0, y: 0, z: 0})}
  end
  
  def handle_info({:spacemouse_motion, motion}, socket) do
    {:noreply, assign(socket, motion: motion)}
  end
  
  def render(assigns) do
    ~H"""
    <div class="spacemouse-display">
      <div>X: <%= @motion.x %></div>
      <div>Y: <%= @motion.y %></div>  
      <div>Z: <%= @motion.z %></div>
    </div>
    """
  end
end
```

## Demo Applications

The library includes several demo applications:

```bash
# Basic API demonstration
mix run -e "SpaceNavigator.Demo.ApiDemo.basic_demo()"

# Interactive demo with LED control
mix run -e "SpaceNavigator.Demo.ApiDemo.interactive_demo()"

# Motion tracking demo
mix run -e "SpaceNavigator.Demo.ApiDemo.motion_demo()"
```

## Development

### Building from Source

```bash
git clone https://github.com/yourorg/space_navigator.git
cd space_navigator
mix deps.get
mix compile
```

### Testing

```bash
# Run tests
mix test

# Run with your SpaceMouse connected
mix run -e "SpaceNavigator.Demo.ApiDemo.basic_demo()"
```

### Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add tests for new functionality
5. Commit your changes (`git commit -am 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## Code Organization

```
lib/space_navigator/
├── core/                    # Core system (clean API)
│   ├── api.ex              # Public API
│   ├── device.ex           # Main device abstraction
│   └── supervisor.ex       # Supervision tree
├── platform/               # Platform-specific implementations
│   ├── behaviour.ex        # Platform behaviour definition
│   ├── macos/              # macOS implementation
│   │   ├── hid_bridge.ex   # IOKit HID bridge (Elixir)
│   │   └── port_manager.ex # C process management
│   └── linux/              # Future Linux implementation
├── demo/                   # Demo applications
└── experimental/           # Research & testing code

priv/platform/
├── macos/                  # macOS-specific binaries
│   ├── hid_reader.c       # Minimal HID communication
│   ├── build.sh           # Build script
│   └── hid_reader         # Compiled binary
└── linux/                 # Future Linux binaries
```

## Technical Details

### Motion Data Format

6DOF motion data with ±1.0 value range:

```elixir
%{
  x: -0.351,   # Translation X (-1.0 to +1.0)
  y: 0.191,    # Translation Y (-1.0 to +1.0)
  z: -0.571,   # Translation Z (-1.0 to +1.0)
  rx: 0.129,   # Rotation X (-1.0 to +1.0)
  ry: -0.254,  # Rotation Y (-1.0 to +1.0)
  rz: 0.446    # Rotation Z (-1.0 to +1.0)
}
```

### Button Data Format

```elixir
%{
  id: 1,              # Button ID (1, 2, etc.)
  state: :pressed     # :pressed or :released
}
```

### LED Event Format

```elixir
%{
  from: :off,                    # Previous LED state (:on, :off, :unknown)
  to: :on,                       # New LED state (:on, :off)
  timestamp: 1640995200000       # System monotonic time in milliseconds
}
```

### Performance Characteristics

- **Event Rate**: ~375 Hz maximum (motion), event-driven (buttons)
- **Latency**: <5ms device to application
- **CPU Usage**: <5% during active use
- **Memory**: ~2MB total footprint
- **Resolution**: 700 discrete steps per axis (±1.0 normalized range, ±350 hardware range)

## Troubleshooting

### macOS

- **Security warnings**: Normal for C helper program, safe to allow
- **No events**: Ensure SpaceMouse is connected and recognized by macOS

### Linux (Future)

- **Permission denied**: Add udev rule for device permissions
- **Device not found**: Check if device is recognized by `lsusb`

### General

- **No motion events**: Try moving the SpaceMouse more significantly
- **Button events not working**: Verify your device has buttons and they're being pressed firmly

## Roadmap

### Version 1.1 (Planned)
- [ ] Linux support with direct libusb access
- [ ] Enhanced LED control (brightness levels)
- [ ] Device configuration API (sensitivity, dead zones)

### Version 1.2 (Planned)  
- [ ] Windows support
- [ ] Multiple device support
- [ ] Device-specific optimizations

### Version 2.0 (Future)
- [ ] RGB LED support (device dependent)
- [ ] Custom button mapping
- [ ] Gesture recognition
- [ ] Device calibration tools

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- 3Dconnexion for creating excellent input devices
- The Elixir community for guidance and support
- Contributors to the libusb and IOKit documentation

## Support

- 📖 [Documentation](https://hexdocs.pm/space_navigator)
- 🐛 [Issue Tracker](https://github.com/yourorg/space_navigator/issues)
- 💬 [Discussions](https://github.com/yourorg/space_navigator/discussions)

---

**Made with ❤️ for the Elixir community**