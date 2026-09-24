#!/bin/zsh
set -euo pipefail

APP_PATH="$HOME/Applications/NotchKiller.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/io.github.lechar111.notchkiller.plist"

launchctl unload "$LAUNCH_AGENT" >/dev/null 2>&1 || true
rm -f "$LAUNCH_AGENT"
rm -rf "$APP_PATH"

echo "NotchKiller removed."
