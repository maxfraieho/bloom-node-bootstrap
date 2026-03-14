#!/usr/bin/env bash
# doctor.sh
# Health check script for bloom-node-bootstrap.
# For each installed component: detect → verify → report status.
# Prints a summary table.
#
# Usage:
#   ./doctor.sh [--component COMP] [--verbose]

set -euo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLOOM_ROOT="$DOCTOR_DIR"
export BLOOM_ROOT

source "${BLOOM_ROOT}/bootstrap/logging.sh"
source "${BLOOM_ROOT}/bootstrap/common.sh"
source "${BLOOM_ROOT}/bootstrap/state-store.sh"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
FILTER_COMPONENT=""
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --component|-c) FILTER_COMPONENT="$2"; shift 2 ;;
        --verbose|-v)   VERBOSE=true; shift ;;
        --help|-h)
            printf 'Usage: %s [--component COMP] [--verbose]\n' "$(basename "$0")" >&2
            printf 'Components: cgc chub workflow hooks system-tuning tokens-config\n' >&2
            exit 0 ;;
        *) log_warn "doctor.sh: unknown argument: $1"; shift ;;
    esac
done

# ---------------------------------------------------------------------------
# Color shortcuts for table
# ---------------------------------------------------------------------------
_status_color() {
    local status="$1"
    case "$status" in
        OK)      printf '%b%s%b' "${CLR_GREEN:-}" "$status" "${CLR_RESET:-}" ;;
        WARN)    printf '%b%s%b' "${CLR_YELLOW:-}" "$status" "${CLR_RESET:-}" ;;
        FAIL)    printf '%b%s%b' "${CLR_RED:-}" "$status" "${CLR_RESET:-}" ;;
        MISSING) printf '%b%s%b' "${CLR_DIM:-}" "$status" "${CLR_RESET:-}" ;;
        SKIP)    printf '%b%s%b' "${CLR_DIM:-}" "$status" "${CLR_RESET:-}" ;;
        *)       printf '%s' "$status" ;;
    esac
}

# ---------------------------------------------------------------------------
# _doctor_component COMPONENT
# Run detect + verify for one component, return status string.
# ---------------------------------------------------------------------------
_doctor_component() {
    local comp="$1"
    local comp_dir="${BLOOM_ROOT}/components/${comp}"

    if [[ ! -d "$comp_dir" ]]; then
        printf '%-20s %-10s %s\n' "$comp" "MISSING" "no component directory"
        return
    fi

    # Check if skipped in state
    if state_has "component.${comp}.skip" 2>/dev/null; then
        local skip_reason
        skip_reason="$(state_get "component.${comp}.skip_reason" 2>/dev/null || echo "skipped")"
        printf '%-20s %-10s %s\n' "$comp" "SKIP" "$skip_reason"
        return
    fi

    # Run detect (in subshell, capture output)
    local detect_status=""
    if [[ -f "${comp_dir}/detect.sh" ]]; then
        local detect_out
        detect_out="$(bash "${comp_dir}/detect.sh" 2>/dev/null || true)"

        # Extract STATUS line
        local status_var_prefix
        case "$comp" in
            cgc)           status_var_prefix="CGC" ;;
            chub)          status_var_prefix="CHUB" ;;
            workflow)      status_var_prefix="WORKFLOW" ;;
            hooks)         status_var_prefix="HOOKS" ;;
            system-tuning) status_var_prefix="SYSTEM_TUNING" ;;
            tokens-config) status_var_prefix="TOKENS_CONFIG" ;;
            *)             status_var_prefix="" ;;
        esac

        if [[ -n "$status_var_prefix" ]]; then
            detect_status=$(printf '%s' "$detect_out" \
                | grep "^${status_var_prefix}_STATUS=" \
                | cut -d= -f2 || true)
        fi
    fi
    detect_status="${detect_status:-unknown}"

    # Map detect status to doctor initial assessment
    local doctor_status="UNKNOWN"
    local note=""
    case "$detect_status" in
        missing)
            # Not installed — that's MISSING, not a verify failure
            printf '%-20s %-10s %s\n' "$comp" "MISSING" "not installed"
            return
            ;;
        foreign)
            note="foreign install detected"
            ;;
        partial)
            doctor_status="WARN"
            note="partial installation"
            ;;
        ours-healthy|ours-broken|*)
            ;;
    esac

    # Run verify script
    local verify_exit=0
    if [[ -f "${comp_dir}/verify.sh" ]]; then
        if [[ "$VERBOSE" == "true" ]]; then
            bash "${comp_dir}/verify.sh" 2>&1 || verify_exit=$?
        else
            bash "${comp_dir}/verify.sh" &>/dev/null || verify_exit=$?
        fi
    else
        verify_exit=1
        note="no verify.sh"
    fi

    # Map verify exit to doctor status
    case $verify_exit in
        0) doctor_status="OK"   ;;
        1) doctor_status="WARN" ;;
        *) doctor_status="FAIL" ;;
    esac

    [[ "$detect_status" == "foreign" && "$doctor_status" == "OK" ]] && note="foreign install, healthy"

    # State store info
    local installed_at=""
    installed_at="$(state_get "component.${comp}.installed_at" 2>/dev/null || true)"
    [[ -n "$installed_at" ]] && note="${note} (installed: ${installed_at})"

    printf '%-20s %-10s %s\n' "$comp" "$(printf '%s' "$doctor_status")" "${note:-}"
}

# ---------------------------------------------------------------------------
# System prerequisites check
# ---------------------------------------------------------------------------
_doctor_system() {
    log_section "System Prerequisites"
    local issues=0

    # bash version
    local bash_ver="${BASH_VERSION:-unknown}"
    log_info "bash: ${bash_ver}"
    if [[ "${bash_ver%%.*}" -lt 4 ]]; then
        log_warn "bash version < 4 — some features may not work (array issues on macOS bash 3)"
        issues=$((issues + 1))
    fi

    # git
    if command -v git &>/dev/null; then
        log_ok "git: $(git --version)"
    else
        log_error "git: not found — required for cloning components"
        issues=$((issues + 1))
    fi

    # python3
    if command -v python3 &>/dev/null; then
        log_ok "python3: $(python3 --version 2>&1)"
    else
        log_warn "python3: not found — some components may require it"
        issues=$((issues + 1))
    fi

    # ~/.local/bin in PATH
    if [[ ":${PATH}:" == *":${HOME}/.local/bin:"* ]]; then
        log_ok "PATH: ~/.local/bin present"
    else
        log_warn "PATH: ~/.local/bin not in PATH — installed binaries may not be reachable"
        issues=$((issues + 1))
    fi

    # ~/.claude directory
    if [[ -d "${HOME}/.claude" ]]; then
        log_ok "~/.claude: directory exists"
    else
        log_info "~/.claude: not found (will be created during install)"
    fi

    # Free disk space
    local disk_free_mb
    disk_free_mb=$(df -m "$HOME" 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)
    if [[ "$disk_free_mb" -lt 500 ]]; then
        log_warn "disk: only ${disk_free_mb}MB free in $HOME — may be tight"
        issues=$((issues + 1))
    else
        log_ok "disk: ${disk_free_mb}MB free in $HOME"
    fi

    # RAM
    local ram_mb
    ram_mb=$(awk '/MemTotal/ { printf "%d", $2/1024 }' /proc/meminfo 2>/dev/null || echo 0)
    local free_mb
    free_mb=$(awk '/MemAvailable/ { printf "%d", $2/1024 }' /proc/meminfo 2>/dev/null || echo 0)
    log_info "memory: total=${ram_mb}MB, available=${free_mb}MB"
    if [[ "$free_mb" -lt 128 ]]; then
        log_warn "memory: only ${free_mb}MB available — install may be slow"
        issues=$((issues + 1))
    fi

    printf '\nSystem check: %d issue(s) found\n\n' "$issues"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
ALL_COMPONENTS=(cgc chub workflow hooks system-tuning tokens-config)

printf '\n'
printf '%b%s%b\n' "${CLR_BOLD:-}" "Bloom Node Bootstrap — Doctor Report" "${CLR_RESET:-}"
printf 'Host: %s | %s | %s\n' \
    "$(hostname -s 2>/dev/null || echo unknown)" \
    "$(uname -m)" \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
printf '\n'

_doctor_system

log_section "Component Health"
local_line="$(printf '%.0s─' {1..60})"
printf '%-20s %-10s %s\n' "Component" "Status" "Notes"
printf '%s\n' "$local_line"

overall_fail=0
overall_warn=0

if [[ -n "$FILTER_COMPONENT" ]]; then
    _doctor_component "$FILTER_COMPONENT"
else
    for comp in "${ALL_COMPONENTS[@]}"; do
        result="$(_doctor_component "$comp")"
        printf '%s\n' "$result"

        if printf '%s' "$result" | grep -q "FAIL"; then
            overall_fail=$((overall_fail + 1))
        elif printf '%s' "$result" | grep -qE "WARN|MISSING"; then
            overall_warn=$((overall_warn + 1))
        fi
    done
fi

printf '\n'
printf 'Summary: %d failure(s), %d warning(s)\n' "$overall_fail" "$overall_warn"

if [[ "$overall_fail" -gt 0 ]]; then
    printf '%bRun ./install.sh --apply to repair failed components.%b\n' \
        "${CLR_RED:-}" "${CLR_RESET:-}"
    exit 1
elif [[ "$overall_warn" -gt 0 ]]; then
    printf '%bSome warnings detected — run ./install.sh --verify for details.%b\n' \
        "${CLR_YELLOW:-}" "${CLR_RESET:-}"
    exit 0
else
    printf '%bAll checks passed.%b\n' "${CLR_GREEN:-}" "${CLR_RESET:-}"
    exit 0
fi
