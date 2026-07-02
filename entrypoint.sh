#!/bin/sh

set -eu

PARAMETERS_FILE="/config/parameters.conf"
MERGERFS_PID=""

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

cleanup() {
    log "Cleaning up mergerfs..."

    if [ -n "$MERGERFS_PID" ] && kill -0 "$MERGERFS_PID" 2>/dev/null; then
        kill "$MERGERFS_PID" 2>/dev/null || true
        wait "$MERGERFS_PID" 2>/dev/null || true
    fi

    if grep -q " /merged " /proc/mounts; then
        fusermount3 -uz /merged 2>/dev/null \
        || fusermount -uz /merged 2>/dev/null \
        || umount -l /merged 2>/dev/null \
        || true
    fi

    log "Cleanup complete."
}

trap cleanup EXIT INT TERM

if [ -n "${MERGERFS_PARAMS:-}" ]; then
    log "Using parameters from MERGERFS_PARAMS environment variable."
    PARAMS="$MERGERFS_PARAMS"
else
    if [ ! -f "$PARAMETERS_FILE" ]; then
        log "Error: $PARAMETERS_FILE not found and MERGERFS_PARAMS is not set."
        exit 1
    fi

    PARAMS=$(
        grep -v '^[[:space:]]*#' "$PARAMETERS_FILE" \
        | sed '/^[[:space:]]*$/d' \
        | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
        | paste -sd ',' -
    )

    if [ -z "$PARAMS" ]; then
        log "Error: No valid parameters found in $PARAMETERS_FILE."
        exit 1
    fi

    log "Using parameters from $PARAMETERS_FILE."
fi

if [ ! -d /merged ]; then
    log "Error: /merged does not exist."
    exit 1
fi

set -- /disks/*

if [ ! -e "$1" ]; then
    log "Error: No branches found under /disks."
    exit 1
fi

log "Executing: mergerfs -f -o $PARAMS /disks/* /merged"

mergerfs -f -o "$PARAMS" "$@" /merged &
MERGERFS_PID="$!"

wait "$MERGERFS_PID"
