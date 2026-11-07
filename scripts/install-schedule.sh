#!/usr/bin/env bash
# install-schedule.sh [--print|--install] [cron|launchd|systemd]
# Schedules what must run without anyone remembering it: the health check with repairs (every 30 minutes) and the full test
# matrix (every 6 hours). --print (default) shows the entries; --install writes them (cron: user crontab; launchd: a user
# LaunchAgent; systemd: user timers). The coordinating agent ALSO runs the health loop while a session is open (it can act on
# FAIL lines); this schedule is the floor that keeps working when no session is.
. "$(dirname "$0")/lib/common.sh"
mode=${1:---print}; kind=${2:-}
[ -n "$kind" ] || { if [ "$OS" = Darwin ]; then kind=launchd; elif command -v systemctl >/dev/null 2>&1; then kind=systemd; else kind=cron; fi; }
health="$FACTORY_BIN/health.sh --fix >> $STATE_DIR/health.log 2>&1"
matrix="$FACTORY_BIN/matrix-check.sh >> $STATE_DIR/matrix.out 2>&1"
label="dev.software-factory.$PROJECT_NAME"
case "$kind" in
  cron)
    entry="7,37 * * * * $health
13 */6 * * * [ -n \"\$(grep -E '^CMD_E2E_MATRIX=.+' $FACTORY_CONF)\" ] && $matrix"
    if [ "$mode" = --install ]; then ( crontab -l 2>/dev/null | grep -v "$FACTORY_BIN/"; echo "$entry" ) | crontab -; echo "cron installed"; else echo "$entry"; fi ;;
  launchd)
    plist="$HOME/Library/LaunchAgents/$label.health.plist"
    body="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\"><dict>
<key>Label</key><string>$label.health</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>-c</string><string>$health</string></array>
<key>StartInterval</key><integer>1800</integer>
<key>RunAtLoad</key><true/>
</dict></plist>"
    if [ "$mode" = --install ]; then mkdir -p "$(dirname "$plist")"; echo "$body" > "$plist"; launchctl unload "$plist" 2>/dev/null; launchctl load "$plist"; echo "launchd agent installed: $plist"; else echo "$body"; fi ;;
  systemd)
    unit="$HOME/.config/systemd/user"
    svc="[Unit]
Description=software factory health ($PROJECT_NAME)
[Service]
Type=oneshot
ExecStart=/bin/bash -c '$health'"
    tmr="[Unit]
Description=software factory health every 30 minutes ($PROJECT_NAME)
[Timer]
OnBootSec=2min
OnUnitActiveSec=30min
[Install]
WantedBy=timers.target"
    if [ "$mode" = --install ]; then mkdir -p "$unit"; echo "$svc" > "$unit/$label-health.service"; echo "$tmr" > "$unit/$label-health.timer"; systemctl --user daemon-reload && systemctl --user enable --now "$label-health.timer"; echo "systemd timer installed"; else echo "$svc"; echo ---; echo "$tmr"; fi ;;
  *) echo "usage: install-schedule.sh [--print|--install] [cron|launchd|systemd]" >&2; exit 2 ;;
esac
