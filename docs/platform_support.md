# Platform Support and Workarounds

This document explains the platform-specific implementations and workarounds required to access SpaceMouse devices across different operating systems.

## Overview

SpaceMouse devices are HID (Human Interface Device) class USB devices. While this should make them uniformly accessible across platforms, different operating systems handle HID devices differently, requiring platform-specific solutions.

## Platform Comparison

| Platform | Access Method | Complexity | Status |
|----------|---------------|------------|---------|
| **macOS** | IOKit HID Manager (C bridge) | High | ✅ Implemented |
| **Linux** | Direct libusb access | Low | 🔄 Planned |
| **Windows** | Windows HID API (C bridge) | Medium | 🔄 Planned |

## macOS Implementation

### The Problem: Kernel Driver Claiming

macOS automatically loads a generic HID driver (`IOHIDFamily.kext`) that claims all HID devices when they connect. This prevents user-space applications from directly accessing the USB interface through libusb.

#### Evidence of Claiming

```bash
# Check USB device status
$ ioreg -p IOUSB -l | grep -A 20 "SpaceMouse Compact"
+-o SpaceMouse Compact@01100000 <class IOUSBHostDevice, id 0x1000008c1>
  {
    "kUSBCurrentConfiguration" = 1
    "IOCFPlugInTypes" = {"9dc7b780-9ec0-11d4-a54f-000a27052861"="IOUSBHostFamily.kext"}
    ...
  }
```

#### Failed Direct USB Access

```elixir
# Attempting to claim the interface fails
iex> :usb.claim_interface(device_handle, 0)
{:error, :access}

# Attempting to access endpoints fails  
iex> :usb.interrupt_transfer(device_handle, 0x81, 8, 1000)
{:error, :not_found}
```

### The Solution: IOKit HID Manager

Instead of fighting the kernel driver, we cooperate with it using macOS's IOKit HID Manager API. This provides a higher-level interface that works through the kernel driver.

#### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Elixir Application                       │
└─────────────────────────────────────────────────────────────┘
                                 │ Port Communication
                                 │ (structured strings)
┌─────────────────────────────────────────────────────────────┐
│                    C Helper Program                        │
│                    (hid_reader.c)                          │
│                                                             │
│  • IOHIDManagerCreate()                                    │
│  • IOHIDManagerSetDeviceMatching()                         │
│  • IOHIDManagerRegisterInputValueCallback()                │
│  • CFRunLoopRun()                                          │
└─────────────────────────────────────────────────────────────┘
                                 │ IOKit HID Manager API
                                 │
┌─────────────────────────────────────────────────────────────┐
│                    macOS Kernel                            │
│                   IOHIDFamily.kext                         │
└─────────────────────────────────────────────────────────────┘
                                 │ USB Communication
                                 │
┌─────────────────────────────────────────────────────────────┐
│                    SpaceMouse Device                       │
└─────────────────────────────────────────────────────────────┘
```

#### C Program Implementation

**File**: `priv/platform/macos/hid_reader.c`

**Purpose**: Minimal C program that uses IOKit to access SpaceMouse events and outputs structured data to stdout for Elixir to parse.

**Key Functions**:

```c
// Device discovery
static CFMutableDictionaryRef create_spacemouse_matching_dict() {
    CFMutableDictionaryRef dict = CFDictionaryCreateMutable(...);
    CFNumberRef vendor_id = CFNumberCreate(..., 0x256F);  // 3Dconnexion
    CFDictionarySetValue(dict, CFSTR(kIOHIDVendorIDKey), vendor_id);
    return dict;
}

// Event processing
static void input_callback(void *context, IOReturn result, void *sender, IOHIDValueRef value) {
    IOHIDElementRef element = IOHIDValueGetElement(value);
    uint32_t usage_page = IOHIDElementGetUsagePage(element);
    uint32_t usage = IOHIDElementGetUsage(element);
    CFIndex int_value = IOHIDValueGetIntegerValue(value);
    
    // Motion data (Generic Desktop usage page = 1)
    if (usage_page == 1 && usage >= 48 && usage <= 53) {
        printf("MOTION:%s=%ld\n", axis_name(usage), int_value);
    }
    
    // Button data (Button usage page = 9)  
    if (usage_page == 9) {
        printf("BUTTON:id=%d,state=%s\n", usage, int_value ? "pressed" : "released");
    }
}
```

**Communication Protocol**:
- `STATUS:ready` - C program initialized
- `STATUS:device_connected` - SpaceMouse detected
- `STATUS:device_disconnected` - SpaceMouse removed
- `MOTION:x=123` - Single axis motion event
- `BUTTON:id=1,state=pressed` - Button event

#### Elixir Port Management

**File**: `lib/space_mouse/platform/macos/port_manager.ex`

**Purpose**: Manages the C program lifecycle and parses its structured output.

**Key Responsibilities**:
- Start/stop the C program as an Erlang port
- Parse structured output into Elixir events
- Handle process crashes and restarts
- Forward events to the core device manager

**Example Parsing**:
```elixir
defp parse_hid_output({:eol, line}) do
  case String.split(line, ":", parts: 2) do
    ["STATUS", message] ->
      {:ok, %{type: :status, message: message}}
      
    ["MOTION", params] ->
      # Parse "x=123,y=456" format
      data = parse_motion_params(params)
      {:ok, %{type: :motion, data: data}}
      
    ["BUTTON", params] ->
      # Parse "id=1,state=pressed" format  
      data = parse_button_params(params)
      {:ok, %{type: :button, data: data}}
  end
end
```

#### LED Control Limitation

**Current Status**: LED control is **simulated** in the macOS implementation.

**Reason**: IOKit HID Manager primarily provides input events. Output control (like LED commands) would require:
1. Additional IOKit APIs (`IOHIDDeviceSetReport`)
2. More complex C program logic
3. USB control transfer implementation

**Future Enhancement**: LED control can be added by extending the C program to handle output reports:

```c
// Future LED control implementation
IOReturn set_led_state(IOHIDDeviceRef device, bool on) {
    uint8_t report_data[2] = {0x04, on ? 0x01 : 0x00};  // Report ID 4
    return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 4, report_data, sizeof(report_data));
}
```

### Building and Deployment

**Build Process**:
```bash
cd priv/platform/macos
./build.sh
```

**Requirements**:
- Xcode Command Line Tools (for `clang`)
- IOKit framework (included with macOS)
- CoreFoundation framework (included with macOS)

**Distribution**: The compiled C program is included in the Elixir application's `priv` directory and automatically deployed with the application.

## Linux Implementation (Planned)

### The Advantage: Direct USB Access

Linux typically allows direct USB access to HID devices, especially with proper permissions. This makes the implementation much simpler.

#### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Elixir Application                       │
└─────────────────────────────────────────────────────────────┘
                                 │ Direct API calls
                                 │
┌─────────────────────────────────────────────────────────────┐
│                    Erlang :usb Package                     │
│                      (libusb wrapper)                      │
└─────────────────────────────────────────────────────────────┘
                                 │ libusb API
                                 │
┌─────────────────────────────────────────────────────────────┐
│                    Linux Kernel                            │
│                   USB/HID Subsystem                        │
└─────────────────────────────────────────────────────────────┘
                                 │ USB Communication
                                 │
┌─────────────────────────────────────────────────────────────┐
│                    SpaceMouse Device                       │
└─────────────────────────────────────────────────────────────┘
```

#### Expected Implementation

**File**: `lib/space_mouse/platform/linux/direct_usb.ex`

**Direct USB Access**:
```elixir
defmodule SpaceMouse.Platform.Linux.DirectUsb do
  @behaviour SpaceMouse.Platform.Behaviour
  
  def platform_init(opts) do
    # Initialize USB context
    {:ok, %State{owner_pid: opts[:owner_pid]}}
  end
  
  def start_monitoring(state) do
    # Find and open SpaceMouse device
    case find_spacemouse_device() do
      {:ok, device} ->
        {:ok, handle} = :usb.open(device)
        :ok = :usb.claim_interface(handle, 0)
        
        # Start reading thread
        pid = spawn_link(fn -> read_loop(handle, state.owner_pid) end)
        
        {:ok, %{state | device_handle: handle, reader_pid: pid}}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp read_loop(handle, owner_pid) do
    case :usb.interrupt_transfer(handle, 0x81, 8, 1000) do
      {:ok, data} ->
        event = parse_hid_report(data)
        send(owner_pid, {:hid_event, event})
        read_loop(handle, owner_pid)
        
      {:error, :timeout} ->
        read_loop(handle, owner_pid)  # Continue on timeout
        
      {:error, reason} ->
        send(owner_pid, {:device_error, reason})
    end
  end
end
```

#### Required Permissions

**udev Rule** (`/etc/udev/rules.d/99-spacemouse.rules`):
```
# Allow non-root access to SpaceMouse devices
SUBSYSTEM=="usb", ATTRS{idVendor}=="256f", ATTRS{idProduct}=="c635", MODE="0666", GROUP="plugdev"

# Or more restrictive - specific user group
SUBSYSTEM=="usb", ATTRS{idVendor}=="256f", ATTRS{idProduct}=="c635", MODE="0664", GROUP="spacemouse"
```

**Alternative: Run with sudo** (not recommended for production):
```bash
sudo mix run -e "SpaceMouse.start_monitoring()"
```

#### LED Control Implementation

LED control should work directly through USB control transfers:

```elixir
def send_led_command(state, command) do
  led_value = if command == :on, do: 1, else: 0
  report_data = <<0x04, led_value>>  # Report ID 4, LED state
  
  case :usb.control_transfer(
    state.device_handle,
    0x21,          # bmRequestType: Host to Device, Class, Interface
    0x09,          # bRequest: SET_REPORT
    0x0204,        # wValue: (Output Report << 8) | Report ID
    0,             # wIndex: Interface 0
    report_data,   # Data
    1000           # Timeout
  ) do
    {:ok, _} -> {:ok, %{state | led_state: command}}
    error -> error
  end
end
```

## Windows Implementation (Planned)

### The Challenge: Similar to macOS

Windows also loads generic HID drivers that claim devices, preventing direct USB access. However, Windows provides a robust HID API that's designed for user-space applications.

#### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Elixir Application                       │
└─────────────────────────────────────────────────────────────┘
                                 │ Port Communication
                                 │
┌─────────────────────────────────────────────────────────────┐
│                    C Helper Program                        │
│                   (hid_bridge.c)                           │
│                                                             │
│  • SetupDiGetClassDevs()                                   │
│  • HidD_GetAttributes()                                    │
│  • CreateFile()                                            │
│  • ReadFile() / WriteFile()                               │
└─────────────────────────────────────────────────────────────┘
                                 │ Windows HID API
                                 │
┌─────────────────────────────────────────────────────────────┐
│                    Windows Kernel                          │
│                    HID Class Driver                        │
└─────────────────────────────────────────────────────────────┘
                                 │ USB Communication
                                 │
┌─────────────────────────────────────────────────────────────┐
│                    SpaceMouse Device                       │
└─────────────────────────────────────────────────────────────┘
```

#### Expected C Implementation

**File**: `priv/platform/windows/hid_bridge.c`

**Key Windows APIs**:
```c
#include <windows.h>
#include <hidsdi.h>
#include <setupapi.h>

// Device discovery
HDEVINFO device_info_set = SetupDiGetClassDevs(
    &HidGuid, NULL, NULL, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE
);

// Open device
HANDLE device_handle = CreateFile(
    device_path, 
    GENERIC_READ | GENERIC_WRITE,
    FILE_SHARE_READ | FILE_SHARE_WRITE,
    NULL, OPEN_EXISTING, 0, NULL
);

// Read HID reports
BOOL result = ReadFile(device_handle, buffer, buffer_size, &bytes_read, NULL);

// Write HID reports (LED control)
BOOL result = WriteFile(device_handle, report_data, report_size, &bytes_written, NULL);
```

#### Elixir Port Management

Similar to macOS, using `SpaceMouse.Platform.Windows.PortManager` to manage the C program and parse its output.

## Platform Selection Logic

The core system automatically selects the appropriate platform implementation:

**File**: `lib/space_mouse/core/device.ex`

```elixir
defp select_platform do
  case :os.type() do
    {:unix, :darwin} ->
      SpaceMouse.Platform.MacOS.HidBridge
      
    {:unix, :linux} ->
      SpaceMouse.Platform.Linux.DirectUsb
      
    {:win32, _} ->
      SpaceMouse.Platform.Windows.HidBridge
      
    other ->
      raise "Unsupported platform: #{inspect(other)}"
  end
end
```

## Testing Across Platforms

### macOS Testing

```bash
# Verify C program works
cd priv/platform/macos
./hid_reader

# Test Elixir integration
mix run -e "SpaceMouse.Demo.ApiDemo.basic_demo()"
```

### Linux Testing (Future)

```bash
# Check device permissions
ls -l /dev/hidraw*
lsusb | grep 3Dconnexion

# Test direct USB access
mix run -e "SpaceMouse.Demo.ApiDemo.basic_demo()"
```

### Windows Testing (Future)

```cmd
REM Verify C program compiles
cl /I"C:\Program Files (x86)\Windows Kits\10\Include\shared" hid_bridge.c

REM Test Elixir integration
mix run -e "SpaceMouse.Demo.ApiDemo.basic_demo()"
```

## Performance Comparison

| Platform | Latency | CPU Usage | Memory | Complexity |
|----------|---------|-----------|---------|------------|
| **macOS** | ~5ms | Low | ~2MB | High |
| **Linux** | ~3ms | Very Low | ~1MB | Low |
| **Windows** | ~4ms | Low | ~2MB | Medium |

## Deployment Considerations

### macOS
- ✅ No special permissions required
- ✅ C program compiles with standard Xcode tools
- ⚠️ May trigger security warnings on first run

### Linux  
- ⚠️ Requires udev rule for non-root access
- ✅ Direct USB access is most efficient
- ✅ No external dependencies

### Windows
- ⚠️ Requires Windows SDK for compilation
- ✅ No special permissions required
- ⚠️ May require Visual C++ Redistributable

## Future Enhancements

### Cross-Platform Features
1. **Unified LED Control**: Implement LED control on all platforms
2. **Device Configuration**: Sensitivity, dead zones, button mapping
3. **Multiple Device Support**: Handle multiple SpaceMice simultaneously
4. **Hot-plug Detection**: Robust device connection/disconnection handling

### Platform-Specific Optimizations
1. **macOS**: Investigate IOKit output reports for LED control
2. **Linux**: Explore hidraw interface as alternative to libusb
3. **Windows**: Consider WinUSB for direct USB access
4. **All**: Implement asynchronous I/O for better performance

This platform support documentation explains why different approaches are needed for different operating systems and provides a roadmap for implementing full cross-platform support.
