# Proxmox Backup Server in Docker

[![GitHub Release](https://img.shields.io/github/v/release/regix1/pbs-docker?style=for-the-badge&logo=github)](https://github.com/regix1/pbs-docker/releases)
[![GitHub Stars](https://img.shields.io/github/stars/regix1/pbs-docker?style=for-the-badge&logo=github)](https://github.com/regix1/pbs-docker)
[![License](https://img.shields.io/badge/license-AGPL--3.0-blue?style=for-the-badge)](LICENSE)

Unofficial Proxmox Backup Server built for Docker. Multi-architecture support (amd64/arm64) with subscription nag removal built in.

---

## Quick Start

```bash
docker run -d \
  --name pbs \
  -p 8007:8007 \
  -v pbs-config:/etc/proxmox-backup \
  -v pbs-data:/datastore \
  ghcr.io/regix1/pbs-docker:latest
```

Then open `https://localhost:8007` and log in with `admin` / `pbspbs`. Change the password immediately.

## Pre-built Images

Images are published to GitHub Container Registry:

| Tag | Description | Architectures |
|-----|-------------|---------------|
| `latest` | Latest stable release | amd64, arm64 |
| `amd64-latest` | AMD64 only | amd64 |
| `arm64-latest` | ARM64 only | arm64 |

```bash
# Multi-arch (auto-selects for your platform)
docker pull ghcr.io/regix1/pbs-docker:latest

# Specific architecture
docker pull ghcr.io/regix1/pbs-docker:arm64-latest
```

## What Works

- **Subscription nag removal** - No popups on desktop or mobile views
- **Full backup/restore** - All PBS backup functionality
- **Web UI** - Complete web interface
- **Statistics and monitoring** - Dashboard and metrics
- **User management and ACLs** - Full access control
- **Multiple datastores** - Add as many as you need
- **API access** - Full REST API
- **SMART monitoring** - With device passthrough (see configuration)

## Limitations

- **ZFS** - Not available inside containers
- **Shell access** - Disabled (ephemeral container, wouldn't persist anyway)
- **PAM authentication** - Use PBS authentication instead

## Installation

### Docker Compose (Recommended)

Download the compose file:

```bash
wget https://raw.githubusercontent.com/regix1/pbs-docker/main/docker-compose.yml
```

Start the container:

```bash
docker-compose up -d
```

Access the web interface at `https://<your-ip>:8007` with username `admin` and password `pbspbs`. Change the password after first login.

### Docker CLI

```bash
docker run -d \
  --name proxmox-backup-server \
  --hostname pbs \
  -p 8007:8007 \
  -v /path/to/config:/etc/proxmox-backup \
  -v /path/to/logs:/var/log/proxmox-backup \
  -v /path/to/lib:/var/lib/proxmox-backup \
  -v /path/to/datastore:/datastore \
  --cap-add SYS_ADMIN \
  --cap-add NET_ADMIN \
  ghcr.io/regix1/pbs-docker:latest
```

## Configuration

### Adding to Proxmox VE

Get the PBS fingerprint:

```bash
docker exec pbs proxmox-backup-manager cert info | grep Fingerprint
```

Then follow the [official integration guide](https://pbs.proxmox.com/docs/pve-integration.html).

### Adding Storage Volumes

Create `docker-compose.override.yml`:

```yaml
version: '3.8'

services:
  pbs:
    volumes:
      - /mnt/storage:/datastore
      - /mnt/usb-backup:/usb-backup
```

### Timezone

```yaml
services:
  pbs:
    environment:
      TZ: America/New_York
```

### SMART Monitoring

Pass through your drives and add the required capability:

```yaml
services:
  pbs:
    devices:
      - /dev/sda
      - /dev/sdb
    cap_add:
      - SYS_RAWIO
```

### Persist All Data

For production use, bind mount everything:

```yaml
volumes:
  pbs_config:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /srv/pbs/config
  pbs_logs:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /srv/pbs/logs
  pbs_lib:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /srv/pbs/lib
  pbs_datastore:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /srv/pbs/datastore
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TZ` | `UTC` | Container timezone |
| `PBS_ENTERPRISE` | `no` | Use enterprise apt repository |
| `PBS_NO_SUBSCRIPTION` | `yes` | Use no-subscription apt repository |
| `DISABLE_SUBSCRIPTION_NAG` | `yes` | Remove subscription popup from web UI |

## Subscription Nag Removal

The container includes a service that patches the Proxmox web interface to remove subscription warnings. This runs automatically at startup and watches for file changes (handles apt upgrades gracefully).

**What gets patched:**

- Desktop subscription status checks
- Mobile view subscription banners
- ExtJS popup dialogs
- CSS warning indicators
- The `checked_command` subscription verification function

**Directories monitored:**

- `/usr/share/javascript/proxmox-widget-toolkit`
- `/usr/share/javascript/proxmox-backup`
- `/usr/share/pbs-docs`
- `/usr/share/javascript/pbs`

The service uses `inotifywait` for efficient file monitoring. If a JS file gets replaced (e.g., during an update), patches are automatically reapplied.

To disable nag removal, set `DISABLE_SUBSCRIPTION_NAG=no` in your environment.

## Networking

For better performance, especially with large backups:

```yaml
services:
  pbs:
    network_mode: host
```

## System Requirements

- **CPU**: 2+ cores recommended
- **RAM**: 2GB minimum, 4GB+ recommended
- **Storage**: 10GB for system + your backup storage
- **Architecture**: AMD64 or ARM64

## Troubleshooting

**Authentication failure:**
- Make sure `/run` is mounted as tmpfs (required for PBS 2.1+)
- Use `admin` not `admin@pbs` for the username

**Container won't start:**
- Check logs: `docker logs pbs`
- Verify port 8007 isn't already in use

**Slow performance:**
- Increase container memory
- Use host networking
- Put storage on SSDs

## Support

This project is based on work by [Kamil Trzciński](https://github.com/ayufan/pve-backup-server-dockerfiles) (ayufan).

If you find this useful, consider supporting the original author:

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/Y8Y8GCP24)

**This Fork:**

- [Report Issues](https://github.com/regix1/pbs-docker/issues)
- [Request Features](https://github.com/regix1/pbs-docker/discussions)
- [View Releases](https://github.com/regix1/pbs-docker/releases)

## License

AGPL-3.0, same as Proxmox Backup Server.

## Credits

- Original dockerization by [Kamil Trzciński](https://github.com/ayufan/pve-backup-server-dockerfiles) (2020-2025)
- Built from sources at [git.proxmox.com](http://git.proxmox.com/)
- Proxmox is a registered trademark of Proxmox Server Solutions GmbH
