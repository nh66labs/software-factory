#!/usr/bin/env bash
# notify.sh "<message>"   A ready NOTIFY_CMD with common backends, chosen by environment (set them in the machine's environment
# or a git-ignored file sourced by factory.conf; never commit tokens). Several may be set; each is best effort.
#   NOTIFY_NTFY_TOPIC      https://ntfy.sh/<topic> push to a phone (self-hosted ntfy: NOTIFY_NTFY_URL)
#   NOTIFY_SLACK_WEBHOOK   Slack incoming webhook URL
#   NOTIFY_WEBHOOK         any URL receiving JSON {"text": "..."}
#   NOTIFY_FILE            append to a file (default: state/notifications.log, always written)
#   NOTIFY_MACOS=1         a macOS notification on this machine
msg=${1:?usage: notify.sh <message>}
here=$(cd "$(dirname "$0")" && pwd)
file=${NOTIFY_FILE:-$here/../state/notifications.log}
mkdir -p "$(dirname "$file")"; printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M')" "$msg" >> "$file"
json=$(python3 -I -c 'import json,sys; print(json.dumps({"text": sys.argv[1]}))' "$msg")
[ -n "${NOTIFY_NTFY_TOPIC:-}" ] && curl -fsS -m 15 -d "$msg" "${NOTIFY_NTFY_URL:-https://ntfy.sh}/$NOTIFY_NTFY_TOPIC" >/dev/null 2>&1
[ -n "${NOTIFY_SLACK_WEBHOOK:-}" ] && curl -fsS -m 15 -H 'Content-Type: application/json' -d "$json" "$NOTIFY_SLACK_WEBHOOK" >/dev/null 2>&1
[ -n "${NOTIFY_WEBHOOK:-}" ] && curl -fsS -m 15 -H 'Content-Type: application/json' -d "$json" "$NOTIFY_WEBHOOK" >/dev/null 2>&1
[ "${NOTIFY_MACOS:-}" = 1 ] && command -v osascript >/dev/null 2>&1 && osascript -e "display notification \"${msg//\"/}\" with title \"software factory\"" >/dev/null 2>&1
exit 0
