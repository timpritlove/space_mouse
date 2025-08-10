#!/bin/bash
#
# Build script for macOS HID reader
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/_build/dev/lib/space_mouse/priv/platform/macos"

# Create build directory if it doesn't exist
mkdir -p "$BUILD_DIR"

echo "🔨 Building macOS HID reader..."

# Compile the C program to the build directory
clang -framework IOKit -framework CoreFoundation \
      -O2 -Wall -Wextra \
      -o "$BUILD_DIR/hid_reader" \
      "$SCRIPT_DIR/hid_reader.c"

echo "✅ Build complete: $BUILD_DIR/hid_reader"
echo "🧪 Test with: $BUILD_DIR/hid_reader"
