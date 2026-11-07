#!/usr/bin/env bash
# keepawake.sh   Keep the machine awake while the factory runs. A machine that sleeps drops the network connections of
# every headless agent run at once (they end with no output and look like failures). Servers do not sleep: no-op there.
case "$(uname -s)" in
  Darwin) exec caffeinate -imsu -t "${KEEPAWAKE_SECONDS:-259200}" ;;
  Linux)
    if command -v systemd-inhibit >/dev/null 2>&1; then exec systemd-inhibit --what=idle:sleep --why="software factory" sleep "${KEEPAWAKE_SECONDS:-259200}"; fi
    exec sleep "${KEEPAWAKE_SECONDS:-259200}" ;;
  *) exec sleep "${KEEPAWAKE_SECONDS:-259200}" ;;
esac
