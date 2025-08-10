# SpaceMouse 6DOF System Documentation

## Overview

This document provides comprehensive technical details about how the SpaceMouse 6 Degrees of Freedom (6DOF) input system works, based on empirical testing and analysis of the SpaceMouse Compact.

## 6DOF Coordinate System

The SpaceMouse provides simultaneous input across six axes of movement:

### Translation Axes
- **X**: Left/Right movement
- **Y**: Forward/Back movement  
- **Z**: Up/Down movement

### Rotation Axes
- **RX**: Tilt (pitch) - forward/back rotation
- **RY**: Roll - left/right rotation
- **RZ**: Twist (yaw) - clockwise/counterclockwise rotation

## Value Ranges

The SpaceMouse library automatically normalizes raw hardware values to a standardized range:

### Library Output (Normalized)

| Axis | Description | Minimum | Maximum | Total Range |
|------|-------------|---------|---------|-------------|
| **X** | Left/Right | -1.0 | +1.0 | 2.0 |
| **Y** | Forward/Back | -1.0 | +1.0 | 2.0 |
| **Z** | Up/Down | -1.0 | +1.0 | 2.0 |
| **RX** | Tilt | -1.0 | +1.0 | 2.0 |
| **RY** | Roll | -1.0 | +1.0 | 2.0 |
| **RZ** | Twist | -1.0 | +1.0 | 2.0 |

### Raw Hardware Values (Internal)

| Axis | Description | Minimum | Maximum | Total Range |
|------|-------------|---------|---------|-------------|
| **X** | Left/Right | -350 | +350 | 700 |
| **Y** | Forward/Back | -350 | +350 | 700 |
| **Z** | Up/Down | -350 | +350 | 700 |
| **RX** | Tilt | -350 | +350 | 700 |
| **RY** | Roll | -350 | +350 | 700 |
| **RZ** | Twist | -350 | +350 | 700 |

### Key Characteristics

- **Library Data Type**: 64-bit floats (-1.0 to +1.0)
- **Hardware Data Type**: Signed 16-bit integers (-350 to +350)
- **Neutral Position**: `0.0` for all axes (library), `0` for hardware
- **Scaling Factor**: `1.0 / 350.0` (hardware to library conversion)
- **Resolution**: 700 discrete steps per axis, maintaining precision after scaling
- **Precision**: Single-unit increments

## Event Structure

### Motion Events

Each motion event contains a complete 6DOF state snapshot:

```elixir
{:spacemouse_motion, %{
  x: -0.357,    # Translation X: left/right (was -125)
  y: 0.571,     # Translation Y: forward/back (was 200)
  z: 0.0,       # Translation Z: up/down (was 0)
  rx: 0.129,    # Rotation X: tilt (was 45)
  ry: -0.086,   # Rotation Y: roll (was -30)
  rz: 0.429     # Rotation Z: twist (was 150)
}}
```

### Event Characteristics

- **Single Event Type**: All 6 axes are reported together in one event
- **Complete State**: Each event contains the current value for all 6 axes
- **Selective Activity**: Individual axes can be zero (inactive) or non-zero (active)
- **Real-time Updates**: Events are generated at hardware polling frequency

## Hardware Behavior

### Polling Rate
- **Maximum Event Rate**: ~375 events/second
- **Typical Active Rate**: 250-350 events/second during movement
- **Idle Behavior**: Zero events when device is untouched

### Sensitivity
- **Motion Detection**: Extremely sensitive to micro-movements
- **Dead Zone**: No built-in hardware dead zone
- **Noise Floor**: Minimal sensor noise at rest
- **Response Time**: Immediate (<3ms) response to input changes

### Multi-Axis Operation
- **Simultaneous Input**: All 6 axes can be active simultaneously
- **Independent Values**: Each axis operates independently
- **Combined Movements**: Natural for complex 6DOF manipulations
- **No Cross-Talk**: Minimal interference between axes

## Software Implementation Details

### Value Processing
```elixir
# Raw values come directly from hardware
%{x: x, y: y, z: z, rx: rx, ry: ry, rz: rz} = motion_event

# Application-level scaling example
scale_factor = 1000.0 / 350.0  # Scale to ±1000 range
scaled_x = x * scale_factor
```

### Dead Zone Implementation
Since the hardware provides no dead zone, applications typically implement software dead zones:

```elixir
def apply_dead_zone(value, threshold \\ 5) do
  if abs(value) < threshold, do: 0, else: value
end
```

### Filtering Considerations
- **High Frequency**: Events arrive at ~375Hz maximum
- **Noise Filtering**: May want low-pass filtering for smooth motion
- **Gesture Recognition**: Temporal analysis across multiple events
- **Rate Limiting**: Applications may need to downsample for performance

## Performance Characteristics

### Event Statistics (from testing)
- **Total Range Coverage**: ±350 achievable on all axes
- **Event Generation**: 97%+ of events contain non-zero motion data
- **Latency**: Hardware-to-software latency <5ms
- **Reliability**: No dropped events observed during testing
- **Precision**: Stable values at all force levels

### Recommended Applications Settings
- **Dead Zone**: 3-10 units (depending on application sensitivity needs)
- **Scaling**: Linear scaling works well across the full range
- **Smoothing**: Optional low-pass filter for applications requiring smooth motion
- **Update Rate**: 60-120Hz sufficient for most applications (downsample from 375Hz)

## Comparison with Other 6DOF Devices

The SpaceMouse Compact's ±350 range provides:
- **High Resolution**: 700 steps per axis
- **Symmetric Operation**: Equal positive/negative ranges
- **Professional Grade**: Suitable for CAD, 3D modeling, and precision applications
- **Low Latency**: Real-time response suitable for interactive applications

## Integration Guidelines

### For Applications
1. **Handle Complete Events**: Process all 6 axes from each event
2. **Implement Dead Zones**: Add software dead zones for user comfort
3. **Scale Appropriately**: Convert ±350 range to application-specific units
4. **Consider Filtering**: Add temporal filtering for smooth motion if needed
5. **Respect User Intent**: All axes can be active simultaneously

### For Libraries
1. **Preserve Raw Values**: Don't apply filtering at the library level
2. **Maintain Event Structure**: Keep all 6 axes in single events
3. **Document Ranges**: Clearly specify the ±350 range in API documentation
4. **Provide Examples**: Show how to handle multi-axis events

## Testing Methodology

The values and characteristics documented here were determined through:
- **Comprehensive Range Testing**: 130+ seconds of maximum force application in all directions
- **Event Rate Analysis**: Monitoring of 30,000+ motion events
- **Multi-Axis Testing**: Simultaneous movement across multiple axes
- **Precision Verification**: Single-unit increment testing
- **Performance Profiling**: Real-time event processing analysis

This ensures the documented behavior reflects real-world usage patterns and hardware capabilities.
