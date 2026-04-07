#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_APP="/Applications/ClaudeBat.app"
BUILD_APP="$PROJECT_DIR/build/ClaudeBat.app"
STATUS_FILE="$HOME/Library/Application Support/ClaudeBat/monitor-status.json"
LOG_FILE="$HOME/Library/Logs/ClaudeBat/monitor.jsonl"
BACKUP_DIR="$HOME/Library/Application Support/ClaudeBat/Backups"
TIMESTAMP="$(date +"%Y%m%d-%H%M%S")"
BACKUP_APP="$BACKUP_DIR/ClaudeBat-$TIMESTAMP.app"

restore_backup() {
    if [ -d "$BACKUP_APP" ]; then
        echo "Install failed. Restoring backup to $TARGET_APP"
        rm -rf "$TARGET_APP"
        mv "$BACKUP_APP" "$TARGET_APP"
    fi
}

trap restore_backup ERR

echo "==> Building local monitor bundle"
LOCAL_MONITOR_BUILD=1 "$PROJECT_DIR/scripts/build-app.sh"

echo "==> Quitting ClaudeBat"
osascript -e 'tell application "ClaudeBat" to quit' >/dev/null 2>&1 || true
pkill -x ClaudeBat >/dev/null 2>&1 || true
sleep 1

mkdir -p "$BACKUP_DIR"

if [ -d "$TARGET_APP" ]; then
    echo "==> Backing up existing app to $BACKUP_APP"
    mv "$TARGET_APP" "$BACKUP_APP"
fi

echo "==> Installing monitored build to $TARGET_APP"
/usr/bin/ditto "$BUILD_APP" "$TARGET_APP"
xattr -cr "$TARGET_APP" >/dev/null 2>&1 || true

echo "==> Launching ClaudeBat"
open "$TARGET_APP"

echo "==> Waiting for monitor status snapshot"
for _ in $(seq 1 20); do
    if [ -f "$STATUS_FILE" ] && grep -q '"app_running"[[:space:]]*:[[:space:]]*true' "$STATUS_FILE"; then
        break
    fi
    sleep 1
done

if ! [ -f "$STATUS_FILE" ]; then
    echo "ERROR: monitor status file was not created at $STATUS_FILE"
    exit 1
fi

if ! grep -q '"app_running"[[:space:]]*:[[:space:]]*true' "$STATUS_FILE"; then
    echo "ERROR: monitor status file exists but app_running was not true"
    exit 1
fi

trap - ERR

echo "==> Install complete"
echo "App: $TARGET_APP"
if [ -d "$BACKUP_APP" ]; then
    echo "Backup: $BACKUP_APP"
fi
echo "Status: $STATUS_FILE"
if [ -f "$LOG_FILE" ]; then
    echo "Log: $LOG_FILE"
fi
