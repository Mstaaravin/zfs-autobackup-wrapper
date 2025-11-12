# ZFS Backup Wrapper (Simplified)

A streamlined bash wrapper for zfs-autobackup that focuses on what zfs-autobackup doesn't provide: structured logging, log rotation, and readable reports.

> [!IMPORTANT]
> This script wraps the zfs-autobackup utility. Install it separately from: https://github.com/psy0rz/zfs_autobackup

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
  - [Install zfs-autobackup](#1-install-zfs-autobackup-debianubuntu-with-root-privileges)
  - [SSH Configuration](#2-ssh-configuration)
  - [ZFS Pool Configuration](#3-zfs-pool-configuration)
- [Configuration](#configuration)
- [Usage](#usage)
- [Output Example](#output-example)
- [Logs](#logs)
- [Automatic Execution (Crontab)](#automatic-execution-crontab)
- [Verification](#verification)
- [Retention Policy](#retention-policy)
- [Useful Links](#useful-links)
- [License](#license)

## Features

  - Automated ZFS pool backup with remote replication
  - Hierarchical backup organization by hostname (prevents pool name collisions across multiple hosts)
  - Auto-creates remote destination datasets on first run
  - Structured logging with timestamps
  - Automatic log rotation (keeps only logs with matching snapshots)
  - Clean tabular reports showing datasets, snapshots, and space usage
  - Support for multiple pools or single pool backup
  - Performance optimized with minimal ZFS command invocations



## Prerequisites

**System Requirements:**
- Linux with ZFS support (Debian, Ubuntu, or similar)
- Root or sudo access
- SSH root access to remote backup server with ZFS installed

### 1. Install zfs-autobackup (Debian/Ubuntu) with root privileges
```bash
apt install pipx -y
pipx install zfs-autobackup
pipx ensurepath
```

### 2. SSH Configuration
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
We'll use this pool and its respective datasets as an example.
```bash
root@lhome01:~# zfs list
NAME                        USED  AVAIL  REFER  MOUNTPOINT
zlhome01                   2.57T   879G    24K  none
zlhome01/HOME.cmiranda     2.34T   879G  1.92T  /home/cmiranda
zlhome01/HOME.root         15.7G   879G  3.93G  /root
zlhome01/etc.libvirt.qemu   640K   879G    65K  /etc/libvirt/qemu
zlhome01/var.lib.docker     109G   879G  88.5G  /var/lib/docker
zlhome01/var.lib.incus     17.6G   879G  4.57G  /var/lib/incus
zlhome01/var.lib.libvirt   90.6G   879G  43.1G  /var/lib/libvirt
```

Set the autobackup property on each pool on origin server (lhome01):
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

Edit the script variables:

```bash
# Remote destination host (SSH config hostname or IP)
REMOTE_HOST="zima01"

# Remote pool base path where backups will be stored
# Backups are organized hierarchically as: BASEPATH/hostname/poolname
# This prevents pool name collisions across multiple source hosts
REMOTE_POOL_BASEPATH="WD181KFGX/BACKUPS"

# Log directory
LOG_DIR="/root/logs"

# Source pools to backup when no specific pool is provided
SOURCE_POOLS=(
    "zlhome01"
)
```

**Note on REMOTE_HOST:**
- You can use either an SSH config hostname (e.g., `"zima01"`) or a direct IP address (e.g., `"192.168.1.100"`)
- **Using an SSH config hostname is recommended** as it leverages the SSH config optimizations (hardware-accelerated ciphers, compression settings, etc.)
- Using a direct IP address will work but bypasses the SSH config optimizations, resulting in slower transfer speeds

**Note on Backup Organization:**
- Backups are automatically organized by hostname: `REMOTE_POOL_BASEPATH/hostname/poolname`
- Example: Pool `zpool01` from host `lhome01` → `WD181KFGX/BACKUPS/lhome01/zpool01`
- This prevents collisions when backing up pools with the same name from different hosts
- The hostname is detected automatically using `hostname -s`

## Usage

```bash
# Backup all configured pools
./zfs-autobackup-wrapper.sh

# Backup specific pool
./zfs-autobackup-wrapper.sh zlhome01
```

## Output Example

```
===== BACKUP SUMMARY (2025-11-11 22:10:43) =====

DATASETS SUMMARY:
+--------------------------------+----------------+--------------------------------+---------------+
| Dataset                        | Total Snaps    | Last Snapshot                  | Space Used    |
+--------------------------------+----------------+--------------------------------+---------------+
| zpool01                        | 1              | zpool01-20251111220955         | 146911666     |
| zpool01/docker                 | 1              | zpool01-20251111220955         | 31372         |
| zpool01/nextcloud              | 1              | zpool01-20251111220955         | 31372         |
| zpool01/var.lib.incus          | 1              | zpool01-20251111220955         | 136449104     |
+--------------------------------+----------------+--------------------------------+---------------+

STATISTICS:
+------------------------+---------------+
| Metric                 | Value         |
+------------------------+---------------+
| Total Datasets         | 4             |
| Total Snapshots        | 4             |
| Snapshots Created      | 1             |
| Snapshots Deleted      | 0             |
| Operation Duration     | 48s           |
+------------------------+---------------+

LOG ROTATION:
[2025-11-11 22:10:43] Cleaning logs for zpool01 using match_snapshots policy
[2025-11-11 22:10:43] Found 1 unique snapshot dates for zpool01 (recursive search)
[2025-11-11 22:10:43] Sample extracted dates: 20251111 
[2025-11-11 22:10:43] Date range: 20251111 to 20251111
[2025-11-11 22:10:43] Keeping current day log: /root/logs/zpool01_backup_20251111_2209.log
[2025-11-11 22:10:43] Keeping current day log: /root/logs/zpool01_backup_20251111_0849.log
[2025-11-11 22:10:43] Keeping current day log: /root/logs/zpool01_backup_20251111_0847.log
[2025-11-11 22:10:43] Keeping current day log: /root/logs/zpool01_backup_20251111_2131.log
[2025-11-11 22:10:43] Keeping current day log: /root/logs/zpool01_backup_20251111_0833.log
[2025-11-11 22:10:43] Keeping current day log: /root/logs/zpool01_backup_20251111_0907.log
[2025-11-11 22:10:43] Keeping current day log: /root/logs/zpool01_backup_20251111_2148.log
[2025-11-11 22:10:43] Keeping current day log: /root/logs/zpool01_backup_20251111_0842.log
[2025-11-11 22:10:43] Keeping current day log: /root/logs/zpool01_backup_20251111_0834.log
[2025-11-11 22:10:43] Log cleanup completed for zpool01: processed=9, removed=0, kept=9
[2025-11-11 22:10:48] Backup process completed

POOL: zpool01  |  Remote: zima01  |  Status: ✓ COMPLETED  |  Last backup: 2025-11-11 22:10:43
Log file: /root/logs/zpool01_backup_20251111_2209.log

```

## Logs

Logs are stored in `/root/logs/`:
- Individual pool backup logs: `poolname_backup_YYYYMMDD_HHMM.log`

### Log Rotation
The script automatically removes old logs that don't have matching snapshots, keeping your log directory clean while preserving logs for existing backups.

## Automatic Execution (Crontab)

Add to root's crontab:
```bash
# Run daily at 19:00
00 19 * * * PATH=$PATH:/root/.local/bin /root/scripts/zfs-autobackup-wrapper.sh > /root/logs/cron_backup.log 2>&1
```

Make the script executable:
```bash
chmod +x /root/scripts/zfs-autobackup-wrapper.sh
```

## Verification

Compare snapshots on source and target:

> [!WARNING]
> Source and target snapshots may differ in count and USED values due to different retention policies. The REFER column should match for snapshots with the same name.

**Source system:**
```bash
root@lhome01:~# zfs list
NAME                        USED  AVAIL  REFER  MOUNTPOINT
zlhome01                   2.57T   873G    24K  none
zlhome01/HOME.cmiranda     2.34T   873G  1.92T  /home/cmiranda
zlhome01/HOME.root         15.7G   873G  3.93G  /root
zlhome01/etc.libvirt.qemu   666K   873G    66K  /etc/libvirt/qemu
zlhome01/var.lib.docker     109G   873G  88.5G  /var/lib/docker
zlhome01/var.lib.incus     17.7G   873G  4.59G  /var/lib/incus
zlhome01/var.lib.libvirt   93.8G   873G  43.5G  /var/lib/libvirt

root@lhome01:~# zfs list -t snapshot -r zlhome01/HOME.cmiranda
NAME                                             USED  AVAIL  REFER  MOUNTPOINT
zlhome01/HOME.cmiranda@zlhome01-20250731180001  6.63G      -  1.71T  -
zlhome01/HOME.cmiranda@zlhome01-20250810190001  5.67G      -  1.71T  -
zlhome01/HOME.cmiranda@zlhome01-20250909190001  42.0G      -  2.01T  -
zlhome01/HOME.cmiranda@zlhome01-20251009190001  28.7G      -  2.08T  -
zlhome01/HOME.cmiranda@zlhome01-20251016190001  15.8G      -  2.08T  -
zlhome01/HOME.cmiranda@zlhome01-20251023190001  5.25G      -  1.90T  -
zlhome01/HOME.cmiranda@zlhome01-20251026190002  2.66G      -  1.90T  -
zlhome01/HOME.cmiranda@zlhome01-20251027190002  2.56G      -  1.91T  -
zlhome01/HOME.cmiranda@zlhome01-20251028190001  3.17G      -  1.91T  -
zlhome01/HOME.cmiranda@zlhome01-20251029190001  3.32G      -  1.91T  -
zlhome01/HOME.cmiranda@zlhome01-20251030190001  2.12G      -  1.91T  -
zlhome01/HOME.cmiranda@zlhome01-20251031190001  1.61G      -  1.91T  -
zlhome01/HOME.cmiranda@zlhome01-20251101190001  3.56G      -  1.91T  -
zlhome01/HOME.cmiranda@zlhome01-20251102190001  4.53G      -  1.91T  -
zlhome01/HOME.cmiranda@zlhome01-20251103190001  6.58G      -  1.92T  -
zlhome01/HOME.cmiranda@zlhome01-20251109193804  4.93G      -  1.92T  -
```

**Target system:**
```bash
root@lhome01:~# ssh zima01 zfs list -r WD181KFGX/BACKUPS/lhome01
NAME                                                        USED  AVAIL     REFER  MOUNTPOINT
WD181KFGX/BACKUPS/lhome01                                  2.98T  2.55T       96K  none
WD181KFGX/BACKUPS/lhome01/zlhome01                         2.98T  2.55T       96K  none
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda           2.60T  2.55T     1.92T  /home/cmiranda
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.root               15.8G  2.55T     3.94G  /root
WD181KFGX/BACKUPS/lhome01/zlhome01/etc.libvirt.qemu        2.46M  2.55T      212K  /etc/libvirt/qemu
WD181KFGX/BACKUPS/lhome01/zlhome01/var.lib.docker           160G  2.55T     89.1G  /var/lib/docker
WD181KFGX/BACKUPS/lhome01/zlhome01/var.lib.incus           19.5G  2.55T     5.30G  /var/lib/incus
WD181KFGX/BACKUPS/lhome01/zlhome01/var.lib.libvirt         99.7G  2.55T     47.6G  /var/lib/libvirt

root@lhome01:~# ssh zima01 zfs list -t snapshot -r WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda
NAME                                                                       USED  AVAIL     REFER  MOUNTPOINT
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda@zlhome01-20241115013705  11.1G      -     1.20T  -
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda@zlhome01-20241214223058  12.4G      -     1.21T  -
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda@zlhome01-20250113180001  10.5G      -     1.26T  -
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda@zlhome01-20250211181002  8.57G      -     1.28T  -
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda@zlhome01-20250313180811  9.80G      -     1.29T  -
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda@zlhome01-20250505185145  5.58G      -     1.64T  -
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda@zlhome01-20250512215639  3.99G      -     1.66T  -
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda@zlhome01-20250611180001  9.39G      -     1.71T  -
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda@zlhome01-20250719180001  6.28G      -     1.71T  -
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda@zlhome01-20250810190001  6.42G      -     1.72T  -
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda@zlhome01-20250909190001  42.6G      -     2.02T  -
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda@zlhome01-20251009190001  29.2G      -     2.08T  -
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda@zlhome01-20251016190001  16.1G      -     2.09T  -
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda@zlhome01-20251023190001  5.42G      -     1.91T  -
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda@zlhome01-20251026190002  2.74G      -     1.91T  -
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda@zlhome01-20251027190002  2.60G      -     1.91T  -
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda@zlhome01-20251028190001  3.21G      -     1.91T  -
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda@zlhome01-20251029190001  3.37G      -     1.91T  -
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda@zlhome01-20251030190001  2.20G      -     1.91T  -
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda@zlhome01-20251031190001  1.68G      -     1.91T  -
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda@zlhome01-20251101190001  3.63G      -     1.91T  -
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda@zlhome01-20251102190001  4.62G      -     1.91T  -
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda@zlhome01-20251103190001  6.69G      -     1.93T  -
WD181KFGX/BACKUPS/lhome01/zlhome01/HOME.cmiranda@zlhome01-20251109193804     0B      -     1.92T  -

```


The backup summary report provides an overview of all datasets, snapshots, and operations.

## Retention Policy

zfs-autobackup manages snapshot retention with these default settings:
- Keep the last 10 snapshots
- Keep every 1 day, delete after 1 week
- Keep every 1 week, delete after 1 month
- Keep every 1 month, delete after 1 year

These are configured in zfs-autobackup itself, not in the wrapper script.

## Useful Links

- [ZFS Autobackup Official Repository](https://github.com/psy0rz/zfs_autobackup)
- [Automating ZFS Snapshots for Peace of Mind](https://it-notes.dragas.net/2024/08/21/automating-zfs-snapshots-for-peace-of-mind/)
- [OpenZFS Documentation](https://openzfs.github.io/openzfs-docs/)

## License

MIT
