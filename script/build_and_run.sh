#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/outputs/Don CSV.app"
DONCSV_SDKROOT="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk}"
if [[ ! -d "$DONCSV_SDKROOT" ]]; then
    echo "macOS 26 SDK not found at $DONCSV_SDKROOT" >&2
    exit 1
fi

export SDKROOT="$DONCSV_SDKROOT"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT/.build/ModuleCache26}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$ROOT/.build/SwiftPMModuleCache26}"

SDK_SWIFT_INTERFACE="$DONCSV_SDKROOT/usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface"
SDK_COMPILER_VERSION=""
if [[ -f "$SDK_SWIFT_INTERFACE" ]]; then
    SDK_COMPILER_VERSION="$(sed -n 's#^// swift-compiler-version: ##p' "$SDK_SWIFT_INTERFACE" | head -n 1)"
fi

cd "$ROOT"
killall DonCSV 2>/dev/null || true
for _ in {1..50}; do
    if ! killall -0 DonCSV 2>/dev/null; then
        break
    fi
    sleep 0.1
done
SWIFT_BUILD_ARGUMENTS=(-c release --disable-sandbox)
if [[ -n "$SDK_COMPILER_VERSION" ]]; then
    SWIFT_BUILD_ARGUMENTS+=(-Xswiftc -interface-compiler-version -Xswiftc "$SDK_COMPILER_VERSION")
fi
swift build "${SWIFT_BUILD_ARGUMENTS[@]}"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DonCSV "$APP/Contents/MacOS/DonCSV"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/DonCSVIcon-1024.png "$APP/Contents/Resources/DonCSVIcon-1024.png"
xattr -cr "$APP"
codesign --force --sign - "$APP"
touch "$APP"
sleep 0.25
open "$APP"
