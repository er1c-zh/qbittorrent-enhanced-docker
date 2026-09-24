#!/bin/sh
set -eux

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
TZ="${TZ:-UTC}"

echo "==> qBittorrent Enhanced Edition container starting"
echo "==> detected PUID=${PUID} PGID=${PGID} TZ=${TZ}"

# Set the timezone.
if [ -e "/usr/share/zoneinfo/$TZ" ]; then
    ln -sfn "/usr/share/zoneinfo/$TZ" /etc/localtime
    printf '%s\n' "$TZ" > /etc/timezone
fi

# Required directories.
mkdir -p /config /downloads

# ---- Runtime user handling (LinuxServer-style) ----
# Ensure the qbittorrent user has a real /etc/passwd + /etc/group entry with the
# requested PUID/PGID. A numeric-only privilege drop (setpriv) leaves the process
# without a passwd entry, which crashes qBittorrent at startup on some hosts.
if [ "$(id -u)" = "0" ]; then
    groupmod -o -g "${PGID}" qbittorrent 2>/dev/null \
        || groupadd -g "${PGID}" qbittorrent
    usermod -o -u "${PUID}" -g "${PGID}" -d /config qbittorrent 2>/dev/null \
        || useradd -u "${PUID}" -g "${PGID}" -d /config -s /usr/sbin/nologin qbittorrent
    echo "==> runtime user qbittorrent: uid=$(id -u qbittorrent) gid=$(id -g qbittorrent)"
else
    echo "==> running as uid=$(id -u), skipping user/group creation"
fi

# ---- Configuration seed (first run only) ----
CONF_FILE="/config/qBittorrent/config/qBittorrent.conf"
if [ ! -f "$CONF_FILE" ]; then
    echo "==> seeding default configuration: ${CONF_FILE}"
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

# ---- Permission handling ----
# Make sure the volumes are writable by the runtime user, but only recurse when
# ownership actually differs (avoids scanning huge download trees every start).
fix_perms() {
    dir="$1"
    uid="$2"
    gid="$3"
    owner="$(stat -c '%u:%g' "$dir" 2>/dev/null || true)"
    if [ "$owner" != "${uid}:${gid}" ]; then
        echo "==> setting ownership of ${dir} to ${uid}:${gid}"
        chown -R "${uid}:${gid}" "$dir"
    else
        echo "==> ${dir} already owned by ${uid}:${gid}, skipping"
    fi
}
fix_perms /config "$PUID" "$PGID"
fix_perms /downloads "$PUID" "$PGID"

# The top-level mount owner can already match PUID:PGID while the profile
# directories created during seeding are still root-owned; qBittorrent would
# then fail to create its cache/data dirs. Ensure the profile root itself is
# owned by the runtime user (it only holds config/data/cache, so this is cheap).
QBT_PROFILE="/config/qBittorrent"
if [ -e "$QBT_PROFILE" ]; then
    owner="$(stat -c '%u:%g' "$QBT_PROFILE" 2>/dev/null || true)"
    if [ "$owner" != "${PUID}:${PGID}" ]; then
        echo "==> setting ownership of ${QBT_PROFILE} to ${PUID}:${PGID}"
        chown -R "${PUID}:${PGID}" "$QBT_PROFILE"
    fi
fi

# ---- Launch ----
if [ "$(id -u)" = "0" ]; then
    echo "==> dropping privileges, executing: gosu qbittorrent $*"
    exec gosu qbittorrent "$@"
fi
echo "==> executing: $*"
exec "$@"
