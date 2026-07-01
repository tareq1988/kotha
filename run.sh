#!/bin/bash
# Build Kotha and launch it. Regenerates the Xcode project if needed.
set -e
cd "$(dirname "$0")"

if [ ! -d "Kotha.xcodeproj" ] || [ project.yml -nt Kotha.xcodeproj ]; then
  echo "→ Generating Xcode project…"
  xcodegen generate
fi

echo "→ Building…"
xcodebuild -project Kotha.xcodeproj -scheme Kotha -configuration Debug \
  -derivedDataPath build build -quiet

APP="build/Build/Products/Debug/Kotha.app"
echo "→ Launching $APP"
# Relaunch fresh
pkill -x Kotha 2>/dev/null || true
sleep 0.3
open "$APP"
echo "✓ Kotha is running in the menu bar."
