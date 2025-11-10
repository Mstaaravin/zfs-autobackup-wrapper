#!/usr/bin/env bash
#
# Copyright (c) 2024-2025. All rights reserved.
#
# Name: zfs-autobackup-wrapper.sh
# Version: 1.0.19
# Author: Mstaaravin
# Description: Simplified ZFS backup wrapper with efficient logging and monitoring
#             Focuses on what zfs-autobackup doesn't provide: structured logging,
#             log rotation, and readable reports.
#
# Changelog v1.0.19:
#   - Added final summary output showing pool, remote host, status, and log file
#   - Improved reporting consistency with remote backup information
#
# Changelog v1.0.18:
#   - Removed redundant check_recent_snapshots() - zfs-autobackup handles this
#   - Removed complex snapshot categorization - simplified to total counts
#   - Removed monthly distribution and retention policy displays
#   - Optimized dataset info collection to single-pass approach
#   - Reduced script complexity by ~200 lines while maintaining core value
#   - Performance improvement: 3x fewer zfs command invocations
#
# Usage: ./zfs-autobackup-wrapper.sh [pool_name]
#
# Exit codes:
#   0 - Success
#   1 - Dependency check failed/Pool validation failed
#

# Ensure script fails on any error
set -e

# Enable debug mode for cron troubleshooting
# set -x

# Global configuration

# Remote destination - can be either:
# - SSH config hostname (in ~/.ssh/config, e.g., "zima01")
# - Direct IP address (e.g., "192.168.1.100")
# Requires SSH key authentication and ZFS permissions on remote host (normally using root)
REMOTE_HOST="zima01"
REMOTE_POOL_BASEPATH="WD181KFGX/BACKUPS"

# Basic logging configuration and date formats
LOG_DIR="/root/logs"
DATE=$(date +%Y%m%d_%H%M)                         # Used for filenames (YYYYMMDD)
TIMESTAMP="[$(date '+%Y-%m-%d %H:%M:%S')]"   # Used for log messages
START_TIME=$(date +%s)                       # Used for duration calculation

# Function to update timestamp
update_timestamp() {
    TIMESTAMP="[$(date '+%Y-%m-%d %H:%M:%S')]"
}

# Ensure PATH includes necessary directories
export PATH="/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# Source pools to backup if none specified
SOURCE_POOLS=(
    "zlhome01"
)

# For tracking statistics (simplified)
declare -A BACKUP_STATS
declare -A DATASETS_INFO
declare -a CREATED_SNAPSHOTS

# Logs messages to both syslog and stdout
# Uses global TIMESTAMP for consistency
log_message() {
    update_timestamp
    echo "${TIMESTAMP} $1" | logger -t zfs-backup
    echo "${TIMESTAMP} $1"
}

# Check if running as root
if [ "$(id -u)" != "0" ]; then
    log_message "Error: This script must be run as root"
    exit 1
fi

# Verifies zfs-autobackup is installed and accessible
check_dependencies() {
    if ! command -v zfs-autobackup >/dev/null 2>&1; then
        log_message "Error: zfs-autobackup is not installed"
        return 1
    fi
    return 0
}

# Validate if ZFS pool exists and has required properties
validate_pool() {
    local pool=$1
    if ! zfs list "$pool" >/dev/null 2>&1; then
        log_message "Error: Pool $pool does not exist"
        return 1
    fi

    # Verify autobackup property is set
    if ! zfs get autobackup:${pool} ${pool} | grep -q "true"; then
        log_message "Error: autobackup:${pool} property not set to true for pool ${pool}"
        return 1
    fi

    return 0
}

# Collect information about datasets - OPTIMIZED single-pass approach
# Significantly faster than previous multi-pass implementation
collect_dataset_info() {
    local pool=$1
    local temp_file=$(mktemp)

    # Single recursive call to get all datasets and snapshots at once
    # This replaces multiple individual zfs list calls per dataset
    zfs list -r -t all -o name,type,used,creation -Hp "${pool}" > "${temp_file}"

    local dataset_count=0
    local total_snapshots=0

    # Process all data in a single pass
    while IFS=$'\t' read -r name type used creation; do
        if [ "${type}" = "filesystem" ] || [ "${type}" = "volume" ]; then
            # This is a dataset
            dataset_count=$((dataset_count + 1))
            DATASETS_INFO["${name},space"]="${used}"
            DATASETS_INFO["${name},snaps"]=0
            DATASETS_INFO["${name},last_snap"]="N/A"

        elif [ "${type}" = "snapshot" ]; then
            # This is a snapshot
            total_snapshots=$((total_snapshots + 1))
            local dataset=$(echo "${name}" | cut -d'@' -f1)
            local snap_name=$(echo "${name}" | cut -d'@' -f2)

            # Increment snapshot count for this dataset
            local current_count=${DATASETS_INFO["${dataset},snaps"]:-0}
            DATASETS_INFO["${dataset},snaps"]=$((current_count + 1))

            # Always update last snapshot (file is sorted, so last one wins)
            DATASETS_INFO["${dataset},last_snap"]="${snap_name}"
        fi
    done < "${temp_file}"

    rm -f "${temp_file}"

    BACKUP_STATS["total_datasets"]="${dataset_count}"
    BACKUP_STATS["total_snapshots"]="${total_snapshots}"
}

# Parse the output of zfs-autobackup for created and deleted snapshots
# Counts snapshots from log output
parse_autobackup_output() {
    local logfile=$1

    # Count snapshots created
    # Pattern matches: "[Source] Creating snapshots zlhome01-20250929190001 in pool zlhome01"
    local created_count=$(grep -c "\[Source\] Creating snapshots.*-[0-9]\{14\} in pool" "${logfile}" || echo "0")

    # Count snapshots deleted (only from Source, not Target)
    # Pattern matches: "[Source] zlhome01/HOME.cmiranda@zlhome01-20250829214228: Destroying"
    local deleted_count=$(grep -c "\[Source\].*@.*: Destroying" "${logfile}" || echo "0")

    BACKUP_STATS["snapshots_created"]="${created_count}"
    BACKUP_STATS["snapshots_deleted"]="${deleted_count}"

    # Optional: Log the detected counts for debugging
    log_message "Detected ${created_count} snapshots created and ${deleted_count} snapshots deleted" >> "${logfile}"

    # Populate array for created snapshots (useful for detailed statistics)
    # Extract snapshot names from creation lines
    while read -r line; do
        # Extract the snapshot name pattern: poolname-YYYYMMDDHHMMSS
        local snap_name=$(echo "${line}" | grep -o '[a-zA-Z0-9_-]\+-[0-9]\{14\}')
        if [ -n "${snap_name}" ]; then
            CREATED_SNAPSHOTS+=("${snap_name}")
        fi
    done < <(grep "\[Source\] Creating snapshots.*-[0-9]\{14\} in pool" "${logfile}" || true)
}

# Format time duration from seconds to a human readable format
format_duration() {
    local seconds=$1
    local minutes=$((seconds / 60))
    local remaining_seconds=$((seconds % 60))

    if [ "${minutes}" -eq 0 ]; then
        echo "${seconds}s"
    else
        echo "${minutes}m ${remaining_seconds}s"
    fi
}

# Draw a table header with appropriate column sizes
draw_table_header() {
    local col1_width=$1
    local col2_width=$2
    local col3_width=$3
    local col4_width=$4

    printf "+%${col1_width}s+%${col2_width}s+%${col3_width}s+%${col4_width}s+\n" \
           "$(printf '%0.s-' $(seq 1 $col1_width))" \
           "$(printf '%0.s-' $(seq 1 $col2_width))" \
           "$(printf '%0.s-' $(seq 1 $col3_width))" \
           "$(printf '%0.s-' $(seq 1 $col4_width))"

    printf "| %-$((col1_width-2))s | %-$((col2_width-2))s | %-$((col3_width-2))s | %-$((col4_width-2))s |\n" \
           "Dataset" "Total Snaps" "Last Snapshot" "Space Used"

    printf "+%${col1_width}s+%${col2_width}s+%${col3_width}s+%${col4_width}s+\n" \
           "$(printf '%0.s-' $(seq 1 $col1_width))" \
           "$(printf '%0.s-' $(seq 1 $col2_width))" \
           "$(printf '%0.s-' $(seq 1 $col3_width))" \
           "$(printf '%0.s-' $(seq 1 $col4_width))"
}

# Draw a table row with appropriate column sizes - SIMPLIFIED
# Removed complex (XM,YW,ZD) breakdown for cleaner output
draw_table_row() {
    local dataset=$1
    local col1_width=$2
    local col2_width=$3
    local col3_width=$4
    local col4_width=$5

    local snaps="${DATASETS_INFO["${dataset},snaps"]}"
    local last_snap="${DATASETS_INFO["${dataset},last_snap"]}"
    local space="${DATASETS_INFO["${dataset},space"]}"

    # Truncate dataset name if too long
    local displayed_dataset="${dataset}"
    if [ ${#displayed_dataset} -gt $((col1_width-4)) ]; then
        displayed_dataset="${displayed_dataset:0:$((col1_width-7))}..."
    fi

    # Truncate last snapshot name if too long
    if [ ${#last_snap} -gt $((col3_width-4)) ]; then
        last_snap="${last_snap:0:$((col3_width-7))}..."
    fi

    printf "| %-$((col1_width-2))s | %-$((col2_width-2))s | %-$((col3_width-2))s | %-$((col4_width-2))s |\n" \
           "${displayed_dataset}" "${snaps}" "${last_snap}" "${space}"
}

# Draw statistics table - SIMPLIFIED
# Removed per-type snapshot counts, focus on essential metrics
draw_stats_table() {
    local pool=$1

    echo
    echo "STATISTICS:"
    printf "+%-24s+%-15s+\n" "$(printf '%0.s-' $(seq 1 24))" "$(printf '%0.s-' $(seq 1 15))"
    printf "| %-22s | %-13s |\n" "Metric" "Value"
    printf "+%-24s+%-15s+\n" "$(printf '%0.s-' $(seq 1 24))" "$(printf '%0.s-' $(seq 1 15))"

    printf "| %-22s | %-13s |\n" "Total Datasets" "${BACKUP_STATS["total_datasets"]}"
    printf "| %-22s | %-13s |\n" "Total Snapshots" "${BACKUP_STATS["total_snapshots"]}"
    printf "| %-22s | %-13s |\n" "Snapshots Created" "${BACKUP_STATS["snapshots_created"]}"
    printf "| %-22s | %-13s |\n" "Snapshots Deleted" "${BACKUP_STATS["snapshots_deleted"]}"
    printf "| %-22s | %-13s |\n" "Operation Duration" "${BACKUP_STATS["duration"]}"

    printf "+%-24s+%-15s+\n" "$(printf '%0.s-' $(seq 1 24))" "$(printf '%0.s-' $(seq 1 15))"
}

# Generate a detailed summary report - SIMPLIFIED
# Removed complex categorization and monthly distribution
generate_summary_report() {
    local pool=$1
    local status=$2
    local logfile=$3

    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    BACKUP_STATS["duration"]="$(format_duration ${duration})"

    # Collect dataset information using optimized single-pass approach
    collect_dataset_info "${pool}"

    # If this was a successful backup, parse the log for additional information
    if [[ "${status}" == *"COMPLETED"* ]]; then
        parse_autobackup_output "${logfile}"
    fi

    # Define table column widths
    local col1_width=32  # Dataset
    local col2_width=16  # Total Snaps
    local col3_width=32  # Last Snapshot
    local col4_width=15  # Space Used

    # Create a temporary file for the clean report
    local temp_report=$(mktemp)

    # Generate the clean report to temp file
    {
        echo
        echo "===== BACKUP SUMMARY ($(date '+%Y-%m-%d %H:%M:%S')) ====="
        echo "POOL: ${pool}  |  Status: ${status}  |  Last backup: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Log file: ${logfile}"
        echo

        # Print dataset summary table
        echo "DATASETS SUMMARY:"
        draw_table_header ${col1_width} ${col2_width} ${col3_width} ${col4_width}

        # List all datasets
        for dataset in $(zfs list -r -o name -H "${pool}"); do
            draw_table_row "${dataset}" ${col1_width} ${col2_width} ${col3_width} ${col4_width}
        done

        printf "+%${col1_width}s+%${col2_width}s+%${col3_width}s+%${col4_width}s+\n" \
               "$(printf '%0.s-' $(seq 1 $col1_width))" \
               "$(printf '%0.s-' $(seq 1 $col2_width))" \
               "$(printf '%0.s-' $(seq 1 $col3_width))" \
               "$(printf '%0.s-' $(seq 1 $col4_width))"

        # Draw statistics table
        draw_stats_table "${pool}"

    } > "${temp_report}"

    # Display the clean report on stdout
    cat "${temp_report}"

    # Append the clean report to logfile
    cat "${temp_report}" >> "${logfile}"

    # Clean up
    rm -f "${temp_report}"

    # Store pool info for use in main function - will be displayed at the end
    BACKUP_STATS["${pool},pool_info"]="POOL: ${pool}  |  Remote: ${REMOTE_HOST}  |  Status: ${status}  |  Last backup: $(date '+%Y-%m-%d %H:%M:%S')"
    BACKUP_STATS["${pool},log_file_info"]="Log file: ${logfile}"
}

# Main backup function for a single pool - SIMPLIFIED
# Removed redundant recent snapshot check - zfs-autobackup handles this internally
log_backup() {
    local pool=$1
    local logfile="$LOG_DIR/${pool}_backup_${DATE}.log"
    local temp_error_file=$(mktemp)

    # Start logging from the beginning
    log_message "Processing pool: $pool" | tee -a "$logfile"
    log_message "- Starting backup" | tee -a "$logfile"
    log_message "- Log file: $logfile" | tee -a "$logfile"

    # Execute backup with full output capture
    # zfs-autobackup will handle --min-change internally and skip if no changes
    if ! zfs-autobackup -v --clear-mountpoint --force --ssh-target "$REMOTE_HOST" "$pool" "$REMOTE_POOL_BASEPATH" > >(tee -a "$logfile") 2> >(tee -a "$temp_error_file" >&2); then
        log_message "- Backup failed" | tee -a "$logfile"
        cat "$temp_error_file" | tee -a "$logfile"
        printf '\n\n' | tee -a "$logfile"

        # Generate summary report
        generate_summary_report "${pool}" "✗ FAILED" "${logfile}"
        FAILED_POOLS+=("$pool")
    else
        log_message "- Backup completed successfully" | tee -a "$logfile"
        printf '\n' | tee -a "$logfile"

        # Generate summary report
        generate_summary_report "${pool}" "✓ COMPLETED" "${logfile}"
    fi

    # Add LOG ROTATION section after the backup summary
    {
        echo
        echo "LOG ROTATION:"
    } | tee -a "$logfile"

    # Clean logs for this pool with output captured
    clean_old_logs "$pool" | tee -a "$logfile"

    rm -f "$temp_error_file"
}

# Removes log files that don't have matching snapshots
# Only processes logs older than current day
# UNCHANGED - This function provides genuine value and is kept as-is
clean_old_logs() {
    local pool=$1
    local current_date=$(date +%Y%m%d)

    log_message "Cleaning logs for $pool using match_snapshots policy"

    # Get all snapshots from pool AND all its datasets (recursive search)
    # Extract dates from 14-digit timestamps, handling various snapshot prefixes
    local snapshot_dates=$(zfs list -t snapshot -o name -H -r "$pool" |
                          grep -E "@[a-zA-Z0-9_-]+-[0-9]{14}" |
                          sed -E "s/.*@[a-zA-Z0-9_-]+-([0-9]{8})[0-9]{6}/\1/" |
                          sort -u)

    # Count valid extracted dates
    local snapshot_count=$(echo "$snapshot_dates" | grep -c "^[0-9]\{8\}$" || echo "0")
    log_message "Found $snapshot_count unique snapshot dates for $pool (recursive search)"

    # Debug: Show sample of extracted dates
    if [ "$snapshot_count" -gt 0 ]; then
        log_message "Sample extracted dates: $(echo "$snapshot_dates" | head -5 | tr '\n' ' ')"
        # Show date range
        local oldest_date=$(echo "$snapshot_dates" | head -1)
        local newest_date=$(echo "$snapshot_dates" | tail -1)
        log_message "Date range: $oldest_date to $newest_date"
    else
        log_message "WARNING: No valid snapshot dates found with expected pattern"
        # Show sample snapshot names for debugging
        local sample_snapshots=$(zfs list -t snapshot -o name -H -r "$pool" | head -5)
        log_message "Sample snapshot names found: $sample_snapshots"
    fi

    # Process each log file
    local logs_processed=0
    local logs_removed=0
    local logs_kept=0

    # Use a safer approach to avoid subshell issues with counters
    while IFS= read -r logfile; do
        [ -z "$logfile" ] && continue

        logs_processed=$((logs_processed + 1))

        # Extract the date portion (YYYYMMDD) from the log filename
        log_date=$(basename "$logfile" | grep -o '[0-9]\{8\}')

        # Skip if no valid date found in filename
        if [ -z "$log_date" ]; then
            log_message "WARNING: Could not extract date from log filename: $logfile"
            continue
        fi

        # Skip if it's today's log
        if [ "$log_date" = "$current_date" ]; then
            log_message "Keeping current day log: $logfile"
            logs_kept=$((logs_kept + 1))
            continue
        fi

        # Check if we have snapshots for this date
        if echo "$snapshot_dates" | grep -q "^${log_date}$"; then
            log_message "Keeping log that matches snapshot date $log_date: $logfile"
            logs_kept=$((logs_kept + 1))
        else
            log_message "Removing old log without matching snapshot for date $log_date: $logfile"
            rm "$logfile"
            logs_removed=$((logs_removed + 1))
        fi
    done < <(find "$LOG_DIR" -name "${pool}_backup_*.log" 2>/dev/null)

    log_message "Log cleanup completed for $pool: processed=$logs_processed, removed=$logs_removed, kept=$logs_kept"
}

# Main script execution
# Validates dependencies and pools
# Processes each pool and handles failures
main() {
    log_message "Starting ZFS backup process (v1.0.19)"
    log_message "Checking dependencies..."

    # Verify dependencies
    if ! check_dependencies; then
        log_message "Failed dependency check. Exiting."
        exit 1
    fi
    log_message "Dependencies OK"

    # Ensure log directory exists
    mkdir -p "$LOG_DIR" || {
        log_message "Error: Could not create log directory $LOG_DIR"
        exit 1
    }

    # Array for tracking failed pools
    declare -a FAILED_POOLS=()

    # Use specified pool or default list
    if [ $# -eq 1 ]; then
        if validate_pool "$1"; then
            POOLS=("$1")
        else
            exit 1
        fi
    else
        POOLS=("${SOURCE_POOLS[@]}")
    fi

    # Process each pool
    for pool in "${POOLS[@]}"; do
        log_backup "$pool"
        sleep 5  # Brief pause between pools
    done

    # Final completion message
    log_message "Backup process completed"
    echo

    # Display pool and log file info for each processed pool
    for pool in "${POOLS[@]}"; do
        # Display the stored pool info from BACKUP_STATS
        if [ -n "${BACKUP_STATS["${pool},pool_info"]}" ]; then
            echo "${BACKUP_STATS["${pool},pool_info"]}"
            echo "${BACKUP_STATS["${pool},log_file_info"]}"
        fi
    done

    # Report any failures
    if [ ${#FAILED_POOLS[@]} -gt 0 ]; then
        log_message "WARNING: Some pools failed: ${FAILED_POOLS[*]}"
        exit ${#FAILED_POOLS[@]}
    fi
}

# Run main function with provided arguments
main "$@"
exit 0
