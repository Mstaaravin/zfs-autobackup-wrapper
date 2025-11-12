#!/bin/bash
# Release all holds for a given dataset
dataset="$1"

if [ -z "$dataset" ]; then
    echo "Usage: $0 <dataset>"
    exit 1
fi

# Get all snapshots
zfs list -t snapshot -o name -H -r "$dataset" 2>/dev/null | while read snapshot; do
    # Check holds for this snapshot
    zfs holds -H "$snapshot" 2>/dev/null | while IFS=$'\t' read snap_name hold_tag timestamp; do
        if [ -n "$hold_tag" ]; then
            echo "Releasing hold '$hold_tag' on $snapshot"
            zfs release "$hold_tag" "$snapshot"
        fi
    done
done
