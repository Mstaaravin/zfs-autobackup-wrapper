# Simple Single Host Backup
Basic setup: One source host backing up a single pool to a remote server. The remote path includes
the hostname directory automatically created by the script.

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│  SOURCE HOST: lhome01                         REMOTE HOST: zima01                                        │
│  ┌─────────────────────────┐                  ┌───────────────────────────────────────────────────────┐  │
│  │  Pool: zpool01          │                  │  WD181KFGX/BACKUPS/                                   │  │
│  │  ├─ dataset1            │                  │               └─── lhome01/                           │  │
│  │  │    ├─dataset1@snap1  │  ssh + zfs send  │                        └── zpool01/                   │  │
│  │  ├─ dataset2            │─────────────────▸│                               ├─ dataset1             │  │
│  │  │    ├─dataset1@snap1  │                  │                               │    ├─ dataset2@snap1  │  │
│  │  └─ dataset3            │                  │                               ├─ dataset2             │  │
│  │       └──dataset1@snap1 │                  │                               │    ├─ dataset2@snap1  │  │
│  └─────────────────────────┘                  │                               └─ dataset3             │  │
│                                               │                                    └─ dataset3@snap1  │  │
│                                               └───────────────────────────────────────────────────────┘  │
│                                                                                                          │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```


# Multi-Host Organization (No Name Collisions)
Multi-host setup: Multiple source hosts can have pools with identical names. The script automatically
organizes backups by hostname, preventing any naming conflicts.

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│  SOURCE HOST: lhome01           SOURCE HOST: server01          REMOTE HOST: zima01                       │
│  ┌─────────────────────────┐    ┌─────────────────────────┐    ┌───────────────────────────────────────┐ │
│  │  Pool: zpool01          │    │  Pool: zpool01          │    │  WD181KFGX/BACKUPS/                   │ │
│  │  ├─ dataset1            │    │  ├─ database            │    │    ├─ lhome01/                        │ │
│  │  │    ├─ dataset1@snap1 │    │  │    ├─ database@snap1 │    │    │   └─ zpool01/  ◄── from lhome01  │ │
│  │  │    └─ dataset1@snap2 │    │  │    └─ database@snap2 │    │    │        ├─ dataset1               │ │
│  │  └─ dataset2            │    │  └─ configs             │    │    │        │    ├─ dataset1@snap1    │ │
│  │       ├─ dataset2@snap1 │    │       ├─ configs@snap1  │    │    │        │    └─ dataset1@snap2    │ │
│  │       └─ dataset2@snap2 │    │       └─ configs@snap2  │    │    │        └─ dataset2               │ │
│  └─────────────────────────┘    └─────────────────────────┘    │    │             ├─ dataset2@snap1    │ │
│           │                              │                     │    │             └─ dataset2@snap2    │ │
│           │   ssh + zfs send             │                     │    │                                  │ │
│           └──────────────────────────────┼────────────────────▸│    └─ server01/                       │ │
│                                          │                     │        └─ zpool01/  ◄── from server01 │ │
│                                          └────────────────────▸│             ├─ database               │ │
│                                                                │             │    ├─ database@snap1    │ │
│   ✓ Same pool name "zpool01" on both hosts - NO COLLISION!     │             │    └─ database@snap2    │ │
│   ✓ Organized by hostname automatically                        │             └─ configs                │ │
│                                                                │                  ├─ configs@snap1     │ │
│                                                                │                  └─ configs@snap2     │ │
│                                                                └───────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```


# Complete Backup Flow (Single Execution)
Step-by-step flow: Shows the complete execution process from start to finish, including all checks,
backup execution, summary generation, and log rotation. Highlights the v1.1.0 improvement where BACKUP
SUMMARY is written to both console and log file.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  BACKUP EXECUTION FLOW                                                      │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────┐          │
│  │ 1. SCRIPT START (on lhome01)                                  │          │
│  │    ./zfs-autobackup-wrapper.sh                                │          │
│  └───────────────────────────────────────────────────────────────┘          │
│                                           │                                 │
│                                           ▼                                 │
│  ┌───────────────────────────────────────────────────────────────┐          │
│  │ 2. CHECK DEPENDENCIES                                         │          │
│  │    ✓ zfs-autobackup installed?                                │          │
│  │    ✓ SSH access to zima01?                                    │          │
│  │    ✓ Pool exists locally?                                     │          │
│  └───────────────────────────────────────────────────────────────┘          │
│                                           │                                 │
│                                           ▼                                 │
│  ┌───────────────────────────────────────────────────────────────┐          │
│  │ 3. ENSURE REMOTE STRUCTURE                                    │          │
│  │    ssh zima01 "zfs list WD181KFGX/BACKUPS/lhome01"            │          │
│  │    └─ If not exists: auto-create hostname dataset             │          │
│  └───────────────────────────────────────────────────────────────┘          │
│                                           │                                 │
│                                           ▼                                 │
│  ┌───────────────────────────────────────────────────────────────┐          │
│  │ 4. EXECUTE BACKUP                                             │          │
│  │    zfs-autobackup -v --clear-mountpoint --force \             │          │
│  │      --ssh-target zima01 zpool01 WD181KFGX/BACKUPS/lhome01    │          │
│  │                                                               │          │
│  │    Output written to:                                         │          │
│  │    ✓ STDOUT (console)                                         │          │
│  │    ✓ /root/logs/zpool01_backup_20251112_2132.log              │          │
│  └───────────────────────────────────────────────────────────────┘          │
│                                           │                                 │
│                                           ▼                                 │
│  ┌───────────────────────────────────────────────────────────────┐          │
│  │ 5. GENERATE BACKUP SUMMARY                                    │          │
│  │    ===== BACKUP SUMMARY =====                                 │          │
│  │    DATASETS SUMMARY:                                          │          │
│  │    +----------------+------------+----------------------+     │          │
│  │    | Dataset        | Snapshots  | Last Snapshot        |     │          │
│  │    +----------------+------------+----------------------+     │          │
│  │    | zpool01        | 1          | @...20251111...      |     │          │
│  │    | zpool01/docker | 2          | @...20251112...      |     │          │
│  │    +----------------+------------+----------------------+     │          │
│  │                                                               │          │
│  │    Written to BOTH: ✓ Console  ✓ Log file                     │          │
│  └───────────────────────────────────────────────────────────────┘          │
│                                           │                                 │
│                                           ▼                                 │
│  ┌───────────────────────────────────────────────────────────────┐          │
│  │ 6. LOG ROTATION                                               │          │
│  │    - Keep logs matching snapshot dates                        │          │
│  │    - Keep today's log                                         │          │
│  │    - Remove orphaned logs (no matching snapshots)             │          │
│  └───────────────────────────────────────────────────────────────┘          │
│                                           │                                 │
│                                           ▼                                 │
│  ┌───────────────────────────────────────────────────────────────┐          │
│  │ 7. FINAL STATUS                                               │          │
│  │    POOL: zpool01  |  Remote: zima01  |  Status: ✓ COMPLETED   │          │
│  │    Log file: /root/logs/zpool01_backup_20251112_2132.log      │          │
│  │                                                               │          │
│  │    Written to BOTH: ✓ Console  ✓ Log file                     │          │
│  └───────────────────────────────────────────────────────────────┘          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```