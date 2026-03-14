#!/usr/bin/env bash
# components/system-tuning/detect.sh
# Detection for system tuning state (zram, swap, memory settings).
# COMPONENT_STATUS: missing | ours-healthy | ours-broken | foreign | partial

set -euo pipefail

_ST_DETECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BLOOM_ROOT_GUESS="$(cd "${_ST_DETECT_DIR}/../.." && pwd)"

if ! declare -f log_debug &>/dev/null; then
    source "${_BLOOM_ROOT_GUESS}/bootstrap/common.sh"
fi

bloom_detect_system_tuning() {
    log_debug "system-tuning/detect: starting"

    local has_zram=false
    local has_swap=false
    local zram_device=""
    local swap_mb=0
    local vm_swappiness=""
    local our_tuning=false

    # Check for zram
    if [[ -d /sys/block/zram0 ]] || lsblk 2>/dev/null | grep -q "^zram"; then
        has_zram=true
        zram_device="/dev/zram0"
        log_debug "system-tuning/detect: zram found"
    fi

    # Check for swap
    swap_mb=$(awk '/SwapTotal/ { printf "%d", $2/1024 }' /proc/meminfo 2>/dev/null || echo 0)
    [[ "$swap_mb" -gt 0 ]] && has_swap=true

    # Read swappiness
    vm_swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "unknown")

    # Check for bloom tuning marker
    if [[ -f "${HOME}/.bloom-node-tuning" ]] || \
       grep -q "bloom-node-bootstrap" /etc/sysctl.d/*.conf 2>/dev/null || \
       [[ -f /etc/bloom-tuning.conf ]]; then
        our_tuning=true
    fi

    # Determine status
    if [[ "$our_tuning" == "true" ]]; then
        SYSTEM_TUNING_STATUS="ours-healthy"
        SYSTEM_TUNING_HEALTHY=true
    elif [[ "$has_zram" == "true" ]] || [[ "$has_swap" == "true" ]]; then
        SYSTEM_TUNING_STATUS="foreign"  # Some tuning exists but not ours
        SYSTEM_TUNING_HEALTHY=true
    else
        SYSTEM_TUNING_STATUS="missing"
        SYSTEM_TUNING_HEALTHY=false
    fi

    SYSTEM_TUNING_HAS_ZRAM="$has_zram"
    SYSTEM_TUNING_HAS_SWAP="$has_swap"
    SYSTEM_TUNING_ZRAM_DEVICE="$zram_device"
    SYSTEM_TUNING_SWAP_MB="$swap_mb"
    SYSTEM_TUNING_VM_SWAPPINESS="$vm_swappiness"
    SYSTEM_TUNING_OUR_VERSION="$our_tuning"

    _st_export_and_print
}

_st_export_and_print() {
    export SYSTEM_TUNING_STATUS SYSTEM_TUNING_HEALTHY SYSTEM_TUNING_HAS_ZRAM \
           SYSTEM_TUNING_HAS_SWAP SYSTEM_TUNING_ZRAM_DEVICE SYSTEM_TUNING_SWAP_MB \
           SYSTEM_TUNING_VM_SWAPPINESS SYSTEM_TUNING_OUR_VERSION

    log_debug "system-tuning/detect: STATUS=${SYSTEM_TUNING_STATUS} ZRAM=${SYSTEM_TUNING_HAS_ZRAM} SWAP=${SYSTEM_TUNING_SWAP_MB}MB"
    printf 'SYSTEM_TUNING_STATUS=%s\nSYSTEM_TUNING_HAS_ZRAM=%s\nSYSTEM_TUNING_HAS_SWAP=%s\nSYSTEM_TUNING_SWAP_MB=%s\nSYSTEM_TUNING_VM_SWAPPINESS=%s\nSYSTEM_TUNING_OUR_VERSION=%s\n' \
        "$SYSTEM_TUNING_STATUS" "$SYSTEM_TUNING_HAS_ZRAM" "$SYSTEM_TUNING_HAS_SWAP" \
        "$SYSTEM_TUNING_SWAP_MB" "$SYSTEM_TUNING_VM_SWAPPINESS" "$SYSTEM_TUNING_OUR_VERSION"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bloom_detect_system_tuning
fi
