#!/bin/sh
set -eu

# The WebUI port is read from the persistent config so the check keeps working
# even if the user changes the port in the WebUI. qBittorrent answers 403 for
# unauthenticated requests and 200 once logged in; both mean the daemon is up.
CONF_FILE="/config/qBittorrent/config/qBittorrent.conf"
port=8080
if [ -f "$CONF_FILE" ]; then
    cfg_port="$(sed -n 's/^WebUI\/Port=\([0-9][0-9]*\)$/\1/p' "$CONF_FILE" | tail -n 1)"
    if [ -n "$cfg_port" ]; then
        port="$cfg_port"
    fi
fi

code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:${port}/")"
case "$code" in
    200|401|403) exit 0 ;;
    *) exit 1 ;;
esac
