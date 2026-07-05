#!/usr/bin/env bash
#
# Copyright (c) 2024-2026. All rights reserved.
#
# Name: zfs-autobackup-wrapper.sh
# Version: 2.0.0
# Author: Mstaaravin
# Description: Thin wrapper around zfs-autobackup (https://github.com/psy0rz/zfs_autobackup)
#              Adds only what zfs-autobackup deliberately leaves out:
#              per-run log files, age-based log rotation, a readable summary,
#              and failure notifications via healthchecks.io.
#
# Changelog v2.0.0:
#   - Full rewrite: ~570 -> ~240 lines
#   - Removed ASCII table engine; summary is plain `zfs list` with human-readable sizes
#   - Removed regex parsing of zfs-autobackup output (fragile across upgrades)
#   - Log rotation is now age-based; logs from failed runs are renamed *_FAILED.log
#     and kept under a longer retention period
#   - Added healthchecks.io pings: /start on begin, success or /fail on end,
#     with a log excerpt as the ping body
#   - Detects "cannot find common snapshot" failures and logs a remediation hint
#   - Site configuration can be overridden in an optional <scriptname>.conf file,
#     so the deployed copy no longer drifts from the repo
#   - Local mode: REMOTE_HOST="" backs up to another pool on the same host
#     (no SSH; target is REMOTE_POOL_BASEPATH on the local machine)
#
# Usage: ./zfs-autobackup-wrapper.sh [pool_name]
#
# Exit codes:
#   0 - Success
#   1 - Dependency or pool validation failure
#   N - Number of pools that failed to back up
#

set -euo pipefail

# ===== Configuration =====
# Override any of these in an optional config file next to this script,
# named like the script but with .conf extension (e.g. backup_zfs.conf).
# The .conf file is plain bash, e.g.:
#   REMOTE_HOST="zima01"
#   HEALTHCHECKS_URL="https://hc-ping.com/<your-uuid>"

# SSH config hostname (~/.ssh/config) or IP of the backup target.
# Requires SSH key authentication and ZFS permissions on the remote host.
# Leave EMPTY ("") for local mode: backup to another pool on this same host
# (target is REMOTE_POOL_BASEPATH on the local machine, no SSH involved).
REMOTE_HOST="pbs01"
REMOTE_POOL_BASEPATH="WD181KFGX/HOST"

# Pools to back up when no pool is given on the command line
SOURCE_POOLS=(
    "zlhome01"
)

LOG_DIR="/root/logs"

# Retention passed to zfs-autobackup (--keep-source / --keep-target)
KEEP_POLICY="10,1d1w,1w1m,1m6m"

# Log rotation: plain age-based retention. Logs from failed runs are renamed
# *_FAILED.log and kept longer so failures stay diagnosable.
LOG_RETENTION_DAYS=60
LOG_RETENTION_DAYS_FAILED=365

# healthchecks.io ping URL (empty = notifications disabled)
HEALTHCHECKS_URL=""

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
CONF_FILE="${SCRIPT_PATH%.sh}.conf"
# shellcheck source=/dev/null
[ -f "$CONF_FILE" ] && source "$CONF_FILE"

# ===== Runtime globals =====
export PATH="/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

LOCAL_HOSTNAME=$(hostname -s)
RUN_DATE=$(date +%Y%m%d_%H%M)

declare -a FAILED_POOLS=()
declare -A POOL_LOG=()
declare -A POOL_STATUS=()

# ===== Helpers =====

# Run a command on the backup target: via SSH in remote mode, directly in local mode
target_exec() {
    if [ -n "$REMOTE_HOST" ]; then
        ssh "$REMOTE_HOST" "$@"
    else
        bash -c "$@"
    fi
}

# Human-readable name of the backup target for logs and summaries
target_name() {
    echo "${REMOTE_HOST:-local}"
}

# Log to stdout and syslog with a consistent timestamp
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    logger -t zfs-backup -- "$*" 2>/dev/null || true
}

# Ping healthchecks.io. $1 = endpoint ("" success, "/start", "/fail"),
# $2 = optional body attached to the ping (shown in the healthchecks.io UI)
hc_ping() {
    local endpoint=${1:-} body=${2:-}
    [ -z "$HEALTHCHECKS_URL" ] && return 0
    if ! curl -fsS -m 10 --retry 3 --data-raw "$body" \
            "${HEALTHCHECKS_URL}${endpoint}" >/dev/null 2>&1; then
        log "WARNING: healthchecks.io ping failed (endpoint: '${endpoint:-success}')"
    fi
}

check_dependencies() {
    if ! command -v zfs-autobackup >/dev/null 2>&1; then
        log "Error: zfs-autobackup is not installed"
        return 1
    fi
    if [ -n "$HEALTHCHECKS_URL" ] && ! command -v curl >/dev/null 2>&1; then
        log "Error: curl is required for healthchecks.io notifications"
        return 1
    fi
    return 0
}

validate_pool() {
    local pool=$1
    if ! zfs list "$pool" >/dev/null 2>&1; then
        log "Error: Pool $pool does not exist"
        return 1
    fi
    if ! zfs get -H -o value "autobackup:${pool}" "$pool" | grep -q "true"; then
        log "Error: autobackup:${pool} property not set to true for pool ${pool}"
        return 1
    fi
    return 0
}

# Plain-text summary: datasets with human-readable sizes, snapshot counts, duration
write_summary() {
    local pool=$1 status=$2 duration=$3

    echo
    echo "===== BACKUP SUMMARY ($(date '+%Y-%m-%d %H:%M:%S')) ====="
    echo
    echo "DATASETS:"
    zfs list -r -t filesystem,volume -o name,used,avail,refer "$pool"
    echo
    echo "SNAPSHOTS PER DATASET:"
    zfs list -r -t snapshot -o name -H "$pool" | awk -F@ '{print $1}' | uniq -c
    echo
    echo "Duration: ${duration}"
    echo
    echo "POOL: ${pool}  |  Target: $(target_name)  |  Status: ${status}  |  Last backup: $(date '+%Y-%m-%d %H:%M:%S')"
}

# Run zfs-autobackup for one pool, logging everything to a per-run file
backup_pool() {
    local pool=$1
    local logfile="${LOG_DIR}/${pool}_backup_${RUN_DATE}.log"
    local pool_start pool_status="✓ COMPLETED"
    pool_start=$(date +%s)

    log "Processing pool: ${pool}" | tee -a "$logfile"
    log "Log file: ${logfile}" | tee -a "$logfile"

    # Ensure target base dataset exists: BASEPATH/hostname (multi-host layout)
    local remote_base="${REMOTE_POOL_BASEPATH}/${LOCAL_HOSTNAME}"
    if ! target_exec "zfs list '$remote_base'" >/dev/null 2>&1; then
        log "Creating target base dataset: ${remote_base}" | tee -a "$logfile"
        if ! target_exec "zfs create -p '$remote_base'" 2>&1 | tee -a "$logfile"; then
            log "ERROR: could not create target base dataset on $(target_name)" | tee -a "$logfile"
            pool_status="✗ FAILED"
        fi
    fi

    # In local mode --ssh-target is omitted and zfs-autobackup writes to a local pool
    local -a ssh_target_args=()
    [ -n "$REMOTE_HOST" ] && ssh_target_args=(--ssh-target "$REMOTE_HOST")

    if [ "$pool_status" != "✗ FAILED" ]; then
        if ! zfs-autobackup -v \
                --keep-source "$KEEP_POLICY" --keep-target "$KEEP_POLICY" \
                --clear-mountpoint --force \
                "${ssh_target_args[@]}" \
                "$pool" "$remote_base" 2>&1 | tee -a "$logfile"; then
            pool_status="✗ FAILED"
        fi
    fi

    if [ "$pool_status" = "✗ FAILED" ]; then
        log "Backup FAILED for pool ${pool}" | tee -a "$logfile"

        # Known silent-failure mode: incremental impossible, needs manual action.
        # Without intervention this will fail on every run from now on.
        if grep -qi "find common snapshot" "$logfile"; then
            log "HINT: a dataset has no common snapshot with the target." | tee -a "$logfile"
            log "HINT: rename or destroy the target dataset on $(target_name) to force a full re-send." | tee -a "$logfile"
        fi
    fi

    local duration=$(( $(date +%s) - pool_start ))
    write_summary "$pool" "$pool_status" "$((duration / 60))m $((duration % 60))s" | tee -a "$logfile"

    if [ "$pool_status" = "✗ FAILED" ]; then
        local failed_log="${logfile%.log}_FAILED.log"
        mv "$logfile" "$failed_log"
        logfile="$failed_log"
        FAILED_POOLS+=("$pool")
    fi

    POOL_LOG["$pool"]="$logfile"
    POOL_STATUS["$pool"]="$pool_status"
}

# Age-based rotation; failed-run logs live under a longer retention
rotate_logs() {
    local pool=$1 removed_ok removed_failed
    removed_ok=$(find "$LOG_DIR" -name "${pool}_backup_*.log" ! -name "*_FAILED.log" \
                     -mtime +"$LOG_RETENTION_DAYS" -print -delete | wc -l)
    removed_failed=$(find "$LOG_DIR" -name "${pool}_backup_*_FAILED.log" \
                     -mtime +"$LOG_RETENTION_DAYS_FAILED" -print -delete | wc -l)
    log "Log rotation for ${pool}: removed ${removed_ok} logs older than ${LOG_RETENTION_DAYS}d, ${removed_failed} failed-run logs older than ${LOG_RETENTION_DAYS_FAILED}d"
}

main() {
    log "Starting ZFS backup process (v2.0.0)"

    if [ "$(id -u)" != "0" ]; then
        log "Error: This script must be run as root"
        exit 1
    fi

    if ! check_dependencies; then
        exit 1
    fi

    mkdir -p "$LOG_DIR"

    local -a pools=()
    if [ $# -eq 1 ]; then
        validate_pool "$1" || exit 1
        pools=("$1")
    else
        pools=("${SOURCE_POOLS[@]}")
    fi

    hc_ping "/start" "Backup starting on ${LOCAL_HOSTNAME}: ${pools[*]}"

    for pool in "${pools[@]}"; do
        backup_pool "$pool"
        rotate_logs "$pool" | tee -a "${POOL_LOG[$pool]}"
    done

    echo
    for pool in "${pools[@]}"; do
        echo "POOL: ${pool}  |  Target: $(target_name)  |  Status: ${POOL_STATUS[$pool]}  |  Log: ${POOL_LOG[$pool]}"
    done

    if [ ${#FAILED_POOLS[@]} -gt 0 ]; then
        log "WARNING: Some pools failed: ${FAILED_POOLS[*]}"
        local body="FAILED pools on ${LOCAL_HOSTNAME}: ${FAILED_POOLS[*]}"$'\n\n'
        for pool in "${FAILED_POOLS[@]}"; do
            body+="--- last 40 lines of ${POOL_LOG[$pool]} ---"$'\n'
            body+="$(tail -n 40 "${POOL_LOG[$pool]}")"$'\n\n'
        done
        hc_ping "/fail" "$body"
        exit ${#FAILED_POOLS[@]}
    fi

    log "Backup process completed"
    hc_ping "" "Backup OK on ${LOCAL_HOSTNAME}: ${pools[*]}"
}

main "$@"
