# SpaceMouse Architecture

This document describes the architecture of the SpaceMouse library, which provides cross-platform SpaceMouse device support for Elixir applications.

## Overview

SpaceMouse is designed with a layered architecture that cleanly separates platform-specific implementation details from the core application logic. This allows the library to work across different operating systems with different access methods while presenting a unified API to developers.

## Architecture Layers

```
┌─────────────────────────────────────────────────────────────┐
│                     Application Layer                       │
│           (Your Elixir application using SpaceMouse)   │
└─────────────────────────────────────────────────────────────┘
                                 │
┌─────────────────────────────────────────────────────────────┐
│                      Public API Layer                      │
│                  SpaceMouse.Core.Api                   │
│  • start_monitoring()  • set_led()  • subscribe()         │
└─────────────────────────────────────────────────────────────┘
                                 │
┌─────────────────────────────────────────────────────────────┐
│                    Core Device Layer                       │
│               SpaceMouse.Core.Device                   │
│  • Connection management  • Event distribution             │
│  • Platform abstraction  • State management               │
└─────────────────────────────────────────────────────────────┘
                                 │
┌─────────────────────────────────────────────────────────────┐
│                   Platform Layer                           │
│           SpaceMouse.Platform.Behaviour               │
├─────────────────┬─────────────────┬─────────────────────────┤
│      macOS      │      Linux      │       Windows           │
│   IOKit HID     │   Direct USB    │       HID API           │
│   (via C port)  │   (libusb)      │    (via C bridge)       │
└─────────────────┴─────────────────┴─────────────────────────┘
                  │                 │                         │
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────────┐
│   C HID Reader  │ │   Elixir USB    │ │   C HID Bridge      │
│   (IOKit)       │ │   (Direct)      │ │   (Windows API)     │
└─────────────────┘ └─────────────────┘ └─────────────────────┘
```

## Core Components

### 1. Public API (`SpaceMouse.Core.Api`)

The main interface for external applications. Provides simple, clean functions:

- **Device Management**: `start_monitoring()`, `stop_monitoring()`
- **Event Subscription**: `subscribe()`, `unsubscribe()`
- **LED Control**: `set_led(:on/:off)`, `get_led_state()`
- **Status Queries**: `connected?()`, `connection_state()`

### 2. Core Device (`SpaceMouse.Core.Device`)

The central GenServer that manages device state and coordinates between the platform layer and application layer:

- **Platform Selection**: Automatically chooses the correct platform implementation
- **State Management**: Tracks connection status, LED state, motion data
- **Event Distribution**: Forwards platform events to subscribers
- **Auto-reconnection**: Handles device disconnection/reconnection

### 3. Platform Behaviour (`SpaceMouse.Platform.Behaviour`)

Defines the interface that all platform implementations must follow:

```elixir
@callback platform_init(opts :: keyword()) :: {:ok, term()} | {:error, term()}
@callback start_monitoring(state :: term()) :: {:ok, term()} | {:error, term()}
@callback stop_monitoring(state :: term()) :: :ok
@callback send_led_command(state :: term(), command :: :on | :off) :: {:ok, term()} | {:error, term()}
@callback get_led_state(state :: term()) :: {:ok, :on | :off | :unknown} | {:error, term()}
@callback device_connected?(state :: term()) :: {:ok, boolean()} | {:error, term()}
@callback platform_info() :: %{platform: atom(), method: atom(), version: String.t()}
```

## Platform Implementations

### macOS Implementation (`SpaceMouse.Platform.MacOS.HidBridge`)

**Why needed**: macOS's kernel HID driver claims SpaceMouse devices, preventing direct USB access.

**Solution**: Uses IOKit HID Manager via a minimal C program that communicates through Erlang ports.

**Components**:
- `HidBridge`: Elixir module implementing the platform behaviour
- `PortManager`: Manages the C program lifecycle and parses its output
- `hid_reader.c`: Minimal C program using IOKit HID Manager

**Communication Flow**:
1. Elixir starts C program via port
2. C program outputs structured events: `STATUS:ready`, `MOTION:x=123,y=456`, `BUTTON:id=1,state=pressed`
3. PortManager parses events and forwards to Core Device
4. Core Device distributes to subscribers

### Linux Implementation (Planned)

**Why simpler**: Linux allows direct USB access to HID devices.

**Solution**: Direct libusb access through the Erlang `:usb` package.

**Components**:
- `DirectUsb`: Elixir module using `:usb` package directly
- No C bridge needed

### Windows Implementation (Planned)

**Why similar to macOS**: Windows also has kernel driver claiming.

**Solution**: Windows HID API via C bridge (similar to macOS approach).

## Message Flow

### Device Connection
```
C Program → PortManager → Core Device → Subscribers
   │              │            │             │
   └─ STATUS:     └─ {:hid_     └─ {:space    └─ Application
      device_        event,        mouse_       receives
      connected      ...}          connected,   events
                                   ...}
```

### Motion Events
```
C Program → PortManager → Core Device → Subscribers
   │              │            │             │
   └─ MOTION:     └─ {:hid_     └─ {:space    └─ Application
      x=123,y=456    event,        mouse_       processes
                     ...}          motion,      motion
                                   %{x: 123,
                                     y: 456}}
```

### LED Control
```
Application → Core Device → Platform → (varies by platform)
     │             │            │              │
     └─ set_led    └─ send_led  └─ macOS:      └─ USB Control
        (:on)         _command     Simulated      Transfer
                      (:on)        (future:       (Linux)
                                   USB control)
```

## State Management

### Core Device State
```elixir
%State{
  platform_module: SpaceMouse.Platform.MacOS.HidBridge,
  platform_state: %HidBridge.State{...},
  connection_state: :connected,  # :disconnected | :connecting | :connected | :error
  subscribers: MapSet.new([pid1, pid2]),
  led_state: :on,               # :on | :off | :unknown
  last_motion: %{x: 0.0, y: 0.0, z: 0.0, rx: 0.0, ry: 0.0, rz: 0.0},  # ±1.0 range per axis
  last_button_state: %{1 => :released, 2 => :pressed},
  auto_reconnect: true
}
```

### Platform State (macOS)
```elixir
%HidBridge.State{
  port_manager: #PID<0.123.0>,
  owner_pid: #PID<0.100.0>,
  device_connected: true,
  led_state: :on
}
```

## Error Handling & Fault Tolerance

### Supervision Tree
```
SpaceMouse.Application
└── SpaceMouse.Core.Supervisor
    └── SpaceMouse.Core.Device
        └── (Platform manages its own processes)
```

### Recovery Strategies

1. **C Program Crash**: PortManager detects exit and notifies Core Device
2. **Port Manager Crash**: Core Device detects and can restart monitoring  
3. **Core Device Crash**: Supervisor restarts it, applications re-subscribe
4. **Device Disconnection**: Auto-reconnection attempts (configurable)

## Performance Characteristics

### Event Throughput
- **Motion Events**: ~375 Hz maximum hardware rate, typically 250-350 Hz during movement
- **Button Events**: As fast as user can press (hardware debounced)
- **LED Events**: Emitted on state changes (on/off transitions)
- **Latency**: <5ms from device to application
- **6DOF Data**: All axes (X,Y,Z,RX,RY,RZ) in single events with ±1.0 float value range

### Memory Usage
- **Core System**: ~1-2 MB
- **C Program**: ~100 KB
- **Event Buffers**: Minimal (no buffering by design)

### CPU Usage
- **Idle**: <1% CPU
- **Active Motion**: <5% CPU
- **C Program**: <1% CPU

## Configuration & Extensibility

### Platform Selection
Automatic based on `:os.type()`:
- `{:unix, :darwin}` → macOS implementation
- `{:unix, :linux}` → Linux implementation (future)
- `{:win32, _}` → Windows implementation (future)

### Adding New Platforms
1. Implement `SpaceMouse.Platform.Behaviour`
2. Add platform detection in `Core.Device.select_platform/0`
3. Test with demo applications

### Event Filtering
Applications can filter events by subscribing and pattern matching:
```elixir
receive do
  {:spacemouse_motion, %{x: x}} when abs(x) > 100 ->
    # Only handle significant X movement
  {:spacemouse_button, %{id: 1, state: :pressed}} ->
    # Only handle button 1 presses
end
```

## Security Considerations

### C Program Safety
- Minimal C code with limited system access
- No network communication
- Read-only device access
- Sandboxed through Erlang port isolation

### Permission Requirements
- **macOS**: No special permissions (uses IOKit HID)
- **Linux**: May require device permissions or udev rules
- **Windows**: No special permissions expected

### Data Validation
- All C program output is parsed and validated
- Invalid data is logged and discarded
- No executable code from external sources

## Testing Strategy

### Unit Tests
- Core Device state management
- Platform behaviour compliance
- Event parsing and distribution

### Integration Tests
- End-to-end event flow
- Platform switching
- Error recovery scenarios

### Demo Applications
- `ApiDemo`: Basic functionality demonstration
- `MotionDemo`: Real-time motion tracking
- `InteractiveDemo`: LED control and status

## Future Enhancements

### Planned Features
1. **Linux Support**: Direct USB access via libusb
2. **Windows Support**: HID API via C bridge
3. **Enhanced LED Control**: Brightness, RGB (device dependent)
4. **Device Configuration**: Sensitivity, button mapping
5. **Multiple Device Support**: Multiple SpaceMice simultaneously

### API Stability
- Core API is designed for stability
- Platform-specific details hidden from applications
- Backward compatibility maintained across versions
