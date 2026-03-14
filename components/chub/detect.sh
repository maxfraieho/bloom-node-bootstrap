#!/usr/bin/env bash
# components/chub/detect.sh
# Detection logic for chub (context-hub) component.
#
# COMPONENT_STATUS values:
#   missing       — not found
#   ours-healthy  — our install, passing verify
#   ours-broken   — our install, verify fails
#   foreign       — exists but not installed by us
#   partial       — found but incomplete

set -euo pipefail

_CHUB_DETECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BLOOM_ROOT_GUESS="$(cd "${_CHUB_DETECT_DIR}/../.." && pwd)"

if ! declare -f log_debug &>/dev/null; then
    # shellcheck source=bootstrap/common.sh
    source "${_BLOOM_ROOT_GUESS}/bootstrap/common.sh"
fi

bloom_detect_chub() {
    log_debug "chub/detect: starting"

    local chub_path=""
    local chub_version=""
    local chub_our_version=false
    local chub_repo=""

    # Search known locations
    local search_paths=(
        "${HOME}/.local/bin/chub"
        "${HOME}/context-hub-rpi/chub"
        "${HOME}/context-hub/chub"
        "${HOME}/.local/share/bloom/chub/chub"
        "/usr/local/bin/chub"
    )

    for loc in "${search_paths[@]}"; do
        if [[ -f "$loc" && -x "$loc" ]]; then
            chub_path="$loc"
            break
        fi
    done

    if [[ -z "$chub_path" ]] && command -v chub &>/dev/null; then
        chub_path="$(command -v chub)"
    fi

    if [[ -z "$chub_path" ]]; then
        log_debug "chub/detect: not found"
        CHUB_STATUS="missing"
        CHUB_PATH=""
        CHUB_VERSION=""
        CHUB_OUR_VERSION=false
        CHUB_HEALTHY=false
        CHUB_REPO=""
        _chub_export_and_print
        return 0
    fi

    log_debug "chub/detect: found at ${chub_path}"

    chub_version="$(${chub_path} --version 2>/dev/null | head -1 || echo "unknown")"

    # Check if ours
    if grep -q "bloom-node-bootstrap\|vokov/context-hub\|context-hub-rpi" "$chub_path" 2>/dev/null; then
        chub_our_version=true
    fi

    # Look for repo directory
    for repo_loc in "${HOME}/context-hub-rpi" "${HOME}/context-hub" \
                     "${HOME}/.local/share/bloom/chub"; do
        if [[ -d "${repo_loc}/.git" ]]; then
            chub_repo="$repo_loc"
            break
        fi
    done

    if [[ "$chub_our_version" == "true" ]] || [[ -n "$chub_repo" ]]; then
        # Health check: can it respond?
        if "$chub_path" status &>/dev/null 2>&1 || "$chub_path" --help &>/dev/null 2>&1; then
            CHUB_STATUS="ours-healthy"
            CHUB_HEALTHY=true
        else
            CHUB_STATUS="ours-broken"
            CHUB_HEALTHY=false
        fi
        CHUB_OUR_VERSION=true
    else
        CHUB_STATUS="foreign"
        CHUB_HEALTHY=true
        CHUB_OUR_VERSION=false
    fi

    CHUB_PATH="$chub_path"
    CHUB_VERSION="$chub_version"
    CHUB_REPO="${chub_repo:-}"

    _chub_export_and_print
}

_chub_export_and_print() {
    export CHUB_STATUS CHUB_PATH CHUB_VERSION CHUB_OUR_VERSION CHUB_HEALTHY CHUB_REPO

    log_debug "chub/detect: STATUS=${CHUB_STATUS} PATH=${CHUB_PATH} OURS=${CHUB_OUR_VERSION}"
    printf 'CHUB_STATUS=%s\nCHUB_PATH=%s\nCHUB_VERSION=%s\nCHUB_OUR_VERSION=%s\nCHUB_HEALTHY=%s\nCHUB_REPO=%s\n' \
        "$CHUB_STATUS" "$CHUB_PATH" "$CHUB_VERSION" "$CHUB_OUR_VERSION" "$CHUB_HEALTHY" "${CHUB_REPO:-}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bloom_detect_chub
fi
