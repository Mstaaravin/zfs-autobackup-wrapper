# ZFS Backup Wrapper

A thin bash wrapper for zfs-autobackup that adds only what zfs-autobackup deliberately leaves out: per-run log files, age-based log rotation, a readable summary, and failure notifications via healthchecks.io.

> [!IMPORTANT]
> This script wraps the zfs-autobackup utility. Install it separately from: https://github.com/psy0rz/zfs_autobackup

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
  - [Install zfs-autobackup](#1-install-zfs-autobackup-debianubuntu-with-root-privileges)
  - [SSH Configuration](#2-ssh-configuration-remote-mode-only)
  - [ZFS Pool Configuration](#3-zfs-pool-configuration)
- [Configuration](#configuration)
- [Local Mode (same-host backups)](#local-mode-same-host-backups)
- [Notifications (healthchecks.io)](#notifications-healthchecksio)
- [Usage](#usage)
- [Output Example](#output-example)
- [Logs](#logs)
- [Automatic Execution (Crontab)](#automatic-execution-crontab)
- [Verification](#verification)
- [Retention Policy](#retention-policy)
- [Useful Links](#useful-links)
- [License](#license)

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│  SOURCE HOST: lhome01                         REMOTE HOST: zima01                        │
│  ┌─────────────────────────┐                  ┌───────────────────────────────────────┐  │
│  │  Pool: zpool01          │                  │  WD181KFGX/HOST/                      │  │
│  │  ├─ dataset1            │                  │     └─── lhome01/                     │  │
│  │  │    ├─dataset1@snap1  │  ssh + zfs send  │           └── zpool01/                │  │
│  │  ├─ dataset2            │─────────────────▸│               ├─ dataset1             │  │
│  │  │    ├─dataset1@snap1  │                  │               │    ├─ dataset2@snap1  │  │
│  │  └─ dataset3            │                  │               ├─ dataset2             │  │
│  │       └──dataset1@snap1 │                  │               │    ├─ dataset2@snap1  │  │
│  └─────────────────────────┘                  │               └─ dataset3             │  │
│                                               │                    └─ dataset3@snap1  │  │
│                                               └───────────────────────────────────────┘  │
│                                                                                          │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

The script automatically organizes backups by hostname, preventing pool name collisions when backing up from multiple hosts to the same remote server.

It also supports **local mode**: backing up a pool to another pool on the same host, with no SSH involved (see [Local Mode](#local-mode-same-host-backups)).

> [!IMPORTANT]
> 📚 **See more examples:** [architecture.md](architecture.md) - Multi-host scenarios, multiple pools, directory structures, and complete backup flow diagrams.

## Features

  - Automated ZFS pool backup with remote (SSH) or local (same-host) replication
  - Hierarchical backup organization by hostname (prevents pool name collisions across multiple hosts)
  - Auto-creates target base datasets on first run
  - Per-run log files with timestamps
  - Age-based log rotation; logs from failed runs are kept longer for diagnosis
  - Failure notifications via [healthchecks.io](https://healthchecks.io) (start/success/fail pings with log excerpt)
  - Detects the "cannot find common snapshot" failure mode and logs a remediation hint
  - Site-specific configuration in a required `.conf` file (the script itself stays fully generic)
  - Support for multiple pools or single pool backup

## Prerequisites

**System Requirements:**
- Linux with ZFS support (Debian, Ubuntu, or similar)
- Root or sudo access
- For remote mode: SSH root access to a backup server with ZFS installed
- `curl` (only if healthchecks.io notifications are enabled)

### 1. Install zfs-autobackup (Debian/Ubuntu) with root privileges
```bash
apt install pipx -y
pipx install zfs-autobackup
pipx ensurepath
```

### 2. SSH Configuration (remote mode only)
Create or edit `/root/.ssh/config`:
```
Host zima01
    HostName 172.16.254.5
    Ciphers aes128-gcm@openssh.com
    Compression no
    IPQoS throughput
```

> [!NOTE]
> The `aes128-gcm@openssh.com` cipher uses hardware acceleration for better transfer speeds.<br />
> The `IPQoS throughput` setting prioritizes data transfer over interactive response, optimizing network packet handling for large backups.

### 3. ZFS Pool Configuration

Set the autobackup property on each pool on the source server:
```bash
zfs set autobackup:poolname=true poolname

# Example:
zfs set autobackup:zlhome01=true zlhome01
```

Verify the property is set:
```bash
zfs get all | grep autobackup
```

Expected output:
```
zlhome01                     autobackup:zlhome01   true   local
zlhome01/HOME.cmiranda       autobackup:zlhome01   true   inherited from zlhome01
zlhome01/HOME.root           autobackup:zlhome01   true   inherited from zlhome01
```

## Configuration

The script contains no site-specific values. All configuration lives in a **required config file next to the script**, named like the script but with a `.conf` extension (e.g. if deployed as `/root/scripts/backup_zfs.sh`, the config is `/root/scripts/backup_zfs.conf`). The script refuses to run without it (and without `REMOTE_POOL_BASEPATH` + `SOURCE_POOLS` set), so the deployed copy stays identical to the repo — only the `.conf` differs per host.

```bash
# /root/scripts/backup_zfs.conf — plain bash, sourced by the wrapper

# Target host (SSH config hostname or IP). Empty string = local mode.
REMOTE_HOST="zima01"

# Base path on the target pool. Backups land in BASEPATH/hostname/poolname
REMOTE_POOL_BASEPATH="WD181KFGX/HOST"

# Source pools to back up when no pool is given on the command line
SOURCE_POOLS=("zlhome01")

# Log directory and retention
LOG_DIR="/root/logs"
LOG_RETENTION_DAYS=60
LOG_RETENTION_DAYS_FAILED=365

# Retention passed to zfs-autobackup (--keep-source / --keep-target)
KEEP_POLICY="10,1d1w,1w1m,1m6m"

# healthchecks.io ping URL (empty = notifications disabled)
HEALTHCHECKS_URL="https://hc-ping.com/<your-uuid>"
```

**Note on REMOTE_HOST:**
- You can use either an SSH config hostname (e.g., `"zima01"`) or a direct IP address
- **Using an SSH config hostname is recommended** as it leverages the SSH config optimizations (hardware-accelerated ciphers, etc.)
- An **empty string** (`""`) switches to local mode

**Note on Backup Organization:**
- Backups are automatically organized by hostname: `REMOTE_POOL_BASEPATH/hostname/poolname`
- Example: Pool `zpool01` from host `lhome01` → `WD181KFGX/HOST/lhome01/zpool01`
- The hostname is detected automatically using `hostname -s`

## Local Mode (same-host backups)

To back up a pool to **another pool on the same host** (e.g. a second disk), set `REMOTE_HOST=""`:

```bash
# backup_zfs.conf on zima01: back up zimapool01 to the WD181KFGX pool locally
REMOTE_HOST=""
REMOTE_POOL_BASEPATH="WD181KFGX/HOST"
SOURCE_POOLS=("zimapool01")
```

In local mode no SSH is involved: `zfs send | zfs recv` runs on the same machine. zfs-autobackup automatically excludes the target path from dataset selection, so the received copies are never re-selected as sources.

## Notifications (healthchecks.io)

If `HEALTHCHECKS_URL` is set, the wrapper pings [healthchecks.io](https://healthchecks.io) (SaaS or self-hosted):

| Ping | When | Meaning |
|---|---|---|
| `URL/start` | Backup begins | Run started; healthchecks times the duration |
| `URL` | All pools succeeded | Success — resets the check timer |
| `URL/fail` | Any pool failed | Immediate alert; the last 40 log lines are attached as the ping body |

Configure the check with a **daily schedule and a grace period** longer than your worst-case backup duration (e.g. 2–3 hours). This also alerts you when the backup *doesn't run at all* (dead cron, host down) — the failure mode no wrapper can report by itself.

## Usage

```bash
# Backup all configured pools
./zfs-autobackup-wrapper.sh

# Backup specific pool
./zfs-autobackup-wrapper.sh zlhome01
```

## Output Example

```
===== BACKUP SUMMARY (2026-07-05 06:37:32) =====

DATASETS:
NAME                        USED  AVAIL  REFER
zlhome01                   2.80T   640G    24K
zlhome01/HOME.cmiranda     2.42T   640G   788G
zlhome01/HOME.root         4.48G   640G   594M
zlhome01/etc.libvirt.qemu   395K   640G  77.5K
zlhome01/var.lib.docker    85.2G   640G  85.2G
zlhome01/var.lib.libvirt    144G   640G   102G

SNAPSHOTS PER DATASET:
      1 zlhome01
     11 zlhome01/HOME.cmiranda
     13 zlhome01/HOME.root
     13 zlhome01/etc.libvirt.qemu
      2 zlhome01/var.lib.docker
     13 zlhome01/var.lib.libvirt

Duration: 0m 24s
[2026-07-05 06:37:32] Log rotation for zlhome01: removed 0 logs older than 60d, 0 failed-run logs older than 365d

POOL: zlhome01  |  Target: zima01  |  Status: ✓ COMPLETED  |  Last backup: 2026-07-05 06:37:32  |  Log: /root/logs/zlhome01_backup_20260705_0637.log
[2026-07-05 06:37:32] Backup process completed
```

## Logs

Logs are stored in `LOG_DIR` (default `/root/logs/`):
- Successful runs: `poolname_backup_YYYYMMDD_HHMM.log`
- Failed runs: `poolname_backup_YYYYMMDD_HHMM_FAILED.log`

### Log Rotation
Rotation is age-based and runs after every backup:
- Normal logs are removed after `LOG_RETENTION_DAYS` (default 60 days)
- Failed-run logs (`*_FAILED.log`) are kept for `LOG_RETENTION_DAYS_FAILED` (default 365 days) so failures stay diagnosable long after the fact

## Automatic Execution (Crontab)

Add to root's crontab:
```bash
# Run daily at 22:30
30 22 * * * PATH=$PATH:/root/.local/bin /root/scripts/backup_zfs.sh > /root/cron_backup.log 2>&1
```

Make the script executable:
```bash
chmod +x /root/scripts/backup_zfs.sh
```

## Verification

Compare snapshots on source and target:

> [!WARNING]
> Source and target snapshots may differ in count and USED values due to different retention policies. The REFER column should match for snapshots with the same name.

**Source system:**
```bash
root@lhome01:~# zfs list -t snapshot -r zlhome01/HOME.cmiranda
```

**Target system:**
```bash
root@lhome01:~# ssh zima01 zfs list -t snapshot -r WD181KFGX/HOST/lhome01/zlhome01/HOME.cmiranda
```

Snapshot names present on both sides should show the same `REFER`; the newest common snapshot is what incremental replication builds on.

## Retention Policy

The wrapper passes `KEEP_POLICY` (default `10,1d1w,1w1m,1m6m`) to zfs-autobackup as both `--keep-source` and `--keep-target`:
- Keep the last 10 snapshots
- Keep every 1 day, delete after 1 week
- Keep every 1 week, delete after 1 month
- Keep every 1 month, delete after 6 months

See the [zfs-autobackup thinning documentation](https://github.com/psy0rz/zfs_autobackup/wiki/Manual) for the schedule syntax.

## Useful Links

- [ZFS Autobackup Official Repository](https://github.com/psy0rz/zfs_autobackup)
- [Automating ZFS Snapshots for Peace of Mind](https://it-notes.dragas.net/2024/08/21/automating-zfs-snapshots-for-peace-of-mind/)
- [OpenZFS Documentation](https://openzfs.github.io/openzfs-docs/)

## License

MIT
