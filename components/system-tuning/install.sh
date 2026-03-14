#!/usr/bin/env bash
# components/system-tuning/install.sh
# Apply system-level tuning for low-resource nodes.
# Handles: zram setup, swappiness tuning, swap creation, log2ram recommendation.
# Requires root for most operations; gracefully degrades if not root.
#
# MODE: install | reuse | replace | skip
# (wrap/side-by-side not meaningful for system tuning)

set -euo pipefail

_ST_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BLOOM_ROOT_GUESS="$(cd "${_ST_INSTALL_DIR}/../.." && pwd)"

if ! declare -f log_info &>/dev/null; then
    source "${_BLOOM_ROOT_GUESS}/bootstrap/common.sh"
fi
if ! declare -f state_set &>/dev/null; then
    source "${_BLOOM_ROOT_GUESS}/bootstrap/state-store.sh"
fi
source "${_ST_INSTALL_DIR}/detect.sh"

MODE="${MODE:-install}"
ZRAM_SIZE_MB="${PROFILE_ZRAM_SIZE_MB:-256}"
TARGET_SWAPPINESS="${BLOOM_SWAPPINESS:-60}"

# ---------------------------------------------------------------------------
# _st_check_root — warn if not root, return 1
# ---------------------------------------------------------------------------
_st_check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log_warn "system-tuning: not running as root — some operations will be skipped"
        log_warn "system-tuning: re-run with sudo for full tuning"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# _st_setup_zram
# Load zram kernel module and configure a zram device as swap.
# ---------------------------------------------------------------------------
_st_setup_zram() {
    local size_mb="${1:-$ZRAM_SIZE_MB}"

    if ! _st_check_root; then
        log_warn "system-tuning: zram setup requires root — skipping"
        return 1
    fi

    log_info "system-tuning: setting up zram (${size_mb}MB)"

    # Load module
    if ! lsmod 2>/dev/null | grep -q "^zram"; then
        run_cmd modprobe zram 2>/dev/null || {
            log_warn "system-tuning: cannot load zram module — may not be available in kernel"
            return 1
        }
    fi

    # Wait for device
    local zram_dev="/dev/zram0"
    if [[ ! -b "$zram_dev" ]]; then
        log_warn "system-tuning: ${zram_dev} not found after modprobe"
        return 1
    fi

    # Check if already a swap device
    if swapon --show 2>/dev/null | grep -q "$zram_dev"; then
        log_ok "system-tuning: zram already active as swap"
        return 0
    fi

    # Configure size
    local size_bytes=$(( size_mb * 1024 * 1024 ))
    echo "$size_bytes" > /sys/block/zram0/disksize

    # Format and enable as swap
    run_cmd mkswap "$zram_dev"
    run_cmd swapon -p 100 "$zram_dev"  # high priority so it's used before disk swap

    log_ok "system-tuning: zram activated (${size_mb}MB compressed swap)"
}

# ---------------------------------------------------------------------------
# _st_set_swappiness VALUE
# ---------------------------------------------------------------------------
_st_set_swappiness() {
    local val="$1"
    log_info "system-tuning: setting vm.swappiness=${val}"

    if _st_check_root; then
        run_cmd sysctl -w "vm.swappiness=${val}"
        # Persist across reboots
        local sysctl_conf="/etc/sysctl.d/90-bloom-tuning.conf"
        cat > "$sysctl_conf" <<SYSCTL
# bloom-node-bootstrap system tuning
# Created: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
vm.swappiness=${val}
vm.vfs_cache_pressure=50
SYSCTL
        log_ok "system-tuning: swappiness persisted to ${sysctl_conf}"
    else
        # User-space only (doesn't persist)
        log_warn "system-tuning: setting swappiness requires root — not persisted"
    fi
}

# ---------------------------------------------------------------------------
# _st_create_swapfile SIZE_MB PATH
# ---------------------------------------------------------------------------
_st_create_swapfile() {
    local size_mb="${1:-512}"
    local swap_path="${2:-/swapfile}"

    if ! _st_check_root; then
        log_warn "system-tuning: swapfile creation requires root"
        return 1
    fi

    if swapon --show 2>/dev/null | grep -q "$swap_path"; then
        log_ok "system-tuning: swapfile ${swap_path} already active"
        return 0
    fi

    if [[ -f "$swap_path" ]]; then
        log_info "system-tuning: swapfile already exists at ${swap_path} — enabling"
        run_cmd swapon "$swap_path"
        return 0
    fi

    log_info "system-tuning: creating ${size_mb}MB swapfile at ${swap_path}"
    run_cmd fallocate -l "${size_mb}M" "$swap_path" 2>/dev/null || \
        run_cmd dd if=/dev/zero of="$swap_path" bs=1M count="$size_mb" status=none

    run_cmd chmod 600 "$swap_path"
    run_cmd mkswap "$swap_path"
    run_cmd swapon "$swap_path"

    # Add to fstab if not present
    if ! grep -q "$swap_path" /etc/fstab 2>/dev/null; then
        printf '%s none swap sw 0 0\n' "$swap_path" >> /etc/fstab
        log_ok "system-tuning: added ${swap_path} to /etc/fstab"
    fi

    log_ok "system-tuning: swapfile activated"
}

# ---------------------------------------------------------------------------
# _st_write_marker
# ---------------------------------------------------------------------------
_st_write_marker() {
    cat > "${HOME}/.bloom-node-tuning" <<MARKER
# bloom-node-bootstrap system tuning marker
# Created: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
BLOOM_TUNING_APPLIED=true
ZRAM_SIZE_MB=${ZRAM_SIZE_MB}
SWAPPINESS=${TARGET_SWAPPINESS}
MARKER
}

# ---------------------------------------------------------------------------
# Mode: install
# ---------------------------------------------------------------------------
_mode_install() {
    log_step "system-tuning: mode=install"
    bloom_detect_system_tuning

    if [[ "$SYSTEM_TUNING_OUR_VERSION" == "true" ]]; then
        log_ok "system-tuning: already applied"
        state_set_component_installed "system-tuning" "applied" "install"
        return 0
    fi

    local ram_mb
    ram_mb=$(awk '/MemTotal/ { printf "%d", $2/1024 }' /proc/meminfo 2>/dev/null || echo 1024)

    # Set up zram if recommended by profile and RAM is low
    if [[ "${PROFILE_ZRAM_RECOMMEND:-false}" == "true" ]]; then
        _st_setup_zram "$ZRAM_SIZE_MB" || log_warn "system-tuning: zram setup failed (non-fatal)"
    elif [[ "$ram_mb" -lt 512 && "$SYSTEM_TUNING_HAS_SWAP" == "false" ]]; then
        log_warn "system-tuning: RAM is ${ram_mb}MB and no swap detected — creating swapfile"
        _st_create_swapfile 512 /swapfile || log_warn "system-tuning: swapfile creation failed"
    fi

    # Tune swappiness for low-RAM systems
    if [[ "$ram_mb" -lt 2048 ]]; then
        _st_set_swappiness 80  # Higher swappiness to use swap more aggressively on low RAM
    else
        _st_set_swappiness "$TARGET_SWAPPINESS"
    fi

    _st_write_marker
    state_set_component_installed "system-tuning" "applied" "install"
    log_ok "system-tuning: tuning applied"
}

_mode_reuse() {
    log_step "system-tuning: mode=reuse"
    bloom_detect_system_tuning
    state_set_component_installed "system-tuning" "reuse" "reuse"
    log_ok "system-tuning: existing tuning registered (swappiness=${SYSTEM_TUNING_VM_SWAPPINESS})"
}

_mode_replace() {
    log_step "system-tuning: mode=replace"
    # Remove our old config if it exists
    [[ -f "${HOME}/.bloom-node-tuning" ]] && run_cmd rm "${HOME}/.bloom-node-tuning"
    _mode_install
}

_mode_skip() {
    log_step "system-tuning: mode=skip"
    state_set_skip "system-tuning" "user-requested-skip"
    log_info "system-tuning: skipped"
}

bloom_install_system_tuning() {
    log_section "Installing component: system-tuning"
    case "${MODE}" in
        install)      _mode_install ;;
        reuse)        _mode_reuse ;;
        wrap)         _mode_reuse ;;   # wrap = reuse for system tuning
        replace)      _mode_replace ;;
        side-by-side) log_warn "system-tuning: side-by-side not meaningful — using install"; _mode_install ;;
        skip)         _mode_skip ;;
        *) log_error "system-tuning: unknown MODE='${MODE}'"; return 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bloom_install_system_tuning
fi
