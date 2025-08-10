/*
 * Minimal SpaceMouse HID Reader for macOS
 *
 * Purpose: Provide the most basic HID communication layer that cannot be
 *          accessed from the Erlang VM due to macOS IOKit restrictions.
 *
 * Responsibilities:
 * - Detect SpaceMouse device connection/disconnection
 * - Read raw HID input reports (motion, buttons)
 * - Output structured data to stdout for Elixir port communication
 *
 * Communication Protocol:
 * - Output format: "TYPE:key1=value1,key2=value2"
 * - STATUS messages: "STATUS:ready", "STATUS:device_connected", "STATUS:device_disconnected"
 * - MOTION events: "MOTION:x=123,y=456,z=789,rx=12,ry=34,rz=56"
 * - BUTTON events: "BUTTON:id=1,state=pressed" or "BUTTON:id=1,state=released"
 *
 * Compile: clang -framework IOKit -framework CoreFoundation -o hid_reader hid_reader.c
 */

#include <IOKit/hid/IOHIDManager.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>

// 3Dconnexion SpaceMouse vendor ID
#define SPACEMOUSE_VENDOR_ID 0x256F

// Motion axes mapping (Generic Desktop usage page 0x01)
#define USAGE_X 48
#define USAGE_Y 49
#define USAGE_Z 50
#define USAGE_RX 51
#define USAGE_RY 52
#define USAGE_RZ 53

// Global state
static IOHIDManagerRef hid_manager = NULL;
static bool device_connected = false;

// Device connection callback
static void device_matching_callback(void *context __unused, IOReturn result __unused, void *sender __unused, IOHIDDeviceRef device __unused)
{
    if (!device_connected)
    {
        device_connected = true;
        printf("STATUS:device_connected\n");
        fflush(stdout);
    }
}

// Device disconnection callback
static void device_removal_callback(void *context __unused, IOReturn result __unused, void *sender __unused, IOHIDDeviceRef device __unused)
{
    if (device_connected)
    {
        device_connected = false;
        printf("STATUS:device_disconnected\n");
        fflush(stdout);
    }
}

// HID input report callback
static void input_callback(void *context __unused, IOReturn result __unused, void *sender __unused, IOHIDValueRef value)
{
    IOHIDElementRef element = IOHIDValueGetElement(value);
    uint32_t usage_page = IOHIDElementGetUsagePage(element);
    uint32_t usage = IOHIDElementGetUsage(element);
    CFIndex int_value = IOHIDValueGetIntegerValue(value);

    // Handle motion data (Generic Desktop usage page)
    if (usage_page == 1)
    {
        const char *axis = NULL;
        switch (usage)
        {
        case USAGE_X:
            axis = "x";
            break;
        case USAGE_Y:
            axis = "y";
            break;
        case USAGE_Z:
            axis = "z";
            break;
        case USAGE_RX:
            axis = "rx";
            break;
        case USAGE_RY:
            axis = "ry";
            break;
        case USAGE_RZ:
            axis = "rz";
            break;
        default:
            return; // Ignore other axes
        }

        if (axis)
        {
            printf("MOTION:%s=%ld\n", axis, int_value);
            fflush(stdout);
        }
    }

    // Handle button data (Button usage page)
    else if (usage_page == 9)
    {
        const char *state = (int_value > 0) ? "pressed" : "released";
        printf("BUTTON:id=%d,state=%s\n", usage, state);
        fflush(stdout);
    }
}

// Create HID device matching dictionary for SpaceMouse
static CFMutableDictionaryRef create_spacemouse_matching_dict()
{
    CFMutableDictionaryRef dict = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);

    if (dict)
    {
        CFNumberRef vendor_id = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &(int){SPACEMOUSE_VENDOR_ID});
        CFDictionarySetValue(dict, CFSTR(kIOHIDVendorIDKey), vendor_id);
        CFRelease(vendor_id);
    }

    return dict;
}

// Initialize HID manager and start monitoring
static bool initialize_hid_system()
{
    // Create HID manager
    hid_manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!hid_manager)
    {
        fprintf(stderr, "ERROR: Failed to create HID manager\n");
        return false;
    }

    // Set device matching criteria
    CFMutableDictionaryRef matching_dict = create_spacemouse_matching_dict();
    if (!matching_dict)
    {
        fprintf(stderr, "ERROR: Failed to create matching dictionary\n");
        CFRelease(hid_manager);
        return false;
    }

    IOHIDManagerSetDeviceMatching(hid_manager, matching_dict);
    CFRelease(matching_dict);

    // Register callbacks
    IOHIDManagerRegisterDeviceMatchingCallback(hid_manager, device_matching_callback, NULL);
    IOHIDManagerRegisterDeviceRemovalCallback(hid_manager, device_removal_callback, NULL);
    IOHIDManagerRegisterInputValueCallback(hid_manager, input_callback, NULL);

    // Schedule with run loop
    IOHIDManagerScheduleWithRunLoop(hid_manager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

    // Open HID manager
    IOReturn result = IOHIDManagerOpen(hid_manager, kIOHIDOptionsTypeNone);
    if (result != kIOReturnSuccess)
    {
        fprintf(stderr, "ERROR: Failed to open HID manager (0x%08x)\n", result);
        CFRelease(hid_manager);
        return false;
    }

    return true;
}

// Cleanup HID system
static void cleanup_hid_system()
{
    if (hid_manager)
    {
        IOHIDManagerClose(hid_manager, kIOHIDOptionsTypeNone);
        IOHIDManagerUnscheduleFromRunLoop(hid_manager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        CFRelease(hid_manager);
        hid_manager = NULL;
    }
}

// Main entry point
int main(int argc __unused, char *argv[] __unused)
{
    // Initialize HID system
    if (!initialize_hid_system())
    {
        return 1;
    }

    // Signal ready state
    printf("STATUS:ready\n");
    fflush(stdout);

    // Run event loop indefinitely
    CFRunLoopRun();

    // Cleanup (never reached in normal operation)
    cleanup_hid_system();
    return 0;
}
