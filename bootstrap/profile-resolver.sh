#!/usr/bin/env bash
# bootstrap/profile-resolver.sh
# Resolves the best install profile for the current machine.
# Source this file; do not execute directly.
#
# Depends on: bootstrap/common.sh (for log_*), detect.sh output variables.
#
# Public API:
#   resolve_profile [DETECT_VARS_FILE]
#     Given detected environment variables (sourced from file or already in env),
#     prints the profile name that best matches this machine.
#
# Profile selection logic (in priority order):
#   1. rpi-lowram       — ARM + RAM < 1024MB
#   2. x86-alpine-minimal — x86_64 + Alpine Linux (any RAM)
#   3. x86-legacy-lowram  — x86_64 + RAM < 2048MB
#   4. cloud-micro        — any arch + RAM < 1024MB + cloud marker
#   5. arm-sbc            — ARM (non-rpi) + RAM >= 1024MB
#   6. generic-safe       — fallback for anything else

set -euo pipefail

if ! declare -f log_debug &>/dev/null; then
    _PR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=bootstrap/logging.sh
    source "${_PR_DIR}/logging.sh"
fi

# ---------------------------------------------------------------------------
# _pr_is_cloud
# Heuristic: detect if running inside a cloud/VPS environment.
# Checks for cloud-init, DMI product name, or /run/cloud-init/enabled.
# ---------------------------------------------------------------------------
_pr_is_cloud() {
    # cloud-init present
    [[ -f /run/cloud-init/enabled ]] && return 0
    # DMI product name contains cloud provider name
    local dmi_product=""
    dmi_product="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
    case "${dmi_product,,}" in
        *openstack*|*amazon*|*droplet*|*google*|*azure*|*linode*|*hetzner*|*vultr*)
            return 0 ;;
    esac
    # systemd detect-virt
    if command -v systemd-detect-virt &>/dev/null; then
        local virt
        virt="$(systemd-detect-virt 2>/dev/null || true)"
        case "$virt" in
            kvm|xen|vmware|microsoft|oracle|amazon) return 0 ;;
        esac
    fi
    return 1
}

# ---------------------------------------------------------------------------
# _pr_is_raspberry_pi
# Return 0 if this machine is a Raspberry Pi.
# ---------------------------------------------------------------------------
_pr_is_raspberry_pi() {
    # /proc/cpuinfo contains "Raspberry Pi" on real hardware
    grep -qi "raspberry pi\|bcm2708\|bcm2709\|bcm2711\|bcm2835\|bcm2836\|bcm2837" \
        /proc/cpuinfo 2>/dev/null && return 0
    # Device tree model
    grep -qi "raspberry pi" /proc/device-tree/model 2>/dev/null && return 0
    return 1
}

# ---------------------------------------------------------------------------
# _pr_cpu_class
# Print arm | arm64 | x86_64 | unknown based on uname -m.
# ---------------------------------------------------------------------------
_pr_cpu_class() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        armv6*|armv7*) echo "arm" ;;
        aarch64|arm64) echo "arm64" ;;
        x86_64|amd64)  echo "x86_64" ;;
        i?86)          echo "x86" ;;
        *)             echo "unknown" ;;
    esac
}

# ---------------------------------------------------------------------------
# _pr_ram_mb
# Print total RAM in MB from /proc/meminfo.
# ---------------------------------------------------------------------------
_pr_ram_mb() {
    awk '/MemTotal/ { printf "%d", $2/1024 }' /proc/meminfo 2>/dev/null || echo 0
}

# ---------------------------------------------------------------------------
# _pr_distro_id
# Print distro ID from /etc/os-release.
# ---------------------------------------------------------------------------
_pr_distro_id() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        (source /etc/os-release && echo "${ID:-unknown}")
    else
        echo "unknown"
    fi
}

# ---------------------------------------------------------------------------
# resolve_profile [DETECT_VARS_FILE]
# Main exported function. Prints profile name to stdout.
#
# If DETECT_VARS_FILE is provided, source it first to populate env vars.
# Otherwise reads directly from system.
# ---------------------------------------------------------------------------
resolve_profile() {
    local detect_file="${1:-}"
    if [[ -n "$detect_file" && -f "$detect_file" ]]; then
        log_debug "resolve_profile: sourcing detect file ${detect_file}"
        # shellcheck disable=SC1090
        source "$detect_file"
    fi

    # Use pre-detected vars if available, otherwise detect now
    local cpu_class
    cpu_class="${CPU_CLASS:-$(_pr_cpu_class)}"

    local ram_mb
    ram_mb="${RAM_MB:-$(_pr_ram_mb)}"

    local distro
    distro="${DISTRO:-$(_pr_distro_id)}"

    log_debug "resolve_profile: cpu_class=${cpu_class} ram_mb=${ram_mb} distro=${distro}"

    # --- Rule 1: Raspberry Pi (ARM + low RAM is a specific class) ---
    local is_arm=false
    case "$cpu_class" in arm|arm64) is_arm=true ;; esac

    if [[ "$is_arm" == "true" ]] && _pr_is_raspberry_pi; then
        log_debug "resolve_profile: matched rpi-lowram (Raspberry Pi detected)"
        echo "rpi-lowram"
        return 0
    fi

    # --- Rule 2: Alpine on x86_64 (container/minimal server) ---
    if [[ "$cpu_class" == "x86_64" && "$distro" == "alpine" ]]; then
        log_debug "resolve_profile: matched x86-alpine-minimal (Alpine x86_64)"
        echo "x86-alpine-minimal"
        return 0
    fi

    # --- Rule 3: x86_64 with low RAM (legacy laptop / old desktop) ---
    if [[ "$cpu_class" == "x86_64" && "$ram_mb" -lt 2048 ]]; then
        log_debug "resolve_profile: matched x86-legacy-lowram (x86_64, RAM=${ram_mb}MB < 2048)"
        echo "x86-legacy-lowram"
        return 0
    fi

    # --- Rule 4: Cloud micro instance (any arch, very low RAM, cloud marker) ---
    if [[ "$ram_mb" -lt 1024 ]] && _pr_is_cloud; then
        log_debug "resolve_profile: matched cloud-micro (cloud, RAM=${ram_mb}MB < 1024)"
        echo "cloud-micro"
        return 0
    fi

    # --- Rule 5: ARM SBC (non-RPi, e.g. Orange Pi, Odroid) ---
    if [[ "$is_arm" == "true" ]]; then
        log_debug "resolve_profile: matched arm-sbc (ARM, non-RPi)"
        echo "arm-sbc"
        return 0
    fi

    # --- Fallback ---
    log_debug "resolve_profile: no specific match — using generic-safe"
    echo "generic-safe"
}

# ---------------------------------------------------------------------------
# list_profiles
# Print all available profile names.
# ---------------------------------------------------------------------------
list_profiles() {
    local profiles_dir="${BLOOM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/profiles"
    for f in "${profiles_dir}"/*.sh; do
        [[ -f "$f" ]] || continue
        basename "$f" .sh
    done
}

log_debug "profile-resolver.sh loaded"
