#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/outputs/Don CSV.app"

cd "$ROOT"
swift build -c release

killall DonCSV 2>/dev/null || true
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DonCSV "$APP/Contents/MacOS/DonCSV"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/DonCSVIcon-1024.png "$APP/Contents/Resources/DonCSVIcon-1024.png"
xattr -cr "$APP"
codesign --force --sign - "$APP"
open "$APP"
