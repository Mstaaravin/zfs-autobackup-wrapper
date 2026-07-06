# Simple Single Host Backup
Basic setup: One source host backing up a single pool to a remote server. The remote path includes
the hostname directory automatically created by the script.

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│  SOURCE HOST: lhome01                         REMOTE HOST: zima01                                        │
│  ┌─────────────────────────┐                  ┌───────────────────────────────────────────────────────┐  │
│  │  Pool: zpool01          │                  │  WD181KFGX/HOST/                                      │  │
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
│  │  Pool: zpool01          │    │  Pool: zpool01          │    │  WD181KFGX/HOST/                      │ │
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


# Local Mode (Same-Host Backup)
Local setup: With `REMOTE_HOST=""` the target is another pool on the SAME host. No SSH involved —
`zfs send | zfs recv` runs locally. zfs-autobackup automatically excludes the target path from
selection, so received copies are never re-selected as sources. The hostname hierarchy is kept,
so remote and local backups can share the same target pool without collisions.

```
┌────────────────────────────────────────────────────────────────────────────────────┐
│  HOST: zima01                                                                      │
│                                                                                    │
│  ┌─────────────────────────────┐              ┌─────────────────────────────────┐  │
│  │  Pool: zimapool01 (source)  │              │  Pool: WD181KFGX (target)       │  │
│  │  ├─ subvol-101-disk-0       │              │  WD181KFGX/HOST/                │  │
│  │  │    └─ @zimapool01-...    │   local      │    ├─ zima01/   ◄── local mode  │  │
│  │  ├─ subvol-104-disk-0       │   zfs send   │    │   └─ zimapool01/           │  │
│  │  │    └─ @zimapool01-...    │──────────────▸    │        ├─ subvol-101-...   │  │
│  │  └─ ...                     │   zfs recv   │    │        └─ ...              │  │
│  └─────────────────────────────┘              │    └─ lhome01/  ◄── via SSH     │  │
│                                               │        └─ zlhome01/             │  │
│                                               └─────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────────────┘
```


# Complete Backup Flow (Single Execution)
Step-by-step flow for v2.x: config loading, dependency checks, healthchecks.io pings, backup
execution, plain-text summary, age-based log rotation and final status.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  BACKUP EXECUTION FLOW (v2.x)                                               │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────┐          │
│  │ 1. SCRIPT START                                               │          │
│  │    /root/scripts/backup_zfs.sh                                │          │
│  │    └─ Load REQUIRED site config: backup_zfs.conf              │          │
│  │       (REMOTE_HOST, REMOTE_POOL_BASEPATH, SOURCE_POOLS,       │          │
│  │        HEALTHCHECKS_URL, retention settings)                  │          │
│  │       Missing conf or required vars → abort with error        │          │
│  └───────────────────────────────────────────────────────────────┘          │
│                                           │                                 │
│                                           ▼                                 │
│  ┌───────────────────────────────────────────────────────────────┐          │
│  │ 2. CHECKS                                                     │          │
│  │    ✓ running as root?                                         │          │
│  │    ✓ zfs-autobackup installed?                                │          │
│  │    ✓ curl available? (if healthchecks enabled)                │          │
│  │    ✓ pool exists + autobackup property set? (pool argument)   │          │
│  └───────────────────────────────────────────────────────────────┘          │
│                                           │                                 │
│                                           ▼                                 │
│  ┌───────────────────────────────────────────────────────────────┐          │
│  │ 3. NOTIFY START                                               │          │
│  │    curl HEALTHCHECKS_URL/start                                │          │
│  └───────────────────────────────────────────────────────────────┘          │
│                                           │                                 │
│                                           ▼                                 │
│  ┌───────────────────────────────────────────────────────────────┐          │
│  │ 4. ENSURE TARGET STRUCTURE (per pool)                         │          │
│  │    remote mode: ssh zima01 "zfs list BASEPATH/hostname"       │          │
│  │    local mode:  zfs list BASEPATH/hostname                    │          │
│  │    └─ If not exists: auto-create hostname dataset             │          │
│  └───────────────────────────────────────────────────────────────┘          │
│                                           │                                 │
│                                           ▼                                 │
│  ┌───────────────────────────────────────────────────────────────┐          │
│  │ 5. EXECUTE BACKUP (per pool)                                  │          │
│  │    zfs-autobackup -v --keep-source/--keep-target KEEP_POLICY  │          │
│  │      --clear-mountpoint --force [--ssh-target HOST]           │          │
│  │      pool BASEPATH/hostname                                   │          │
│  │                                                               │          │
│  │    Output → console + /root/logs/pool_backup_YYYYMMDD_HHMM.log│          │
│  │    On failure: detect "cannot find common snapshot" and log   │          │
│  │    a remediation hint; log renamed *_FAILED.log               │          │
│  └───────────────────────────────────────────────────────────────┘          │
│                                           │                                 │
│                                           ▼                                 │
│  ┌───────────────────────────────────────────────────────────────┐          │
│  │ 6. BACKUP SUMMARY (plain zfs list, human-readable sizes)      │          │
│  │    DATASETS: name / used / avail / refer                      │          │
│  │    SNAPSHOTS PER DATASET: counts                              │          │
│  │    Duration                                                   │          │
│  │    Written to BOTH: ✓ Console  ✓ Log file                     │          │
│  └───────────────────────────────────────────────────────────────┘          │
│                                           │                                 │
│                                           ▼                                 │
│  ┌───────────────────────────────────────────────────────────────┐          │
│  │ 7. LOG ROTATION (age-based)                                   │          │
│  │    - Normal logs: removed after LOG_RETENTION_DAYS (60d)      │          │
│  │    - *_FAILED.log: kept LOG_RETENTION_DAYS_FAILED (365d)      │          │
│  └───────────────────────────────────────────────────────────────┘          │
│                                           │                                 │
│                                           ▼                                 │
│  ┌───────────────────────────────────────────────────────────────┐          │
│  │ 8. FINAL STATUS + NOTIFY RESULT                               │          │
│  │    POOL: zpool01 | Target: zima01 | Status: ✓ COMPLETED       │          │
│  │      | Last backup: ... | Log: /root/logs/...                 │          │
│  │                                                               │          │
│  │    all pools OK → curl HEALTHCHECKS_URL        (success)      │          │
│  │    any failed   → curl HEALTHCHECKS_URL/fail                  │          │
│  │                   (body: last 40 log lines)                   │          │
│  │    exit code = number of failed pools                         │          │
│  └───────────────────────────────────────────────────────────────┘          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
