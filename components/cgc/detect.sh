#!/usr/bin/env bash
# components/cgc/detect.sh
# Detection logic for the cgc component (Claude git CLI for RPi/low-RAM nodes).
# Sets COMPONENT_STATUS and related vars, then prints a summary.
#
# COMPONENT_STATUS values:
#   missing       — not found anywhere
#   ours-healthy  — our install, passing verify
#   ours-broken   — our install, verify fails
#   foreign       — exists but not installed by us
#   partial       — found but incomplete install

set -euo pipefail

_CGC_DETECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BLOOM_ROOT_GUESS="$(cd "${_CGC_DETECT_DIR}/../.." && pwd)"

if ! declare -f log_debug &>/dev/null; then
    # shellcheck source=bootstrap/common.sh
    source "${_BLOOM_ROOT_GUESS}/bootstrap/common.sh"
fi

# ---------------------------------------------------------------------------
# bloom_detect_cgc
# Main detection function. Sets and exports detection vars.
# ---------------------------------------------------------------------------
bloom_detect_cgc() {
    log_debug "cgc/detect: starting"

    local cgc_path=""
    local cgc_version=""
    local cgc_our_version=false

    # Search for cgc binary in known locations + PATH
    local search_paths=(
        "${HOME}/.local/bin/cgc"
        "${HOME}/cgc/cgc"
        "${HOME}/cgc-rpi/cgc"
        "${HOME}/bin/cgc"
        "/usr/local/bin/cgc"
        "/usr/bin/cgc"
    )

    for loc in "${search_paths[@]}"; do
        if [[ -f "$loc" && -x "$loc" ]]; then
            cgc_path="$loc"
            break
        fi
    done

    # Also check PATH
    if [[ -z "$cgc_path" ]] && command -v cgc &>/dev/null; then
        cgc_path="$(command -v cgc)"
    fi

    if [[ -z "$cgc_path" ]]; then
        log_debug "cgc/detect: not found"
        CGC_STATUS="missing"
        CGC_PATH=""
        CGC_VERSION=""
        CGC_OUR_VERSION=false
        CGC_HEALTHY=false
        _cgc_export_and_print
        return 0
    fi

    log_debug "cgc/detect: found at ${cgc_path}"

    # Try to get version
    cgc_version="$(${cgc_path} --version 2>/dev/null | head -1 || echo "unknown")"

    # Check if this is our version (look for bloom marker or known repo patterns)
    if grep -q "bloom-node-bootstrap\|vokov/cgc\|cgc-rpi" "$cgc_path" 2>/dev/null; then
        cgc_our_version=true
    fi

    # Check if a cgc repo directory exists (indicates our install)
    local cgc_repo=""
    for repo_loc in "${HOME}/cgc-rpi" "${HOME}/cgc" "${HOME}/.local/share/bloom/cgc"; do
        if [[ -d "${repo_loc}/.git" ]]; then
            cgc_repo="$repo_loc"
            break
        fi
    done

    if [[ "$cgc_our_version" == "true" ]] || [[ -n "$cgc_repo" ]]; then
        # Run a basic health check
        if ${cgc_path} --help &>/dev/null 2>&1; then
            CGC_STATUS="ours-healthy"
            CGC_HEALTHY=true
        else
            CGC_STATUS="ours-broken"
            CGC_HEALTHY=false
        fi
        CGC_OUR_VERSION=true
    else
        # Something called cgc is installed but we don't recognize it
        CGC_STATUS="foreign"
        CGC_HEALTHY=true   # assume foreign works unless we test further
        CGC_OUR_VERSION=false
    fi

    CGC_PATH="$cgc_path"
    CGC_VERSION="$cgc_version"
    CGC_REPO="${cgc_repo:-}"

    _cgc_export_and_print
}

_cgc_export_and_print() {
    export CGC_STATUS CGC_PATH CGC_VERSION CGC_OUR_VERSION CGC_HEALTHY
    export CGC_REPO="${CGC_REPO:-}"

    log_debug "cgc/detect: STATUS=${CGC_STATUS} PATH=${CGC_PATH} VERSION=${CGC_VERSION} OURS=${CGC_OUR_VERSION}"
    printf 'CGC_STATUS=%s\nCGC_PATH=%s\nCGC_VERSION=%s\nCGC_OUR_VERSION=%s\nCGC_HEALTHY=%s\nCGC_REPO=%s\n' \
        "$CGC_STATUS" "$CGC_PATH" "$CGC_VERSION" "$CGC_OUR_VERSION" "$CGC_HEALTHY" "${CGC_REPO:-}"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bloom_detect_cgc
fi
