#!/usr/bin/env bash
# install.sh
# Main entry point for bloom-node-bootstrap.
# Parses CLI args and dispatches the detect → profile → plan → apply pipeline.
#
# Usage:
#   install.sh [OPTIONS]
#
# Options:
#   --detect              Run detection only, print results and exit
#   --plan                Show install plan (detect + profile resolution)
#   --apply               Execute the install plan (default when no mode given)
#   --verify              Run verify on all/specified components
#   --doctor              Run full health check (alias: --check)
#   --component COMP      Operate on a single component only
#   --profile PROFILE     Override auto-detected profile
#   --mode MODE           Override install mode for all components
#   --dry-run             Show what would be done without doing it
#   --yes                 Assume yes to all prompts (non-interactive)
#   --log-level LEVEL     Set log level: debug|info|warn|error
#   --help                Show this help

set -euo pipefail

# ---------------------------------------------------------------------------
# Bootstrap: find BLOOM_ROOT from this script's location
# ---------------------------------------------------------------------------
_INSTALL_SCRIPT="${BASH_SOURCE[0]}"
while [[ -L "$_INSTALL_SCRIPT" ]]; do
    _INSTALL_SCRIPT="$(readlink "$_INSTALL_SCRIPT")"
done
BLOOM_ROOT="$(cd "$(dirname "$_INSTALL_SCRIPT")" && pwd)"
export BLOOM_ROOT

# ---------------------------------------------------------------------------
# Source core libraries
# ---------------------------------------------------------------------------
# shellcheck source=bootstrap/logging.sh
source "${BLOOM_ROOT}/bootstrap/logging.sh"
# shellcheck source=bootstrap/common.sh
source "${BLOOM_ROOT}/bootstrap/common.sh"
# shellcheck source=bootstrap/state-store.sh
source "${BLOOM_ROOT}/bootstrap/state-store.sh"
# shellcheck source=bootstrap/profile-resolver.sh
source "${BLOOM_ROOT}/bootstrap/profile-resolver.sh"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
ACTION=""
FILTER_COMPONENT=""
FORCED_PROFILE=""
FORCED_MODE=""
DRY_RUN="${DRY_RUN:-false}"
BLOOM_ASSUME_YES="${BLOOM_ASSUME_YES:-false}"
BLOOM_LOG_LEVEL="${BLOOM_LOG_LEVEL:-info}"

# ---------------------------------------------------------------------------
# _usage — print help and exit
# ---------------------------------------------------------------------------
_usage() {
    cat >&2 <<HELP

  bloom-node-bootstrap — adaptive dev stack installer for low-resource Linux nodes

  Usage: $(basename "$0") [OPTIONS]

  Pipeline Modes:
    --detect              Run system detection and print results
    --plan                Show what would be installed and how
    --apply               Execute the full install pipeline  [DEFAULT]
    --verify              Run component verification
    --doctor              Run full health check report

  Targeting:
    --component COMP      Operate on one component only
                          Components: cgc chub workflow hooks system-tuning tokens-config
    --profile PROFILE     Override auto-resolved profile
                          Profiles: $(list_profiles | tr '\n' ' ')
    --mode MODE           Override install mode for all components
                          Modes: install reuse wrap replace side-by-side skip

  Behavior:
    --dry-run             Print actions without executing them
    --yes                 Assume yes to all interactive prompts
    --log-level LEVEL     debug | info | warn | error  (default: info)

  Examples:
    $(basename "$0") --detect
    $(basename "$0") --plan --profile rpi-lowram
    $(basename "$0") --apply --dry-run
    $(basename "$0") --apply --component cgc --mode replace
    $(basename "$0") --verify --component hooks
    $(basename "$0") --doctor

HELP
    exit 0
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --detect)           ACTION="detect"; shift ;;
        --plan)             ACTION="plan"; shift ;;
        --apply)            ACTION="apply"; shift ;;
        --verify)           ACTION="verify"; shift ;;
        --doctor|--check)   ACTION="doctor"; shift ;;
        --component|-c)     FILTER_COMPONENT="$2"; shift 2 ;;
        --profile)          FORCED_PROFILE="$2"; shift 2 ;;
        --mode)             FORCED_MODE="$2"; shift 2 ;;
        --dry-run)          DRY_RUN="true"; export DRY_RUN; shift ;;
        --yes|-y)           BLOOM_ASSUME_YES="true"; export BLOOM_ASSUME_YES; shift ;;
        --log-level)        BLOOM_LOG_LEVEL="$2"; export BLOOM_LOG_LEVEL; shift 2 ;;
        --help|-h)          _usage ;;
        *)
            log_error "Unknown argument: $1"
            log_error "Run '$(basename "$0") --help' for usage."
            exit 1
            ;;
    esac
done

# Default action: apply
ACTION="${ACTION:-apply}"

# ---------------------------------------------------------------------------
# _run_detect — run detect.sh and source results
# ---------------------------------------------------------------------------
_run_detect() {
    log_step "Phase 1: System Detection"
    bash "${BLOOM_ROOT}/detect.sh" --kv 2>/dev/null
    # Also load into current env for pipeline use
    eval "$(bash "${BLOOM_ROOT}/detect.sh" --export 2>/dev/null)"
    log_ok "Detection complete"
}

# ---------------------------------------------------------------------------
# _run_profile_resolve — resolve profile and load it
# ---------------------------------------------------------------------------
_run_profile_resolve() {
    log_step "Phase 2: Profile Resolution"

    if [[ -n "$FORCED_PROFILE" ]]; then
        PROFILE_NAME="$FORCED_PROFILE"
        log_info "Profile forced: ${PROFILE_NAME}"
    else
        PROFILE_NAME="$(resolve_profile)"
        log_info "Auto-resolved profile: ${PROFILE_NAME}"
    fi

    source_profile "$PROFILE_NAME"
    export PROFILE_NAME

    log_ok "Profile loaded: ${PROFILE_NAME} — ${PROFILE_DESC:-}"

    if [[ -n "${PROFILE_NOTES:-}" ]]; then
        log_warn "Profile notes: ${PROFILE_NOTES}"
    fi
}

# ---------------------------------------------------------------------------
# _get_component_mode COMPONENT
# Return the mode to use for this component, respecting overrides.
# ---------------------------------------------------------------------------
_get_component_mode() {
    local comp="$1"
    if [[ -n "$FORCED_MODE" ]]; then
        echo "$FORCED_MODE"
        return
    fi

    # Profile-defined default
    local comp_upper="${comp//-/_}"
    comp_upper="${comp_upper^^}"
    local mode_var="PROFILE_DEFAULT_MODE_${comp_upper}"
    local mode="${!mode_var:-install}"
    echo "$mode"
}

# ---------------------------------------------------------------------------
# _run_component_install COMPONENT
# Install one component with appropriate mode.
# ---------------------------------------------------------------------------
_run_component_install() {
    local comp="$1"
    local install_script="${BLOOM_ROOT}/components/${comp}/install.sh"

    if [[ ! -f "$install_script" ]]; then
        log_warn "No install script for component: ${comp} — skipping"
        return 0
    fi

    local mode
    mode="$(_get_component_mode "$comp")"

    log_info "Component ${comp}: mode=${mode}"
    MODE="$mode" bash "$install_script"
}

# ---------------------------------------------------------------------------
# _run_component_verify COMPONENT
# Verify one component.
# ---------------------------------------------------------------------------
_run_component_verify() {
    local comp="$1"
    local verify_script="${BLOOM_ROOT}/components/${comp}/verify.sh"

    if [[ ! -f "$verify_script" ]]; then
        log_warn "No verify script for component: ${comp}"
        return 1
    fi

    bash "$verify_script"
}

# ---------------------------------------------------------------------------
# _apply_pipeline — full install
# ---------------------------------------------------------------------------
_apply_pipeline() {
    log_section "bloom-node-bootstrap: Apply"

    _run_detect
    _run_profile_resolve

    # Confirm before proceeding (unless --yes or dry-run)
    if [[ "${DRY_RUN}" != "true" ]]; then
        log_info "About to install/configure: ${PROFILE_COMPONENTS:-cgc chub workflow hooks tokens-config}"
        if ! confirm "Proceed with installation?"; then
            log_info "Installation cancelled."
            exit 0
        fi
    fi

    # Record bootstrap start
    state_set "bootstrap.started_at" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    state_set "bootstrap.profile" "$PROFILE_NAME"
    state_set "bootstrap.host" "$(hostname -s 2>/dev/null || echo unknown)"

    log_step "Phase 3: Install Components"

    IFS=' ' read -ra COMPONENTS <<< "${PROFILE_COMPONENTS:-cgc chub workflow hooks tokens-config}"

    local failed_components=()

    if [[ -n "$FILTER_COMPONENT" ]]; then
        COMPONENTS=("$FILTER_COMPONENT")
    fi

    for comp in "${COMPONENTS[@]}"; do
        log_section "Component: ${comp}"
        if _run_component_install "$comp"; then
            log_ok "${comp}: install complete"
        else
            log_error "${comp}: install FAILED"
            failed_components+=("$comp")
            # Don't abort — try remaining components
        fi
    done

    log_step "Phase 4: Post-Install Verification"

    local verify_failures=0
    for comp in "${COMPONENTS[@]}"; do
        if _run_component_verify "$comp" 2>/dev/null; then
            log_ok "${comp}: verified"
        else
            local exit_code=$?
            [[ $exit_code -eq 1 ]] && log_warn "${comp}: verified with warnings"
            [[ $exit_code -ge 2 ]] && { log_error "${comp}: verification FAILED"; verify_failures=$((verify_failures+1)); }
        fi
    done

    state_set "bootstrap.completed_at" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    printf '\n'
    if [[ ${#failed_components[@]} -gt 0 ]]; then
        log_error "Install failed for: ${failed_components[*]}"
        log_error "Run './doctor.sh' for details."
        exit 1
    elif [[ $verify_failures -gt 0 ]]; then
        log_warn "Install complete with ${verify_failures} verification failure(s)"
        log_warn "Run './doctor.sh' for details."
        exit 0
    else
        log_ok "bloom-node-bootstrap installation complete!"
        log_info "Run './doctor.sh' to verify system health."
        exit 0
    fi
}

# ---------------------------------------------------------------------------
# _verify_pipeline — verification only
# ---------------------------------------------------------------------------
_verify_pipeline() {
    log_section "bloom-node-bootstrap: Verify"

    IFS=' ' read -ra COMPONENTS <<< "${PROFILE_COMPONENTS:-cgc chub workflow hooks tokens-config}"
    [[ -n "$FILTER_COMPONENT" ]] && COMPONENTS=("$FILTER_COMPONENT")

    local total=0
    local passed=0

    for comp in "${COMPONENTS[@]}"; do
        total=$((total + 1))
        if _run_component_verify "$comp"; then
            passed=$((passed + 1))
        fi
    done

    printf '\nVerification: %d/%d passed\n' "$passed" "$total"
    [[ "$passed" -eq "$total" ]] && exit 0 || exit 1
}

# ---------------------------------------------------------------------------
# Main dispatcher
# ---------------------------------------------------------------------------
case "$ACTION" in
    detect)
        _run_detect
        ;;

    plan)
        # Delegate to plan.sh
        plan_args=()
        [[ -n "$FORCED_PROFILE" ]] && plan_args+=(--profile "$FORCED_PROFILE")
        bash "${BLOOM_ROOT}/plan.sh" "${plan_args[@]}"
        ;;

    apply)
        _apply_pipeline
        ;;

    verify)
        # Need profile loaded for component list
        eval "$(bash "${BLOOM_ROOT}/detect.sh" --export 2>/dev/null)"
        if [[ -n "$FORCED_PROFILE" ]]; then
            PROFILE_NAME="$FORCED_PROFILE"
        else
            PROFILE_NAME="$(resolve_profile)"
        fi
        source_profile "$PROFILE_NAME"
        _verify_pipeline
        ;;

    doctor)
        doctor_args=()
        [[ -n "$FILTER_COMPONENT" ]] && doctor_args+=(--component "$FILTER_COMPONENT")
        [[ "${BLOOM_LOG_LEVEL}" == "debug" ]] && doctor_args+=(--verbose)
        bash "${BLOOM_ROOT}/doctor.sh" "${doctor_args[@]}"
        ;;

    *)
        log_error "Unknown action: ${ACTION}"
        _usage
        ;;
esac
