# USB Protocol and SpaceMouse Communication

This document explains how SpaceMouse devices work at the USB level and the technical challenges involved in accessing them from user-space applications.

## SpaceMouse USB Device Characteristics

### Device Identification

**3Dconnexion SpaceMouse Compact** (used in this implementation):
- **Vendor ID**: `0x256F` (3Dconnexion)
- **Product ID**: `0xC635` (SpaceMouse Compact)
- **Device Class**: `0x03` (HID - Human Interface Device)
- **USB Version**: USB 2.0 (Full Speed)

### USB Device Descriptor

When the SpaceMouse connects, it presents this USB device descriptor:

```
Device Descriptor:
  bLength                18
  bDescriptorType         1
  bcdUSB                 2.00
  bDeviceClass            0  (Interface Specific)
  bDeviceSubClass         0
  bDeviceProtocol         0
  bMaxPacketSize0         8
  idVendor           0x256f  3Dconnexion
  idProduct          0xc635  SpaceMouse Compact
  bcdDevice            4.39
  iManufacturer           1  "3Dconnexion"
  iProduct                2  "SpaceMouse Compact"
  iSerialNumber           0  (none)
  bNumConfigurations      1
```

### Configuration Descriptor

The device has a single configuration with one interface:

```
Configuration Descriptor:
  bLength                 9
  bDescriptorType         2
  wTotalLength           34
  bNumInterfaces          1
  bConfigurationValue     1
  iConfiguration          0
  bmAttributes         0x80  (Bus Powered)
  MaxPower              100mA

Interface Descriptor:
  bLength                 9
  bDescriptorType         4
  bInterfaceNumber        0
  bAlternateSetting       0
  bNumEndpoints           1
  bInterfaceClass         3  HID
  bInterfaceSubClass      0  No Subclass
  bInterfaceProtocol      0  None
  iInterface              0

HID Class Descriptor:
  bLength                 9
  bDescriptorType        33
  bcdHID               1.11
  bCountryCode            0
  bNumDescriptors         1
  bDescriptorType        34  Report
  wDescriptorLength      60

Endpoint Descriptor:
  bLength                 7
  bDescriptorType         5
  bEndpointAddress     0x81  EP 1 IN
  bmAttributes            3  Interrupt
  wMaxPacketSize          8
  bInterval              10
```

## HID Report Structure

### HID Report Descriptor

The SpaceMouse uses a complex HID report descriptor that defines multiple report types:

```
Usage Page (Generic Desktop)
Usage (Multi-axis Controller)
Collection (Application)
  Report ID (1)
  Usage Page (Generic Desktop)
  Usage (X), Usage (Y), Usage (Z)           // Translation axes
  Usage (Rx), Usage (Ry), Usage (Rz)        // Rotation axes
  Logical Minimum (-32768)
  Logical Maximum (32767)
  Physical Minimum (-2048)
  Physical Maximum (2047)
  Unit (None)
  Report Size (16)
  Report Count (6)
  Input (Data, Variable, Absolute)
  
  Report ID (2)
  Usage Page (Button)
  Usage Minimum (1), Usage Maximum (2)      // Button 1, Button 2
  Logical Minimum (0), Logical Maximum (1)
  Report Size (1)
  Report Count (2)
  Input (Data, Variable, Absolute)
  Report Size (6)
  Report Count (1)
  Input (Constant)                          // Padding
  
  Report ID (3-26)
  [Various vendor-specific reports]
  ...
End Collection
```

### Report Types and Formats

#### Motion Report (Report ID 1)
6DOF motion data, 13 bytes total:
```
Byte 0:    Report ID (0x01)
Bytes 1-2: X translation (signed 16-bit, little-endian)
Bytes 3-4: Y translation (signed 16-bit, little-endian)  
Bytes 5-6: Z translation (signed 16-bit, little-endian)
Bytes 7-8: X rotation (signed 16-bit, little-endian)
Bytes 9-10: Y rotation (signed 16-bit, little-endian)
Bytes 11-12: Z rotation (signed 16-bit, little-endian)
```

#### Button Report (Report ID 2)
Button state data, 2 bytes total:
```
Byte 0: Report ID (0x02)
Byte 1: Button bitmask
  Bit 0: Button 1 state (1 = pressed, 0 = released)
  Bit 1: Button 2 state (1 = pressed, 0 = released)
  Bits 2-7: Unused (padding)
```

#### Output Reports (Report IDs 4-26)
Used for device control (LED, configuration, etc.):
```
Byte 0: Report ID (0x04-0x1A)
Bytes 1-N: Command-specific data
```

## USB Communication Methods

### Interrupt Transfers (Standard HID Method)

**Theory**: HID devices typically use interrupt endpoint transfers for real-time data.

**SpaceMouse Endpoint**: `0x81` (IN, Interrupt, 8-byte max packet)

**Expected Usage**:
```c
// Pseudo-code for direct USB access
int result = usb_interrupt_transfer(
    device_handle,
    0x81,           // Endpoint address
    buffer,         // Data buffer
    8,              // Buffer size
    1000            // Timeout (ms)
);
```

### Control Transfers (HID Reports)

**Alternative Method**: Access HID reports via control transfers using HID-specific requests.

**GET_REPORT Control Transfer**:
```c
// Pseudo-code for HID report access
int result = usb_control_transfer(
    device_handle,
    0x81,           // bmRequestType: Device to Host, Class, Interface
    0x01,           // bRequest: GET_REPORT
    (1 << 8) | 1,   // wValue: (Input Report << 8) | Report ID
    0,              // wIndex: Interface 0
    buffer,         // Data buffer
    13,             // Report size
    1000            // Timeout
);
```

**SET_REPORT Control Transfer** (for LED control):
```c
// Pseudo-code for LED control
uint8_t led_data[2] = {0x04, 0x01};  // Report ID 4, LED on
int result = usb_control_transfer(
    device_handle,
    0x21,           // bmRequestType: Host to Device, Class, Interface
    0x09,           // bRequest: SET_REPORT
    (2 << 8) | 4,   // wValue: (Output Report << 8) | Report ID
    0,              // wIndex: Interface 0
    led_data,       // Data buffer
    2,              // Data size
    1000            // Timeout
);
```

## Platform-Specific Challenges

### macOS: Kernel Driver Claiming

**Problem**: macOS automatically loads a generic HID driver for all HID devices, including the SpaceMouse. This kernel driver claims the device interface, preventing user-space applications from accessing it directly via libusb.

**Evidence**:
```bash
$ ioreg -p IOUSB -l | grep -A 20 "SpaceMouse Compact"
+-o SpaceMouse Compact@01100000 <class IOUSBHostDevice, id 0x1000008c1>
  {
    "kUSBCurrentConfiguration" = 1
    "IOCFPlugInTypes" = {"9dc7b780-9ec0-11d4-a54f-000a27052861"="IOUSBHostFamily.kext"}
    ...
  }
```

**Direct USB Access Results**:
```elixir
# Attempting to claim interface 0
:usb.claim_interface(device_handle, 0)
# Returns: {:error, :access}  # Permission denied

# Attempting interrupt transfer on endpoint 0x81
:usb.interrupt_transfer(device_handle, 0x81, 8, 1000)
# Returns: {:error, :not_found}  # Endpoint not available
```

**Solution**: Use macOS IOKit HID Manager API, which provides a higher-level interface that works with kernel-claimed devices.

### Linux: Direct USB Access (Expected)

**Advantage**: Linux typically allows direct USB access to HID devices through libusb, especially with appropriate udev rules.

**Expected Success**:
```elixir
# Should work on Linux
:usb.claim_interface(device_handle, 0)
# Returns: :ok

:usb.interrupt_transfer(device_handle, 0x81, 8, 1000)
# Returns: {:ok, data}
```

**Required udev Rule** (for non-root access):
```
# /etc/udev/rules.d/99-spacemouse.rules
SUBSYSTEM=="usb", ATTRS{idVendor}=="256f", ATTRS{idProduct}=="c635", MODE="0666"
```

### Windows: Similar to macOS

**Problem**: Windows also loads generic HID drivers that claim devices.

**Solution**: Use Windows HID API (similar approach to macOS IOKit).

## IOKit HID Manager (macOS Solution)

### Why IOKit Works

IOKit HID Manager provides a user-space API that cooperates with the kernel HID driver rather than competing with it. It allows applications to receive HID reports without claiming the entire USB interface.

### IOKit API Usage

**Device Matching**:
```c
// Create matching dictionary for SpaceMouse
CFMutableDictionaryRef matching = CFDictionaryCreateMutable(...);
CFNumberRef vendor_id = CFNumberCreate(..., 0x256F);
CFDictionarySetValue(matching, CFSTR(kIOHIDVendorIDKey), vendor_id);

// Set up HID manager
IOHIDManagerRef manager = IOHIDManagerCreate(...);
IOHIDManagerSetDeviceMatching(manager, matching);
```

**Callback Registration**:
```c
// Register for device events
IOHIDManagerRegisterDeviceMatchingCallback(manager, device_connected_callback, NULL);
IOHIDManagerRegisterDeviceRemovalCallback(manager, device_removed_callback, NULL);
IOHIDManagerRegisterInputValueCallback(manager, input_value_callback, NULL);
```

**Event Processing**:
```c
void input_value_callback(void *context, IOReturn result, void *sender, IOHIDValueRef value) {
    IOHIDElementRef element = IOHIDValueGetElement(value);
    uint32_t usage_page = IOHIDElementGetUsagePage(element);
    uint32_t usage = IOHIDElementGetUsage(element);
    CFIndex int_value = IOHIDValueGetIntegerValue(value);
    
    // Process motion data (usage page 1, usages 48-53)
    // Process button data (usage page 9, usages 1-2)
}
```

### Output to Elixir

The C program formats IOKit events as structured strings for easy parsing:

```
STATUS:ready
STATUS:device_connected
MOTION:page=1,usage=48,value=123  // X translation
MOTION:page=1,usage=49,value=-45  // Y translation  
MOTION:page=1,usage=50,value=200  // Z translation
MOTION:page=1,usage=51,value=12   // RX rotation
MOTION:page=1,usage=52,value=-34  // RY rotation
MOTION:page=1,usage=53,value=56   // RZ rotation
BUTTON:page=9,usage=1,value=1     // Button 1 pressed
BUTTON:page=9,usage=1,value=0     // Button 1 released
STATUS:device_disconnected
```

## Data Flow and Timing

### Motion Data Characteristics

**Update Rate**: ~375 Hz maximum (hardware polling rate), typically 250-350 Hz during active movement
**Value Range**: -350 to +350 (all 6 axes: X, Y, Z, RX, RY, RZ)
**Resolution**: 700 discrete steps per axis (±350 range)
**Dead Zone**: No hardware dead zone; software implementation recommended
**Scaling**: Raw values are directly usable or can be scaled to application-specific ranges
**Data Type**: Signed integers within ±350 range
**Neutral Position**: 0 represents center/rest position for all axes

### Button Data Characteristics

**Debouncing**: Handled by device firmware
**Event-driven**: Only sent on state changes
**Response Time**: <1ms from physical press to USB event

### Latency Analysis

```
Physical Motion → Device Processing → USB Transfer → OS Processing → Application
     ~1ms              ~1ms              ~1ms           ~1ms         ~1ms
                                    
Total Latency: ~5ms (acceptable for real-time interaction)
```

## Protocol Implementation Strategies

### Strategy 1: Direct USB (Linux)
```elixir
# Direct approach using :usb package
{:ok, device} = :usb.open(vendor_id: 0x256F, product_id: 0xC635)
:ok = :usb.claim_interface(device, 0)
{:ok, data} = :usb.interrupt_transfer(device, 0x81, 8, 100)
```

### Strategy 2: IOKit Bridge (macOS)
```c
// C program using IOKit
IOHIDManagerRef manager = IOHIDManagerCreate(...);
// Set up callbacks and run loop
// Output events to stdout for Elixir port
printf("MOTION:x=%d,y=%d,z=%d\n", x, y, z);
```

### Strategy 3: Control Transfer Fallback
```elixir
# HID report access via control transfers
{:ok, data} = :usb.control_transfer(
  device, 0x81, 0x01, (1 <<< 8) ||| 1, 0, 13, 1000
)
```

## Error Conditions and Recovery

### Common USB Errors

1. **`:access`** - Permission denied (kernel driver claiming)
2. **`:not_found`** - Endpoint/interface not available  
3. **`:timeout`** - Device not responding
4. **`:device_not_found`** - Device disconnected
5. **`:pipe_error`** - USB communication error

### Recovery Strategies

1. **Automatic Reconnection**: Detect disconnection and attempt reconnection
2. **Fallback Methods**: Try different communication approaches
3. **Graceful Degradation**: Continue operation with reduced functionality
4. **User Notification**: Inform application of device status changes

## Performance Optimization

### Reducing CPU Usage

1. **Event Filtering**: Only process significant motion changes
2. **Batch Processing**: Group multiple events when possible
3. **Efficient Parsing**: Optimize string parsing in port communication
4. **Memory Management**: Avoid unnecessary allocations

### Minimizing Latency

1. **Direct Callbacks**: Minimal processing in C callbacks
2. **Port Communication**: Use line-based output for immediate parsing
3. **Process Priority**: Consider real-time scheduling for critical applications
4. **Buffer Management**: Avoid buffering delays

## Testing and Validation

### USB Protocol Testing

```bash
# Monitor USB traffic (Linux)
sudo usbmon

# View device details
lsusb -v -d 256f:c635

# Test basic connectivity
usb-devices | grep -A 20 "3Dconnexion"
```

### HID Report Analysis

```bash
# Linux: Read raw HID reports
sudo cat /dev/hidraw0 | hexdump -C

# macOS: Use system_profiler
system_profiler SPUSBDataType | grep -A 20 "SpaceMouse"
```

### Protocol Validation

1. **Report Structure**: Verify report IDs and sizes match specification
2. **Value Ranges**: Confirm motion values stay within expected bounds  
3. **Event Timing**: Measure latency and update rates
4. **State Consistency**: Verify button states match physical presses

This protocol documentation provides the foundation for understanding how SpaceMouse devices communicate over USB and why different platforms require different access strategies.
