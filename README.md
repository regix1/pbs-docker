# 🗄️ Proxmox Backup Server in Docker

<div align="center">

[![GitHub Release](https://img.shields.io/github/v/release/regix1/pbs-docker?style=for-the-badge&logo=github)](https://github.com/regix1/pbs-docker/releases)
[![GitHub Stars](https://img.shields.io/github/stars/regix1/pbs-docker?style=for-the-badge&logo=github)](https://github.com/regix1/pbs-docker)
[![License](https://img.shields.io/badge/license-AGPL--3.0-blue?style=for-the-badge)](LICENSE)

**Unofficial Proxmox Backup Server** • **Multi-Architecture** • **No Subscription Nag**

[Quick Start](#-quick-start) • [Features](#-features) • [Installation](#-installation) • [Configuration](#-configuration) • [Support](#-support)

</div>

---

## 🚀 Quick Start

Get up and running in under a minute:

```bash
# Pull and run PBS
docker run -d \
  --name pbs \
  -p 8007:8007 \
  -v pbs-config:/etc/proxmox-backup \
  -v pbs-data:/datastore \
  ghcr.io/regix1/pbs-docker:latest

# Access at https://localhost:8007
# Login: admin / pbspbs (change immediately!)
```

## 📦 Pre-built Images

All images are available on GitHub Container Registry:

| Tag | Description | Architectures |
|-----|-------------|---------------|
| `latest` | Latest stable release | `amd64`, `arm64` |
| `v4.0.13-1` | Specific version | `amd64`, `arm64` |
| `amd64-latest` | AMD64 only | `amd64` |
| `arm64-latest` | ARM64 only | `arm64` |

```bash
# Multi-arch (auto-selects for your platform)
docker pull ghcr.io/regix1/pbs-docker:latest

# Specific architecture
docker pull ghcr.io/regix1/pbs-docker:arm64-latest
```

## 🎯 Features

### ✅ What Works
- ✨ **No Subscription Nag** - Enterprise features without the popups
- 🔄 **Full Backup/Restore** functionality
- 🌐 **Web UI** with all features
- 📊 **Statistics & Monitoring**
- 🔐 **User Management & ACLs**
- 🗂️ **Multiple Datastores**
- 🤖 **API Access**
- 💾 **SMART Monitoring** (with configuration)

### ⚠️ Limitations
- ❌ **ZFS** - Not available in container
- ❌ **Shell Access** - Doesn't make sense in ephemeral containers
- ❌ **PAM Authentication** - Use PBS authentication instead

## 📥 Installation

### Using Docker Compose (Recommended)

1. **Download the compose file:**
```bash
wget https://raw.githubusercontent.com/regix1/pbs-docker/main/docker-compose.yml
```

2. **Start the container:**
```bash
docker-compose up -d
```

3. **Access the web interface:**
   - URL: `https://<your-ip>:8007`
   - Username: `admin`
   - Password: `pbspbs`
   
   ⚠️ **Change the password immediately after first login!**

### Using Docker CLI

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

## ⚙️ Configuration

### 1️⃣ Add to Proxmox VE

Get the PBS fingerprint for adding to Proxmox VE:

```bash
docker exec pbs proxmox-backup-manager cert info | grep Fingerprint
```

Follow the [official integration guide](https://pbs.proxmox.com/docs/pve-integration.html).

### 2️⃣ Add Storage Volumes

Create `docker-compose.override.yml`:

```yaml
version: '3.8'

services:
  pbs:
    volumes:
      - /mnt/storage:/datastore
      - /mnt/usb-backup:/usb-backup
```

### 3️⃣ Configure Timezone

Add to `docker-compose.override.yml`:

```yaml
services:
  pbs:
    environment:
      TZ: America/New_York
```

### 4️⃣ Enable SMART Monitoring

For disk health monitoring, add to `docker-compose.override.yml`:

```yaml
services:
  pbs:
    devices:
      - /dev/sda
      - /dev/sdb
    cap_add:
      - SYS_RAWIO
```

### 5️⃣ Persist All Data (Recommended)

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

## 🔧 Advanced Usage

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TZ` | `UTC` | Timezone |
| `PBS_ENTERPRISE` | `yes` | Enable enterprise repo |
| `PBS_NO_SUBSCRIPTION` | `yes` | Remove subscription check |
| `DISABLE_SUBSCRIPTION_NAG` | `yes` | Remove subscription nag popup |

### Networking

For better performance, consider using host networking:

```yaml
services:
  pbs:
    network_mode: host
```

## 📊 System Requirements

- **CPU**: 2+ cores recommended
- **RAM**: 2GB minimum, 4GB+ recommended
- **Storage**: 10GB for system + your backup storage needs
- **Architecture**: AMD64 or ARM64

## 🛠️ Troubleshooting

### Common Issues

**Authentication Failure:**
- Ensure `/run` is mounted as `tmpfs` (required for PBS 2.1+)
- Use `admin` not `admin@pbs` for login

**Container Won't Start:**
- Check logs: `docker logs pbs`
- Verify ports aren't in use: `netstat -tulpn | grep 8007`

**Slow Performance:**
- Increase memory allocation
- Use host networking mode
- Ensure storage is on fast disks (SSD recommended)

## 🤝 Support

### Original Author & Donations

This project is based on the excellent work by **Kamil Trzciński** (ayufan).

If you find this useful, consider supporting the original author:

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/Y8Y8GCP24)

### This Fork

- 🐛 [Report Issues](https://github.com/regix1/pbs-docker/issues)
- 💡 [Request Features](https://github.com/regix1/pbs-docker/discussions)
- 📖 [View Releases](https://github.com/regix1/pbs-docker/releases)

## 📝 License

This project maintains the same licensing as Proxmox Backup Server (AGPL-3.0).

## 🙏 Credits

- Original dockerization by [Kamil Trzciński](https://github.com/ayufan/pve-backup-server-dockerfiles) (2020-2025)
- Built from sources at [git.proxmox.com](http://git.proxmox.com/)
- Proxmox® is a registered trademark of Proxmox Server Solutions GmbH

---

<div align="center">

**[⬆ Back to Top](#️-proxmox-backup-server-in-docker)**

Made with ❤️ for the Proxmox community

</div>
