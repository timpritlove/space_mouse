# SpaceMouse Demos

This document describes the available demonstration programs for the SpaceMouse library.

## Demo Programs

### 1. API Demo (`lib/space_mouse/demo/api_demo.ex`)

**Purpose**: Demonstrates the clean SpaceMouse API usage patterns.

**Features**:
- Basic API function examples
- Event subscription and handling
- LED control examples
- Error handling patterns
- Best practices for real applications

**Run**: `SpaceMouse.Demo.ApiDemo.basic_demo()`

### 2. Complete Demo (`lib/space_mouse/demo/complete_demo.ex`)

**Purpose**: Comprehensive demonstration of all SpaceMouse features.

**Features**:
- Device connection/disconnection handling
- Real-time 6DOF motion tracking with normalized values (-1.0 to +1.0)
- Button event handling and state tracking
- LED control with state change events
- Automatic reconnection demo
- Performance statistics
- Interactive LED control (Button 1 toggles LED)

**Run**: `SpaceMouse.Demo.CompleteDemo.run()`

### 3. Motion Tracker (`lib/space_mouse/demo/motion_tracker.ex`)

**Purpose**: Focused motion tracking demonstration with visual feedback.

**Features**:
- Clean, focused 6DOF motion display
- Visual progress bars for each axis
- Motion magnitude calculations
- Directional descriptions (e.g., "Moving RIGHT", "Pitching UP")
- Coordinate system explanation
- Real-time motion analysis

**Run**: `SpaceMouse.Demo.MotionTracker.start()`

## Quick Start

To try the demos:

```elixir
# Start iex
iex -S mix

# Run the complete demo (recommended first try)
iex> SpaceMouse.Demo.CompleteDemo.run()

# Or try the focused motion tracker
iex> SpaceMouse.Demo.MotionTracker.start()

# Or explore the API patterns
iex> SpaceMouse.Demo.ApiDemo.basic_demo()
```

## Educational Value

- **API Demo**: Learn the proper API usage patterns
- **Complete Demo**: See all features working together in a real application
- **Motion Tracker**: Understand the 6DOF coordinate system and motion data structure

## Development History

During development, this project included experimental code for:

- USB device claiming analysis on macOS  
- USB metadata exploration techniques
- HID report descriptor parsing logic

This experimental code has been removed to maintain a clean, production-ready codebase. The key insights from this research are documented in the `docs/` directory, particularly `docs/usb_protocol.md` and `docs/architecture.md`.
