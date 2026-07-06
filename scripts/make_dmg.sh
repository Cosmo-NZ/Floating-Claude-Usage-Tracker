#!/usr/bin/env bash
# Build a distributable .dmg with a drag-to-Applications layout.
set -euo pipefail
cd "$(dirname "$0")/.."

VOLNAME="Claude Usage Tracker"
APP="build/ClaudeUsageTracker.app"
DMG="build/ClaudeUsageTracker.dmg"
STAGING="build/dmg_staging"

# Ensure a fresh, signed app bundle exists.
./scripts/build_app.sh release

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Best-effort pretty layout (icon positions + window size). Requires Finder
# automation permission; if denied, the DMG is still built and fully functional.
RW_DMG="build/rw.dmg"
rm -f "$RW_DMG"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" -ov -format UDRW "$RW_DMG" >/dev/null

MOUNT_DIR="/Volumes/$VOLNAME"
hdiutil attach "$RW_DMG" -noautoopen >/dev/null
if osascript >/dev/null 2>&1 <<EOF
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 720, 460}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 120
    set position of item "ClaudeUsageTracker.app" of container window to {130, 180}
    set position of item "Applications" of container window to {390, 180}
    update without registering applications
    close
  end tell
end tell
EOF
then
  echo "Applied Finder layout."
else
  echo "Skipped Finder layout (automation not permitted) — DMG still works."
fi
sync
hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true

# Convert to compressed, read-only final DMG.
hdiutil convert "$RW_DMG" -format UDZO -o "$DMG" >/dev/null
rm -f "$RW_DMG"
rm -rf "$STAGING"

echo "Created $DMG"
ls -lh "$DMG" | awk '{print "Size:", $5}'
