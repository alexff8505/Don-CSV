#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/outputs/Don CSV.app"
DONCSV_SDKROOT="${SDKROOT:-}"

if [[ -z "$DONCSV_SDKROOT" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk ]]; then
    DONCSV_SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk
fi

if [[ -n "$DONCSV_SDKROOT" ]]; then
    export SDKROOT="$DONCSV_SDKROOT"
fi
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT/.build/ModuleCache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$ROOT/.build/SwiftPMModuleCache}"

cd "$ROOT"
swift build -c release --disable-sandbox

killall DonCSV 2>/dev/null || true
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DonCSV "$APP/Contents/MacOS/DonCSV"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/DonCSVIcon-1024.png "$APP/Contents/Resources/DonCSVIcon-1024.png"
xattr -cr "$APP"
codesign --force --sign - "$APP"
open "$APP"
