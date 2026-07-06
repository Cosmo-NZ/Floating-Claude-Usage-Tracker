#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/ClaudeUsageTracker"
APP="build/ClaudeUsageTracker.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeUsageTracker"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# Prefer the stable self-signed identity (keeps Keychain access across rebuilds);
# fall back to ad-hoc if it hasn't been set up (run scripts/setup_signing.sh).
IDENTITY="ClaudeUsageTracker Dev"
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" "$APP"
    echo "Built $APP (signed: $IDENTITY)"
else
    codesign --force --sign - "$APP"
    echo "Built $APP (ad-hoc)"
fi
