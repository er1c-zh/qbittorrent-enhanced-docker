#!/bin/sh
set -eu

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
TZ="${TZ:-UTC}"

# Set the timezone.
if [ -e "/usr/share/zoneinfo/$TZ" ]; then
    ln -sfn "/usr/share/zoneinfo/$TZ" /etc/localtime
    printf '%s\n' "$TZ" > /etc/timezone
fi

# Required directories.
mkdir -p /config /downloads

# Seed a default configuration on first run so the container works out of the
# box: config/data/cache live under /config, downloads go to /downloads.
# qBittorrent merges these keys with its own defaults and rewrites the file on
# shutdown, so any later WebUI changes are preserved.
CONF_FILE="/config/qBittorrent/config/qBittorrent.conf"
if [ ! -f "$CONF_FILE" ]; then
    mkdir -p "$(dirname "$CONF_FILE")"
    cat > "$CONF_FILE" <<'EOF'
[LegalNotice]
Accepted=true

[Preferences]
WebUI/Port=8080

[BitTorrent]
Session/DefaultSavePath=/downloads
Session/Port=6881
EOF
fi

# Make sure volume contents are owned by the target UID/GID, but only when they
# actually differ (avoids recursing over large download trees on every start).
fix_perms() {
    dir="$1"
    uid="$2"
    gid="$3"
    owner="$(stat -c '%u:%g' "$dir" 2>/dev/null || true)"
    if [ "$owner" != "$uid:$gid" ]; then
        chown -R "$uid:$gid" "$dir" 2>/dev/null || true
    fi
}
fix_perms /config "$PUID" "$PGID"
fix_perms /downloads "$PUID" "$PGID"

# Drop privileges and run the daemon as PID 1 so signals are handled cleanly.
if [ "$(id -u)" = "0" ]; then
    exec setpriv --reuid="$PUID" --regid="$PGID" --clear-groups "$@"
fi
exec "$@"
