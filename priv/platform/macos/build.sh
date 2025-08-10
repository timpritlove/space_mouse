#!/bin/bash
#
# Build script for macOS HID reader
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🔨 Building macOS HID reader..."

# Compile the C program
clang -framework IOKit -framework CoreFoundation \
      -O2 -Wall -Wextra \
      -o hid_reader \
      hid_reader.c

echo "✅ Build complete: hid_reader"
echo "🧪 Test with: ./hid_reader"
