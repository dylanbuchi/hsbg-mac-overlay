#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_NAME="HSBG Mac Overlay.app"
SOURCE_APP="$PROJECT_DIR/dist/$APP_NAME"
INSTALL_DIR="$HOME/Applications/$APP_NAME"
AGENT_DIR="$HOME/Library/LaunchAgents"
LABEL="com.dylanbuchi.hsbg-mac-overlay"
AGENT_PATH="$AGENT_DIR/$LABEL.plist"

/bin/sh "$PROJECT_DIR/scripts/package-app.sh" "$PROJECT_DIR/dist"
mkdir -p "$HOME/Applications" "$AGENT_DIR" "$HOME/Library/Logs"
ditto "$SOURCE_APP" "$INSTALL_DIR"
# The agent template uses __HOME__ for the installing user's home folder.
sed "s#__HOME__#$HOME#g" "$PROJECT_DIR/packaging/$LABEL.plist" > "$AGENT_PATH"

USER_ID=$(/usr/bin/id -u)
if /bin/launchctl print "gui/$USER_ID/$LABEL" >/dev/null 2>&1; then
    /bin/launchctl kickstart -k "gui/$USER_ID/$LABEL"
else
    /bin/launchctl bootstrap "gui/$USER_ID" "$AGENT_PATH"
fi

echo "Installed: $INSTALL_DIR"
echo "Autostart enabled: $LABEL"
