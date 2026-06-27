#!/usr/bin/env bash
# Launch the shed-mobile Flutter client in debug mode and register it with Marionette.
#
# Usage: launch-and-connect.sh [macos|linux] [instance-name]
#   Defaults: device=macos, instance=shed-mobile
#
# Leaves `flutter run` running in the background (prints its PID + log path) so an
# agent can drive the app, then hot-reload after edits. Debug build only.
set -euo pipefail

RUN_PID=""
KEEP_RUNNING_ON_EXIT=0
cleanup() {
  if [ "$KEEP_RUNNING_ON_EXIT" -eq 0 ] && [ -n "${RUN_PID:-}" ]; then
    kill "$RUN_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

DEVICE="${1:-macos}"
INSTANCE="${2:-shed-mobile}"
MARIONETTE="${MARIONETTE:-$(command -v marionette || echo "$HOME/.pub-cache/bin/marionette")}"

# shed-mobile is a single-app repo: the project root is the git toplevel.
APP="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
LOG="$(mktemp -t shed-mobile-flutter-XXXXXX).log"

if [ ! -x "$MARIONETTE" ] && ! command -v "$MARIONETTE" >/dev/null 2>&1; then
  echo "marionette CLI not found. Install: dart pub global activate marionette_cli" >&2
  echo "and ensure ~/.pub-cache/bin is on PATH (or set MARIONETTE=/path/to/marionette)." >&2
  exit 1
fi

echo "Launching Flutter ($DEVICE), logging to $LOG ..."
( cd "$APP" && exec flutter run -d "$DEVICE" --dart-define-from-file=env/dev.json ) >"$LOG" 2>&1 &
RUN_PID=$!

# Wait for the Dart VM Service URI; anchor on the "Dart VM Service" line so we
# never grab the DevTools URL printed around the same time.
URI=""
for _ in $(seq 1 150); do
  URI="$(grep -a 'Dart VM Service' "$LOG" 2>/dev/null \
          | grep -oE 'http://127\.0\.0\.1:[0-9]+/[A-Za-z0-9_=/-]+' | head -1 || true)"
  [ -n "$URI" ] && break
  if ! kill -0 "$RUN_PID" 2>/dev/null; then
    echo "flutter run exited before printing a VM Service URI. Log:" >&2
    tail -n 40 "$LOG" >&2
    exit 1
  fi
  sleep 2
done
if [ -z "$URI" ]; then
  echo "Timed out waiting for the VM Service URI. See $LOG" >&2
  exit 1
fi

WS="$(printf '%s' "$URI" | sed -e 's#^http#ws#' -e 's#/\{0,1\}$#/ws#')"
echo "VM Service: $WS"
"$MARIONETTE" register "$INSTANCE" "$WS"
KEEP_RUNNING_ON_EXIT=1

cat <<EOF

Connected as instance "$INSTANCE". flutter run is PID $RUN_PID (log: $LOG).

Next:
  $MARIONETTE -i $INSTANCE get-interactive-elements
  $MARIONETTE -i $INSTANCE tap --key servers-add
  $MARIONETTE -i $INSTANCE enter-text --key addserver-host --input localhost
  $MARIONETTE -i $INSTANCE tap --key addserver-connect
  $MARIONETTE -i $INSTANCE get-logs | grep MSTATE | tail -1
  $MARIONETTE -i $INSTANCE take-screenshots --output ./shed-mobile.png

Cleanup:
  kill $RUN_PID
  $MARIONETTE unregister $INSTANCE
EOF
