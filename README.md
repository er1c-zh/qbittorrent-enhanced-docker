# qbittorrent-enhanced-docker

Self-maintained Docker image for [qBittorrent Enhanced Edition](https://github.com/c0re100/qBittorrent-Enhanced-Edition).

The image bundles the official statically-linked `qbittorrent-enhanced-nox` binary
published by the upstream project — no compilation, no inconsistent third-party
binaries. The CI workflow resolves the latest upstream release and republishes the
image automatically.

**Status: Phase 1** — repository structure, Docker build system, GitHub Actions CI,
basic runtime image. Peer blocking, Xunlei/Thunder client filtering, homelab
monitoring and custom UI are later phases (see [Roadmap](#roadmap)).

## Image

| Registry | Image |
| --- | --- |
| GitHub Container Registry | `ghcr.io/er1c-zh/qbittorrent-enhanced` |

Tags: `latest`, plus one per upstream release (e.g. `release-5.2.3.10`).

## Quick start

```bash
mkdir -p config downloads
docker run -d \
  --name qbittorrent \
  -p 8080:8080 \
  -p 6881:6881 \
  -p 6881:6881/udp \
  -v "$PWD/config:/config" \
  -v "$PWD/downloads:/downloads" \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=Asia/Shanghai \
  ghcr.io/er1c-zh/qbittorrent-enhanced:latest
```

Or with Docker Compose:

```yaml
# compose.yaml
services:
  qbittorrent:
    image: ghcr.io/er1c-zh/qbittorrent-enhanced:latest
    container_name: qbittorrent
    environment:
      PUID: "1000"
      PGID: "1000"
      TZ: Asia/Shanghai
    volumes:
      - ./config:/config
      - ./downloads:/downloads
    ports:
      - "8080:8080"
      - "6881:6881"
      - "6881:6881/udp"
    restart: unless-stopped
```

Open the WebUI at `http://<host>:8080`. On first run qBittorrent generates a
temporary password and prints it to the container logs — set your own password
under *Tools → Options → WebUI*.

## Configuration

### Volumes

| Path | Purpose |
| --- | --- |
| `/config` | qBittorrent profile — config, data and cache (`/config/qBittorrent/`) |
| `/downloads` | Default save location for finished and in-progress downloads |

On first start the image seeds a minimal config so the container works out of the
box (WebUI on port `8080`, listening port `6881`, save path `/downloads`). The
file lives at `/config/qBittorrent/config/qBittorrent.conf` and is owned by the
WebUI from then on.

### Ports

| Port | Protocol | Purpose |
| --- | --- | --- |
| `8080` | TCP | WebUI |
| `6881` | TCP/UDP | BitTorrent listen |

### Environment variables

| Variable | Default | Description |
| --- | --- | --- |
| `PUID` | `1000` | User ID the daemon runs as; volume contents are chowned to it |
| `PGID` | `1000` | Group ID the daemon runs as |
| `TZ` | `UTC` | Container timezone (IANA name, e.g. `Asia/Shanghai`) |

The daemon runs as an unprivileged user. If you already mounted volumes owned by
another UID/GID, set `PUID`/`PGID` to match (ownership is fixed only when it
differs, so large download trees are not rescanned on every start).

## Local build

```bash
docker build --build-arg QBT_VERSION=release-5.2.3.10 -t qbittorrent-enhanced .
```

The upstream tag can be looked up with:

```bash
gh api repos/c0re100/qBittorrent-Enhanced-Edition/releases/latest --jq .tag_name
```

## CI / release automation

`.github/workflows/build.yml` builds and publishes to GHCR:

- on **push** to `main` when image files change;
- on a **weekly schedule** — resolves the latest upstream release, skips if that
  version is already published, otherwise builds and retags `latest`;
- on **manual dispatch** (`workflow_dispatch`).

Multi-platform builds are prepared in the `Dockerfile` (x86_64, aarch64, armv7,
i686, loongarch64 map to upstream static assets) and are gated to
`linux/amd64` in CI for now.

## Roadmap

- [x] Phase 1: repository structure, Docker build system, GitHub Actions CI, basic runtime image
- [ ] Peer/blocklist-based bad client blocking
- [ ] Xunlei / Thunder client filtering
- [ ] Homelab monitoring integration
- [ ] Custom UI

## License

The repository's own files (Dockerfile, scripts, docs) are licensed under
[GPL-2.0](LICENSE). The image bundles the official qBittorrent Enhanced Edition
build, which is GPLv2 software (see upstream
[c0re100/qBittorrent-Enhanced-Edition](https://github.com/c0re100/qBittorrent-Enhanced-Edition)).
