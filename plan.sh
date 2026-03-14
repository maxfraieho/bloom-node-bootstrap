#!/usr/bin/env bash
# plan.sh
# Given the detected environment + resolved profile, output a human-readable
# install plan table showing what will happen for each component.
#
# Usage:
#   ./plan.sh [--profile PROFILE] [--detect-file FILE]
#
# Reads:
#   - detect.sh output (sourced or from file)
#   - profile variables (sourced from profiles/)
#   - state store (existing installs)
#
# Output format:
#   Component        | Status       | Mode         | Action
#   ─────────────────┼──────────────┼──────────────┼─────────────────────────────
#   cgc              | missing      | install      | clone + setup from github
#   chub             | foreign      | wrap         | add bloom layer on top

set -euo pipefail

PLAN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLOOM_ROOT="$PLAN_DIR"
export BLOOM_ROOT

source "${BLOOM_ROOT}/bootstrap/logging.sh"
source "${BLOOM_ROOT}/bootstrap/common.sh"
source "${BLOOM_ROOT}/bootstrap/state-store.sh"
source "${BLOOM_ROOT}/bootstrap/profile-resolver.sh"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
DETECT_FILE=""
FORCED_PROFILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)   FORCED_PROFILE="$2"; shift 2 ;;
        --detect-file) DETECT_FILE="$2"; shift 2 ;;
        --help|-h)
            printf 'Usage: %s [--profile PROFILE] [--detect-file FILE]\n' "$(basename "$0")" >&2
            exit 0 ;;
        *) log_warn "plan.sh: unknown argument: $1"; shift ;;
    esac
done

# ---------------------------------------------------------------------------
# Source detect output
# ---------------------------------------------------------------------------
if [[ -n "$DETECT_FILE" && -f "$DETECT_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$DETECT_FILE"
else
    # Run detect inline
    log_debug "plan.sh: running detect.sh"
    eval "$(bash "${BLOOM_ROOT}/detect.sh" --export 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# Resolve profile
# ---------------------------------------------------------------------------
if [[ -n "$FORCED_PROFILE" ]]; then
    PROFILE_NAME="$FORCED_PROFILE"
else
    PROFILE_NAME="$(resolve_profile)"
fi

log_debug "plan.sh: using profile=${PROFILE_NAME}"
source_profile "$PROFILE_NAME"

# ---------------------------------------------------------------------------
# _plan_component COMPONENT
# Source component detect.sh and map to plan output row.
# ---------------------------------------------------------------------------
_plan_component() {
    local comp="$1"
    local comp_script="${BLOOM_ROOT}/components/${comp}/detect.sh"

    if [[ ! -f "$comp_script" ]]; then
        printf '%-20s %-14s %-14s %s\n' "$comp" "unknown" "skip" "no component script found"
        return
    fi

    # Source detect and capture vars — run in subshell to isolate
    local detect_out
    detect_out="$(bash "$comp_script" 2>/dev/null)"
    local comp_status=""
    local comp_var_prefix

    # Map component name to its status variable prefix
    case "$comp" in
        cgc)            comp_var_prefix="CGC" ;;
        chub)           comp_var_prefix="CHUB" ;;
        workflow)       comp_var_prefix="WORKFLOW" ;;
        hooks)          comp_var_prefix="HOOKS" ;;
        system-tuning)  comp_var_prefix="SYSTEM_TUNING" ;;
        tokens-config)  comp_var_prefix="TOKENS_CONFIG" ;;
        *)              comp_var_prefix="" ;;
    esac

    # Extract status from detect output
    if [[ -n "$comp_var_prefix" ]]; then
        comp_status=$(printf '%s' "$detect_out" | grep "^${comp_var_prefix}_STATUS=" | cut -d= -f2)
    fi
    comp_status="${comp_status:-unknown}"

    # Determine mode from profile variables
    local mode_var="PROFILE_DEFAULT_MODE_${comp_var_prefix}"
    mode_var="${mode_var//-/_}"    # system-tuning → SYSTEM_TUNING
    local mode="${!mode_var:-install}"

    # Override mode based on current status + idempotency
    local action=""
    case "$comp_status" in
        ours-healthy)
            mode="reuse"
            action="already installed — verify only"
            ;;
        ours-broken)
            mode="replace"
            action="reinstall (our broken install)"
            ;;
        foreign)
            case "$mode" in
                install) mode="wrap"; action="foreign exists — add bloom layer" ;;
                wrap)    action="add bloom layer on top of existing" ;;
                replace) action="backup + replace with ours" ;;
                reuse)   action="register existing as-is" ;;
                *)       action="apply mode: ${mode}" ;;
            esac
            ;;
        missing)
            case "$mode" in
                reuse)   action="will be skipped (reuse with nothing to reuse)" ;;
                skip)    action="explicitly skipped by profile" ;;
                *)       action="clone + setup" ;;
            esac
            ;;
        partial)
            mode="replace"
            action="partial install — complete installation"
            ;;
        *)
            action="apply mode: ${mode}"
            ;;
    esac

    # Check state store for previously skipped
    if state_has "component.${comp}.skip" 2>/dev/null; then
        local skip_reason
        skip_reason="$(state_get "component.${comp}.skip_reason" 2>/dev/null || echo "skipped")"
        mode="skip"
        action="previously skipped (${skip_reason})"
    fi

    printf '%-20s %-14s %-14s %s\n' "$comp" "$comp_status" "$mode" "$action"
}

# ---------------------------------------------------------------------------
# Print plan header
# ---------------------------------------------------------------------------
_print_header() {
    printf '\n'
    printf '%b%s%b\n' "${CLR_BOLD:-}" "Bloom Node Bootstrap — Install Plan" "${CLR_RESET:-}"
    printf 'Profile: %s (%s)\n' "$PROFILE_NAME" "${PROFILE_DESC:-}"
    printf 'Host:    %s | Arch: %s | RAM: %sMB | Distro: %s %s\n' \
        "${HOSTNAME_SHORT:-$(hostname -s)}" \
        "${ARCH:-$(uname -m)}" \
        "${RAM_MB:-?}" \
        "${DISTRO:-unknown}" \
        "${DISTRO_VERSION:-}"
    printf '\n'

    local line
    line="$(printf '%.0s─' {1..80})"
    printf '%-20s %-14s %-14s %s\n' "Component" "Status" "Mode" "Action"
    printf '%s\n' "$line"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
_print_header

# Iterate over profile components
IFS=' ' read -ra COMPONENTS <<< "${PROFILE_COMPONENTS:-cgc chub workflow hooks tokens-config}"

for comp in "${COMPONENTS[@]}"; do
    _plan_component "$comp"
done

printf '\n'
printf 'Profile notes: %s\n' "${PROFILE_NOTES:-none}"
printf '\n'
printf 'Run with --apply to execute this plan.\n'
printf '\n'
