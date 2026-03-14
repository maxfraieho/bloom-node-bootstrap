#!/usr/bin/env bash
# components/hooks/detect.sh
# Detection for Claude hooks in ~/.claude/hooks/.
#
# COMPONENT_STATUS: missing | ours-healthy | ours-broken | foreign | partial

set -euo pipefail

_HOOKS_DETECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BLOOM_ROOT_GUESS="$(cd "${_HOOKS_DETECT_DIR}/../.." && pwd)"

if ! declare -f log_debug &>/dev/null; then
    source "${_BLOOM_ROOT_GUESS}/bootstrap/common.sh"
fi

bloom_detect_hooks() {
    log_debug "hooks/detect: starting"

    local hooks_dir="${HOME}/.claude/hooks"
    local hook_count=0
    local bloom_hooks=0

    if [[ ! -d "$hooks_dir" ]]; then
        log_debug "hooks/detect: directory not found at ${hooks_dir}"
        HOOKS_STATUS="missing"
        HOOKS_PATH=""
        HOOKS_COUNT=0
        HOOKS_BLOOM_COUNT=0
        HOOKS_OUR_VERSION=false
        HOOKS_HEALTHY=false
        _hooks_export_and_print
        return 0
    fi

    log_debug "hooks/detect: directory found at ${hooks_dir}"

    # Count hook files
    hook_count=$(find "$hooks_dir" -maxdepth 1 -type f \( -name "*.sh" -o -name "*.py" -o -name "*.json" \) 2>/dev/null | wc -l || echo 0)

    # Count bloom-installed hooks (have our marker comment)
    bloom_hooks=$(grep -rl "bloom-node-bootstrap\|BLOOM_HOOK" "$hooks_dir" 2>/dev/null | wc -l || echo 0)

    if [[ "$hook_count" -eq 0 ]]; then
        HOOKS_STATUS="missing"  # dir exists but empty
        HOOKS_HEALTHY=false
        HOOKS_OUR_VERSION=false
    elif [[ "$bloom_hooks" -gt 0 ]]; then
        # We installed at least some hooks
        # Verify they're executable
        local broken=0
        while IFS= read -r hookfile; do
            [[ -x "$hookfile" ]] || broken=$((broken + 1))
        done < <(grep -rl "bloom-node-bootstrap\|BLOOM_HOOK" "$hooks_dir" 2>/dev/null)

        if [[ "$broken" -gt 0 ]]; then
            HOOKS_STATUS="ours-broken"
            HOOKS_HEALTHY=false
        elif [[ "$bloom_hooks" -lt "$hook_count" ]]; then
            HOOKS_STATUS="partial"  # mix of ours and foreign
            HOOKS_HEALTHY=true
        else
            HOOKS_STATUS="ours-healthy"
            HOOKS_HEALTHY=true
        fi
        HOOKS_OUR_VERSION=true
    else
        # Hooks exist but none are ours
        HOOKS_STATUS="foreign"
        HOOKS_HEALTHY=true
        HOOKS_OUR_VERSION=false
    fi

    HOOKS_PATH="$hooks_dir"
    HOOKS_COUNT="$hook_count"
    HOOKS_BLOOM_COUNT="$bloom_hooks"

    _hooks_export_and_print
}

_hooks_export_and_print() {
    export HOOKS_STATUS HOOKS_PATH HOOKS_COUNT HOOKS_BLOOM_COUNT HOOKS_OUR_VERSION HOOKS_HEALTHY

    log_debug "hooks/detect: STATUS=${HOOKS_STATUS} COUNT=${HOOKS_COUNT} OURS=${HOOKS_BLOOM_COUNT}"
    printf 'HOOKS_STATUS=%s\nHOOKS_PATH=%s\nHOOKS_COUNT=%s\nHOOKS_BLOOM_COUNT=%s\nHOOKS_OUR_VERSION=%s\nHOOKS_HEALTHY=%s\n' \
        "$HOOKS_STATUS" "${HOOKS_PATH:-}" "$HOOKS_COUNT" "$HOOKS_BLOOM_COUNT" \
        "$HOOKS_OUR_VERSION" "$HOOKS_HEALTHY"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bloom_detect_hooks
fi
