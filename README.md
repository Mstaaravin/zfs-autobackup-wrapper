# ZFS Backup Wrapper (Simplified)

A streamlined bash wrapper for zfs-autobackup that focuses on what zfs-autobackup doesn't provide: structured logging, log rotation, and readable reports.

> **Note**This script wraps the zfs-autobackup utility. Install it separately from: https://github.com/psy0rz/zfs_autobackup

## Features

- Automated ZFS pool backup with remote replication
- Structured logging with timestamps
- Automatic log rotation (keeps only logs with matching snapshots)
- Clean tabular reports showing datasets, snapshots, and space usage
- Support for multiple pools or single pool backup
- Performance optimized with minimal ZFS command invocations

## Prerequisites

### 1. Install zfs-autobackup (Debian/Ubuntu)
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

The `aes128-gcm@openssh.com` cipher uses hardware acceleration for better transfer speeds.

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

## Usage

```bash
# Backup all configured pools
./zfs-autobackup-wrapper.sh

# Backup specific pool
./zfs-autobackup-wrapper.sh zlhome01
```

## Output Example

```
===== BACKUP SUMMARY (2025-11-09 19:50:24) =====

DATASETS SUMMARY:
+--------------------------------+----------------+--------------------------------+---------------+
| Dataset                        | Total Snaps    | Last Snapshot                  | Space Used    |
+--------------------------------+----------------+--------------------------------+---------------+
| zlhome01                       | 1              | zlhome01-20241115013705        | 2.56T         |
| zlhome01/HOME.cmiranda         | 16             | zlhome01-20251109193804        | 2.33T         |
| zlhome01/HOME.root             | 24             | zlhome01-20251109193804        | 15.7G         |
| zlhome01/etc.libvirt.qemu      | 22             | zlhome01-20251109193804        | 640K          |
| zlhome01/var.lib.docker        | 13             | zlhome01-20251027190002        | 108G          |
| zlhome01/var.lib.incus         | 15             | zlhome01-20251109193804        | 17.6G         |
| zlhome01/var.lib.libvirt       | 14             | zlhome01-20251109193804        | 90.5G         |
+--------------------------------+----------------+--------------------------------+---------------+

STATISTICS:
+------------------------+---------------+
| Metric                 | Value         |
+------------------------+---------------+
| Total Datasets         | 7             |
| Total Snapshots        | 105           |
| Snapshots Created      | 1             |
| Snapshots Deleted      | 4             |
| Operation Duration     | 12m 20s       |
+------------------------+---------------+

LOG ROTATION:
[2025-11-09 19:50:24] Cleaning logs for zlhome01 using match_snapshots policy
[2025-11-09 19:50:24] Found 37 unique snapshot dates for zlhome01 (recursive search)
[2025-11-09 19:50:24] Keeping log that matches snapshot date 20251027: /root/logs/zlhome01_backup_20251027_1900.log
[2025-11-09 19:50:24] Removing old log without matching snapshot for date 20251019: /root/logs/zlhome01_backup_20251019_1900.log
[2025-11-09 19:50:25] Log cleanup completed for zlhome01: processed=31, removed=1, kept=30

[2025-11-09 19:50:30] Backup process completed

POOL: zlhome01  |  Remote: zima01  |  Status: ✓ COMPLETED  |  Last backup: 2025-11-09 19:50:24
Log file: /root/logs/zlhome01_backup_20251109_1938.log
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

**Source system:**
```bash
root@lhome01:~# zfs list -t snapshot zlhome01/HOME.cmiranda
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
zlhome01/HOME.cmiranda@zlhome01-20251109193804  4.84G      -  1.92T  -

```

**Target system:**
```bash
root@lhome01:~# ssh zima01 zfs list -t snapshot WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda
NAME                                                               USED  AVAIL     REFER  MOUNTPOINT
WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda@zlhome01-20241115013705  11.1G      -     1.20T  -
WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda@zlhome01-20241214223058  12.4G      -     1.21T  -
WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda@zlhome01-20250113180001  10.5G      -     1.26T  -
WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda@zlhome01-20250211181002  8.57G      -     1.28T  -
WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda@zlhome01-20250313180811  9.80G      -     1.29T  -
WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda@zlhome01-20250505185145  5.58G      -     1.64T  -
WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda@zlhome01-20250512215639  3.99G      -     1.66T  -
WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda@zlhome01-20250611180001  9.39G      -     1.71T  -
WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda@zlhome01-20250719180001  6.28G      -     1.71T  -
WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda@zlhome01-20250810190001  6.42G      -     1.72T  -
WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda@zlhome01-20250909190001  42.6G      -     2.02T  -
WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda@zlhome01-20251009190001  29.2G      -     2.08T  -
WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda@zlhome01-20251016190001  16.1G      -     2.09T  -
WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda@zlhome01-20251023190001  5.42G      -     1.91T  -
WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda@zlhome01-20251026190002  2.74G      -     1.91T  -
WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda@zlhome01-20251027190002  2.60G      -     1.91T  -
WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda@zlhome01-20251028190001  3.21G      -     1.91T  -
WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda@zlhome01-20251029190001  3.37G      -     1.91T  -
WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda@zlhome01-20251030190001  2.20G      -     1.91T  -
WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda@zlhome01-20251031190001  1.68G      -     1.91T  -
WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda@zlhome01-20251101190001  3.63G      -     1.91T  -
WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda@zlhome01-20251102190001  4.62G      -     1.91T  -
WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda@zlhome01-20251103190001  6.69G      -     1.93T  -
WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda@zlhome01-20251109193804     0B      -     1.92T  -
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
