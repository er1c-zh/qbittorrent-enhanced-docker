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
#   QBT_VERSION   upstream release tag, e.g. "release-5.2.3.10"
#   GOSU_VERSION  gosu helper release (used for dropping privileges at runtime)
#
# Volumes:
#   /config      qBittorrent profile (config, data, cache)
#   /downloads   default download location
#
# Ports:
#   8080         WebUI
#   6881         BitTorrent listen (tcp + udp)

ARG QBT_VERSION=release-5.2.3.10
ARG GOSU_VERSION=1.19

###############################################################################
# Stage 1 - fetch the official static binary for the target architecture
###############################################################################
FROM alpine:3.21 AS fetch

ARG QBT_VERSION
ARG GOSU_VERSION
ARG TARGETPLATFORM

RUN apk add --no-cache curl unzip

# qBittorrent Enhanced Edition static binary (official upstream build)
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

# gosu: the privilege-dropping helper used by the entrypoint (su-exec is not
# packaged in Debian 13, so the official gosu binary is fetched and verified
# against the published SHA256SUMS).
RUN case "$TARGETPLATFORM" in \
        linux/amd64)  gosu_arch=amd64 ;; \
        linux/arm64)  gosu_arch=arm64 ;; \
        linux/arm/v7) gosu_arch=armhf ;; \
        linux/386)    gosu_arch=i386 ;; \
        *) echo "Unsupported TARGETPLATFORM for gosu: $TARGETPLATFORM" >&2; exit 1 ;; \
    esac \
    && curl -fsSL -o "gosu-${gosu_arch}" \
        "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-${gosu_arch}" \
    && curl -fsSL -o SHA256SUMS \
        "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/SHA256SUMS" \
    && grep -E " (gosu-${gosu_arch})\$" SHA256SUMS | sha256sum -c - \
    && install -m 0755 "gosu-${gosu_arch}" /usr/local/bin/gosu

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
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 1000 qbittorrent \
    && useradd --uid 1000 --gid qbittorrent --home-dir /config --shell /usr/sbin/nologin qbittorrent

COPY --from=fetch /usr/local/bin/qbittorrent-nox /usr/local/bin/qbittorrent-nox
COPY --from=fetch /usr/local/bin/gosu /usr/local/bin/gosu
COPY entrypoint.sh /usr/local/bin/qbittorrent-entrypoint
COPY healthcheck.sh /usr/local/bin/qbittorrent-healthcheck

RUN chmod +x /usr/local/bin/qbittorrent-entrypoint /usr/local/bin/qbittorrent-healthcheck

ENV HOME=/config \
    PUID=1000 \
    PGID=1000 \
    TZ=UTC

VOLUME ["/config", "/downloads"]

EXPOSE 8080 6881 6881/udp

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD ["/usr/local/bin/qbittorrent-healthcheck"]

ENTRYPOINT ["/usr/local/bin/qbittorrent-entrypoint"]
CMD ["qbittorrent-nox", "--profile=/config", "--confirm-legal-notice"]
