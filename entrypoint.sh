#!/bin/sh

set -eu

DISKS_DIR="/disks"
MERGED_DIR="/merged"
PARAMETERS_FILE="/config/parameters.conf"
STARTUP_TIMEOUT=10

MERGERFS_PID=""
CLEANUP_DONE=0

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*"
}

die() {
    printf '%s ERROR: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >&2
    exit 1
}

is_mergerfs_mounted() {
    awk -v mountpoint="$MERGED_DIR" '
        $2 == mountpoint && ($3 == "fuse.mergerfs" || $3 == "fuseblk.mergerfs") {
            found = 1
        }
        END {
            exit(found ? 0 : 1)
        }
    ' /proc/self/mounts
}

wait_for_unmount() {
    i=0
    while is_mergerfs_mounted; do
        if [ "$i" -ge 5 ]; then
            return 1
        fi
        sleep 1
        i=$((i + 1))
    done

    return 0
}

unmount_merged() {
    if ! is_mergerfs_mounted; then
        return 0
    fi

    log "Unmounting existing mergerfs mount from $MERGED_DIR."
    if fusermount3 -u "$MERGED_DIR" 2>/dev/null \
        || fusermount -u "$MERGED_DIR" 2>/dev/null \
        || umount "$MERGED_DIR" 2>/dev/null; then
        if wait_for_unmount; then
            return 0
        fi
    fi

    log "Clean unmount failed; trying lazy FUSE unmount for $MERGED_DIR."
    if fusermount3 -uz "$MERGED_DIR" 2>/dev/null \
        || fusermount -uz "$MERGED_DIR" 2>/dev/null \
        || umount -l "$MERGED_DIR" 2>/dev/null; then
        wait_for_unmount
        return $?
    fi

    return 1
}

cleanup() {
    status="${1:-0}"

    if [ "$CLEANUP_DONE" -eq 1 ]; then
        return "$status"
    fi
    CLEANUP_DONE=1
    trap - EXIT INT TERM

    if [ -n "$MERGERFS_PID" ] && kill -0 "$MERGERFS_PID" 2>/dev/null; then
        log "Stopping mergerfs pid $MERGERFS_PID."
        kill -TERM "$MERGERFS_PID" 2>/dev/null || true
        wait "$MERGERFS_PID" 2>/dev/null || true
    fi
    MERGERFS_PID=""

    if is_mergerfs_mounted; then
        if ! unmount_merged; then
            log "ERROR: Failed to unmount mergerfs from $MERGED_DIR."
            return 1
        fi
    fi

    return "$status"
}

on_signal() {
    signal="$1"
    status="$2"

    log "Received SIG$signal; shutting down."
    cleanup "$status" || status=1
    exit "$status"
}

trap 'cleanup "$?"' EXIT
trap 'on_signal INT 130' INT
trap 'on_signal TERM 143' TERM

load_params_from_file() {
    if [ ! -f "$PARAMETERS_FILE" ]; then
        die "$PARAMETERS_FILE not found and MERGERFS_PARAMS is not set."
    fi

    params=$(
        sed -n '
            s/\r$//
            /^[[:space:]]*#/d
            /^[[:space:]]*$/d
            s/^[[:space:]]*//
            s/[[:space:]]*$//
            p
        ' "$PARAMETERS_FILE" | paste -sd ',' -
    )

    if [ -z "$params" ]; then
        die "No usable mergerfs parameters found in $PARAMETERS_FILE."
    fi

    printf '%s' "$params"
}

if [ -n "${MERGERFS_PARAMS:-}" ]; then
    PARAMS="$MERGERFS_PARAMS"
    log "Using mergerfs parameters from MERGERFS_PARAMS."
else
    PARAMS="$(load_params_from_file)"
    log "Using mergerfs parameters from $PARAMETERS_FILE."
fi

if [ ! -d "$MERGED_DIR" ]; then
    die "$MERGED_DIR does not exist or is not a directory."
fi

if is_mergerfs_mounted; then
    log "Found stale mergerfs mount on $MERGED_DIR before startup."
    unmount_merged || die "Unable to clear stale mergerfs mount on $MERGED_DIR."
fi

set -- "$DISKS_DIR"/*
if [ ! -e "$1" ]; then
    die "No branch directories found under $DISKS_DIR."
fi

for branch in "$@"; do
    if [ ! -d "$branch" ]; then
        die "Branch path is not a directory: $branch"
    fi
done

log "Starting mergerfs with $# branch(es)."
mergerfs -f -o "$PARAMS" "$@" "$MERGED_DIR" &
MERGERFS_PID="$!"

i=0
while [ "$i" -lt "$STARTUP_TIMEOUT" ]; do
    if is_mergerfs_mounted; then
        log "mergerfs mounted $MERGED_DIR."
        break
    fi

    if ! kill -0 "$MERGERFS_PID" 2>/dev/null; then
        if wait "$MERGERFS_PID"; then
            status=0
        else
            status=$?
        fi
        MERGERFS_PID=""
        die "mergerfs exited before mounting $MERGED_DIR with status $status."
    fi

    sleep 1
    i=$((i + 1))
done

if ! is_mergerfs_mounted; then
    log "ERROR: mergerfs did not mount $MERGED_DIR within ${STARTUP_TIMEOUT}s."
    cleanup 1 || true
    exit 1
fi

if wait "$MERGERFS_PID"; then
    status=0
else
    status=$?
fi
MERGERFS_PID=""

if [ "$status" -eq 0 ]; then
    log "mergerfs exited."
else
    log "mergerfs exited with status $status."
fi

exit "$status"
