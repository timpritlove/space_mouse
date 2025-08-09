/*
 * SpaceMouse HID Reader using IOKit
 * Compile with: clang -framework IOKit -framework CoreFoundation -o spacemouse_reader spacemouse_reader.c
 */
#include <IOKit/hid/IOHIDManager.h>
#include <stdio.h>
#include <stdlib.h>

static void device_matching_callback(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    printf("device_found\n");
    fflush(stdout);
}

static void device_removal_callback(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    printf("device_removed\n");
    fflush(stdout);
}

    static void input_callback(void *context, IOReturn result, void *sender, IOHIDValueRef value) {
        IOHIDElementRef element = IOHIDValueGetElement(value);
        uint32_t usage_page = IOHIDElementGetUsagePage(element);
        uint32_t usage = IOHIDElementGetUsage(element);
        CFIndex int_value = IOHIDValueGetIntegerValue(value);
        
        // Focus on Generic Desktop usage page (1) for motion data
        if (usage_page == 1) {
            // Usage 48=X, 49=Y, 50=Z, 51=Rx, 52=Ry, 53=Rz
            if (usage >= 48 && usage <= 53) {
                printf("motion:page=%d,usage=%d,value=%ld\n", usage_page, usage, int_value);
                fflush(stdout);
            }
        }
        
        // Also report button data (usage page 9)
        if (usage_page == 9) {
            printf("button:page=%d,usage=%d,value=%ld\n", usage_page, usage, int_value);
            fflush(stdout);
        }
        
        // Report all events for debugging
        printf("hid_event:page=%d,usage=%d,value=%ld\n", usage_page, usage, int_value);
        fflush(stdout);
    }

int main(int argc, char *argv[]) {
    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, 0);
    
    // Set device matching for SpaceMouse (VID: 0x256F, PID: 0xC635)
    CFMutableDictionaryRef matching = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    
    int vid = 0x256F;
    int pid = 0xC635;
    CFNumberRef vendor_id = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &vid);
    CFNumberRef product_id = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &pid);
    
    CFDictionarySetValue(matching, CFSTR(kIOHIDVendorIDKey), vendor_id);
    CFDictionarySetValue(matching, CFSTR(kIOHIDProductIDKey), product_id);
    
    IOHIDManagerSetDeviceMatching(manager, matching);
    
    // Set callbacks
    IOHIDManagerRegisterDeviceMatchingCallback(manager, device_matching_callback, NULL);
    IOHIDManagerRegisterDeviceRemovalCallback(manager, device_removal_callback, NULL);
    IOHIDManagerRegisterInputValueCallback(manager, input_callback, NULL);
    
    // Schedule with run loop
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    
    // Open manager
    IOReturn ret = IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone);
    if (ret != kIOReturnSuccess) {
        printf("error:failed_to_open_manager\n");
        return 1;
    }
    
    printf("ready\n");
    fflush(stdout);
    
    // Run event loop
    CFRunLoopRun();
    
    return 0;
}
