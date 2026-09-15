#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM="${1:-12D14131-D489-4300-815F-E7A77C841E1E}"
DEVELOPER="$(xcode-select -p)"
export SIMCTL_CHILD_DYLD_FRAMEWORK_PATH="$DEVELOPER/Platforms/iPhoneSimulator.platform/Developer/Library/Frameworks:$DEVELOPER/Platforms/iPhoneSimulator.platform/Developer/Library/PrivateFrameworks"
xcrun simctl install "$SIM" "$ROOT/.build/Build/Products/Debug-iphonesimulator/CraftStudio.app"
xcrun simctl launch "$SIM" studio.craft.ios
