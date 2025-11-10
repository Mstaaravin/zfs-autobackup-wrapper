# ZFS Backup Wrapper (Simplified)

A streamlined bash wrapper for zfs-autobackup that focuses on what zfs-autobackup doesn't provide: structured logging, log rotation, and readable reports.

> **Note**: This script wraps the zfs-autobackup utility. Install it separately from: https://github.com/psy0rz/zfs_autobackup

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
Set the autobackup property on each pool:
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

## Usage

```bash
# Backup all configured pools
./zfs-autobackup-wrapper_v1.0.19.sh

# Backup specific pool
./zfs-autobackup-wrapper_v1.0.19.sh zlhome01
```

## Output Example

```
===== BACKUP SUMMARY (2025-11-09 19:50:24) =====
POOL: zlhome01  |  Status: ✓ COMPLETED  |  Last backup: 2025-11-09 19:50:24
Log file: /root/logs/zlhome01_backup_20251109_1938.log

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
00 19 * * * PATH=$PATH:/root/.local/bin /root/scripts/zfs-autobackup-wrapper_v1.0.19.sh > /root/logs/cron_backup.log 2>&1
```

Make the script executable:
```bash
chmod +x /root/scripts/zfs-autobackup-wrapper_v1.0.19.sh
```

## Verification

Compare snapshots on source and target:

**Source system:**
```bash
zfs list -t snapshot zlhome01/HOME.cmiranda
```

**Target system:**
```bash
zfs list -t snapshot WD181KFGX/BACKUPS/zlhome01/HOME.cmiranda
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
