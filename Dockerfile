# syntax=docker/dockerfile:1
#
# qBittorrent Enhanced Edition
# (upstream: c0re100/qBittorrent-Enhanced-Edition)
#
# Self-maintained image. The official statically-linked `qbittorrent-enhanced-nox`
# binary is fetched from the upstream GitHub release, so the image stays small and
# reproducible without compiling Qt/libtorrent.
#
# Build args:
#   QBT_VERSION  upstream release tag, e.g. "release-5.2.3.10"
#
# Volumes:
#   /config      qBittorrent profile (config, data, cache)
#   /downloads   default download location
#
# Ports:
#   8080         WebUI
#   6881         BitTorrent listen (tcp + udp)

ARG QBT_VERSION=release-5.2.3.10

###############################################################################
# Stage 1 - fetch the official static binary for the target architecture
###############################################################################
FROM alpine:3.21 AS fetch

ARG QBT_VERSION
ARG TARGETPLATFORM

RUN apk add --no-cache curl unzip

RUN case "$TARGETPLATFORM" in \
        linux/amd64)   arch=x86_64 ;; \
        linux/386)     arch=i686 ;; \
        linux/arm64)   arch=aarch64 ;; \
        linux/arm/v7)  arch=armv7 ;; \
        linux/loong64) arch=loongarch64 ;; \
        *) echo "Unsupported TARGETPLATFORM: $TARGETPLATFORM" >&2; exit 1 ;; \
    esac \
    && curl -fsSL -o qbt.zip \
        "https://github.com/c0re100/qBittorrent-Enhanced-Edition/releases/download/${QBT_VERSION}/qbittorrent-enhanced-nox_${arch}-linux-musl_static.zip" \
    && unzip -o qbt.zip \
    && install -m 0755 qbittorrent-nox /usr/local/bin/qbittorrent-nox

###############################################################################
# Stage 2 - runtime image (Debian 13 / trixie)
###############################################################################
FROM debian:13-slim AS runtime

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        passwd \
        tzdata \
        util-linux \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 1000 qbittorrent \
    && useradd --uid 1000 --gid qbittorrent --home-dir /config --shell /usr/sbin/nologin qbittorrent

COPY --from=fetch /usr/local/bin/qbittorrent-nox /usr/local/bin/qbittorrent-nox
COPY entrypoint.sh /usr/local/bin/qbittorrent-entrypoint
COPY healthcheck.sh /usr/local/bin/qbittorrent-healthcheck

RUN chmod +x /usr/local/bin/qbittorrent-entrypoint /usr/local/bin/qbittorrent-healthcheck

ENV PUID=1000 \
    PGID=1000 \
    TZ=UTC

VOLUME ["/config", "/downloads"]

EXPOSE 8080 6881 6881/udp

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD ["/usr/local/bin/qbittorrent-healthcheck"]

ENTRYPOINT ["/usr/local/bin/qbittorrent-entrypoint"]
CMD ["qbittorrent-nox", "--profile=/config", "--confirm-legal-notice"]
