/*
 * SpaceMouse HID Reader with LED Control for macOS
 *
 * Purpose: Provide bidirectional HID communication layer that cannot be
 *          accessed from the Erlang VM due to macOS IOKit restrictions.
 *
 * Responsibilities:
 * - Detect SpaceMouse device connection/disconnection
 * - Read raw HID input reports (motion, buttons)
 * - Send HID output reports (LED control)
 * - Handle commands from stdin (Elixir port communication)
 * - Output structured data to stdout for Elixir port communication
 *
 * Communication Protocol:
 * INPUT (from Elixir via stdin):
 * - LED commands: "LED:on" or "LED:off"
 *
 * OUTPUT (to Elixir via stdout):
 * - Output format: "TYPE:key1=value1,key2=value2"
 * - STATUS messages: "STATUS:ready", "STATUS:device_connected", "STATUS:device_disconnected"
 * - MOTION events: "MOTION:x=123,y=456,z=789,rx=12,ry=34,rz=56"
 * - BUTTON events: "BUTTON:id=1,state=pressed" or "BUTTON:id=1,state=released"
 * - LED confirmations: "LED:state=on" or "LED:state=off"
 *
 * Compile: clang -framework IOKit -framework CoreFoundation -o hid_reader hid_reader.c
 */

#include <IOKit/hid/IOHIDManager.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <sys/select.h>

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
static IOHIDDeviceRef current_device = NULL;
static bool device_connected = false;
static bool led_state = false;

// Device connection callback
static void device_matching_callback(void *context __unused, IOReturn result __unused, void *sender __unused, IOHIDDeviceRef device)
{
    if (!device_connected)
    {
        device_connected = true;
        current_device = device;
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
        current_device = NULL;
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

// Try different LED control methods for various SpaceMouse models
static bool try_led_method(IOHIDDeviceRef device, int method, bool on)
{
    IOReturn result = kIOReturnError;

    switch (method)
    {
    case 1: // Method 1: Output report ID 4 (correct method from git history)
    {
        uint8_t report_data[2] = {0x04, on ? 1 : 0};
        result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput,
                                      report_data[0], report_data, sizeof(report_data));
        printf("STATUS:led_method=1,result=0x%08x\n", result);
        break;
    }

    case 2: // Method 2: Feature report ID 4 (backup method)
    {
        uint8_t report_data[2] = {0x04, on ? 1 : 0};
        result = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature,
                                      report_data[0], report_data, sizeof(report_data));
        printf("STATUS:led_method=2,result=0x%08x\n", result);
        break;
    }

    case 3: // Method 3: Feature report ID 7
    {
        uint8_t report_data[2] = {0x07, on ? 1 : 0};
        result = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature,
                                      report_data[0], report_data, sizeof(report_data));
        printf("STATUS:led_method=3,result=0x%08x\n", result);
        break;
    }

    case 4: // Method 4: Extended feature report
    {
        uint8_t report_data[3] = {0x04, on ? 1 : 0, 0x00};
        result = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature,
                                      report_data[0], report_data, sizeof(report_data));
        printf("STATUS:led_method=4,result=0x%08x\n", result);
        break;
    }
    }

    fflush(stdout);
    return (result == kIOReturnSuccess);
}

// Send LED control command to SpaceMouse
static bool send_led_command(bool on)
{
    if (!current_device || !device_connected)
    {
        printf("STATUS:led_failed=device_not_available\n");
        fflush(stdout);
        return false;
    }

    printf("STATUS:led_attempting=%s\n", on ? "on" : "off");
    fflush(stdout);

    // Try different LED control methods until one works
    for (int method = 1; method <= 4; method++)
    {
        if (try_led_method(current_device, method, on))
        {
            led_state = on;
            printf("LED:state=%s,method=%d\n", on ? "on" : "off", method);
            fflush(stdout);
            return true;
        }
    }

    printf("STATUS:led_failed=all_methods_failed\n");
    fflush(stdout);
    return false;
}

// Handle command from stdin
static void handle_stdin_command(const char *line)
{
    if (strncmp(line, "LED:", 4) == 0)
    {
        const char *cmd = line + 4;
        if (strcmp(cmd, "on") == 0)
        {
            send_led_command(true);
        }
        else if (strcmp(cmd, "off") == 0)
        {
            send_led_command(false);
        }
        else
        {
            printf("STATUS:unknown_led_command=%s\n", cmd);
            fflush(stdout);
        }
    }
    else
    {
        printf("STATUS:unknown_command=%s\n", line);
        fflush(stdout);
    }
}

// Check for stdin input and process commands
static void check_stdin_input()
{
    fd_set readfds;
    struct timeval timeout;

    FD_ZERO(&readfds);
    FD_SET(STDIN_FILENO, &readfds);

    timeout.tv_sec = 0;
    timeout.tv_usec = 0; // Non-blocking

    int result = select(STDIN_FILENO + 1, &readfds, NULL, NULL, &timeout);

    if (result > 0 && FD_ISSET(STDIN_FILENO, &readfds))
    {
        char buffer[256];
        if (fgets(buffer, sizeof(buffer), stdin))
        {
            // Remove newline
            char *newline = strchr(buffer, '\n');
            if (newline)
                *newline = '\0';

            handle_stdin_command(buffer);
        }
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

    // Run event loop with periodic stdin checking
    while (true)
    {
        // Run HID event loop for a short time
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);

        // Check for stdin commands
        check_stdin_input();
    }

    // Cleanup (never reached in normal operation)
    cleanup_hid_system();
    return 0;
}
