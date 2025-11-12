# release_holds.sh

A utility script to release all ZFS holds from snapshots in a given dataset.

## Overview

ZFS holds are mechanisms that prevent snapshots from being destroyed. `zfs-autobackup` uses holds (like `zfs_autobackup:poolname`) to protect snapshots during synchronization operations. This script releases all holds from snapshots, allowing them to be destroyed if needed.

## Usage

```bash
./release_holds.sh <dataset>
```

### Parameters

- `<dataset>`: The ZFS dataset name (required). The script will process this dataset and all its child datasets recursively.

### Examples

Release holds from a specific dataset:
```bash
./release_holds.sh zlhome01/HOME.cmiranda
```

Release holds from an entire pool:
```bash
./release_holds.sh zlhome01
```

Release holds from a backup dataset on a remote system:
```bash
ssh remote-host /path/to/release_holds.sh WD181KFGX/BACKUPS/zlhome01
```

## Output

The script prints each hold as it's being released:

```
Releasing hold 'zfs_autobackup:zlhome01' on zlhome01/HOME.cmiranda@zlhome01-20251109193804
Releasing hold 'zfs_autobackup:zlhome01' on zlhome01/HOME.cmiranda@zlhome01-20251103190001
Releasing hold 'zfs_autobackup:zlhome01' on zlhome01/HOME.cmiranda@zlhome01-20251102190001
```

If no holds are found, the script completes silently.

## When to Use

This script is useful in the following scenarios:

1. **Manual snapshot cleanup**: When you need to destroy snapshots that have holds preventing their deletion
2. **Orphaned holds**: Cleaning up holds left behind from interrupted backup operations
3. **Changing backup configurations**: When switching from one backup tool to another
4. **Troubleshooting**: Resolving issues with snapshots that cannot be destroyed

## How It Works

1. Lists all snapshots recursively under the specified dataset
2. For each snapshot, queries all holds using `zfs holds`
3. Releases each hold found using `zfs release`
4. Processes all child datasets automatically

## Safety Notes

- **Destructive operation**: Once holds are released, snapshots can be destroyed by retention policies or manual commands
- **No confirmation**: The script does not ask for confirmation before releasing holds
- **Recursive**: Affects all child datasets under the specified dataset
- **Immediate effect**: Changes take effect immediately

## Checking Holds Before Release

To see what holds exist before releasing them:

```bash
# List holds for all snapshots in a dataset
zfs holds -r zlhome01/HOME.cmiranda

# List holds for a specific snapshot
zfs holds zlhome01/HOME.cmiranda@zlhome01-20251109193804
```

## Verifying Release

After running the script, verify holds were released:

```bash
zfs holds -r <dataset>
```

If successful, you should see no output or only holds that weren't targeted by the script.

## Related Commands

- `zfs holds [-r] <dataset|snapshot>`: List holds on snapshots
- `zfs release <tag> <snapshot>`: Release a specific hold
- `zfs destroy <snapshot>`: Destroy a snapshot (requires no holds)

## Requirements

- Root or appropriate ZFS permissions
- ZFS utilities installed (`zfs` command available)
- Bash shell

## Exit Codes

- `0`: Success
- `1`: Missing dataset parameter or invalid usage
