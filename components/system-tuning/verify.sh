#!/usr/bin/env bash
# components/system-tuning/verify.sh
# Health check for system-tuning component.
# Exit codes: 0=OK, 1=WARN, 2=FAIL

set -euo pipefail

_ST_VERIFY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BLOOM_ROOT_GUESS="$(cd "${_ST_VERIFY_DIR}/../.." && pwd)"

if ! declare -f log_info &>/dev/null; then
    source "${_BLOOM_ROOT_GUESS}/bootstrap/common.sh"
fi

bloom_verify_system_tuning() {
    log_section "Verifying component: system-tuning"

    local exit_code=0
    local issues=()

    # 1. Check swappiness is set
    local swappiness
    swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "unknown")
    if [[ "$swappiness" == "unknown" ]]; then
        issues+=("cannot read vm.swappiness from /proc/sys/vm/swappiness")
        [[ $exit_code -lt 1 ]] && exit_code=1
    else
        log_ok "system-tuning: vm.swappiness=${swappiness}"
    fi

    # 2. Check swap availability
    local swap_mb
    swap_mb=$(awk '/SwapTotal/ { printf "%d", $2/1024 }' /proc/meminfo 2>/dev/null || echo 0)
    local ram_mb
    ram_mb=$(awk '/MemTotal/ { printf "%d", $2/1024 }' /proc/meminfo 2>/dev/null || echo 9999)

    if [[ "$swap_mb" -eq 0 && "$ram_mb" -lt 1024 ]]; then
        issues+=("no swap available and RAM is only ${ram_mb}MB — system may OOM under load")
        [[ $exit_code -lt 1 ]] && exit_code=1
    elif [[ "$swap_mb" -eq 0 ]]; then
        log_info "system-tuning: no swap (RAM is ${ram_mb}MB — may be acceptable)"
    else
        log_ok "system-tuning: swap available (${swap_mb}MB)"
    fi

    # 3. Check zram
    local has_zram=false
    if [[ -d /sys/block/zram0 ]]; then
        has_zram=true
        local zram_size=0
        zram_size=$(cat /sys/block/zram0/disksize 2>/dev/null || echo 0)
        local zram_mb=$(( zram_size / 1024 / 1024 ))
        log_ok "system-tuning: zram device present (disksize=${zram_mb}MB)"
    fi

    # 4. Check for our marker file
    if [[ -f "${HOME}/.bloom-node-tuning" ]]; then
        log_ok "system-tuning: bloom tuning marker found"
    else
        log_info "system-tuning: no bloom tuning marker (may not have been applied by us)"
    fi

    # 5. Warn if swappiness is 0 on low-RAM system (can cause OOM pressure)
    if [[ "$swappiness" == "0" && "$ram_mb" -lt 2048 ]]; then
        issues+=("vm.swappiness=0 on ${ram_mb}MB RAM system — risk of OOM killer activity")
        [[ $exit_code -lt 1 ]] && exit_code=1
    fi

    for issue in "${issues[@]}"; do
        log_warn "system-tuning: ${issue}"
    done

    case $exit_code in
        0) log_ok "system-tuning: verification PASSED" ;;
        1) log_warn "system-tuning: verification PASSED with warnings" ;;
        2) log_error "system-tuning: verification FAILED" ;;
    esac

    return $exit_code
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bloom_verify_system_tuning
fi
