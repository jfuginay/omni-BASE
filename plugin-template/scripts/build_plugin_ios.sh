#!/bin/bash
#
# Build iOS plugin
# Usage: ./scripts/build_plugin_ios.sh [simulator|device] [debug|release]
#

set -e

# Parse arguments
PLATFORM="${1:-simulator}"
BUILD_MODE="${2:-debug}"

if [ "$BUILD_MODE" = "release" ]; then
    COMPILATION_MODE="opt"
else
    COMPILATION_MODE="dbg"
fi

# Determine config based on platform
if [ "$PLATFORM" = "device" ]; then
    CONFIG="ios_device"
    echo "Building iOS plugin for DEVICE in $BUILD_MODE mode..."
    echo "Note: This will use your Apple Developer certificate"
elif [ "$PLATFORM" = "simulator" ]; then
    CONFIG="ios"
    echo "Building iOS plugin for SIMULATOR in $BUILD_MODE mode..."
else
    echo "Error: Invalid platform. Use 'simulator' or 'device'"
    echo "Usage: ./scripts/build_plugin_ios.sh [simulator|device] [debug|release]"
    exit 1
fi

# Check if we're in the plugin template directory
if [ ! -f "plugin.json" ]; then
    echo "Error: plugin.json not found. Are you in the plugin directory?"
    exit 1
fi

# Check for local configuration
if [ "$PLATFORM" = "device" ] && [ ! -f ".bazelrc.local" ]; then
    echo ""
    echo "⚠️  Warning: No .bazelrc.local found"
    echo "For device builds, you should create .bazelrc.local with your signing configuration."
    echo "Example:"
    echo "  cp .bazelrc.local.example .bazelrc.local"
    echo "  # Edit .bazelrc.local with your Team ID"
    echo ""
    echo "Attempting build with default 'Apple Development' certificate..."
    echo ""
fi

# Build with Bazel
bazel build \
    --config="$CONFIG" \
    --compilation_mode="$COMPILATION_MODE" \
    //ios:MyPlugin

echo ""
echo "✅ Build completed successfully!"
echo "Output: bazel-bin/ios/MyPlugin.framework"

if [ "$PLATFORM" = "simulator" ]; then
    echo ""
    echo "To test in simulator:"
    echo "  1. Open Simulator.app"
    echo "  2. Integrate this framework into the OmniTAK test app"
fi

if [ "$PLATFORM" = "device" ]; then
    echo ""
    echo "To install on device:"
    echo "  1. Integrate this framework into the OmniTAK app"
    echo "  2. Build and install OmniTAK with plugin included"
    echo ""
    echo "Or package as plugin bundle:"
    echo "  ./scripts/package_plugin.sh"
fi
