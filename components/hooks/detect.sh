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

    # Detect canonical workflow hooks specifically
    HOOKS_HAS_POLICY=false
    HOOKS_HAS_SKILL_HOOK=false
    HOOKS_HAS_DISPATCH=false
    [[ -x "${hooks_dir}/ctx-workflow-policy.sh" ]]  && HOOKS_HAS_POLICY=true
    [[ -x "${hooks_dir}/unified-skill-hook.sh" ]]   && HOOKS_HAS_SKILL_HOOK=true
    [[ -x "${hooks_dir}/UserPromptSubmit" ]]         && HOOKS_HAS_DISPATCH=true

    # Check settings.json registration
    HOOKS_REGISTERED=false
    local settings="${HOME}/.claude/settings.json"
    if [[ -f "$settings" ]]; then
        if python3 -c "
import sys, json
with open('${settings}') as f: d = json.load(f)
hooks = d.get('hooks', {}).get('UserPromptSubmit', [])
cmds = [h.get('command','') for e in hooks for h in e.get('hooks',[])]
found = sum(1 for c in cmds if 'ctx-workflow-policy' in c or 'unified-skill-hook' in c)
sys.exit(0 if found >= 2 else 1)
" 2>/dev/null; then
            HOOKS_REGISTERED=true
        fi
    fi

    # Override status if canonical hooks are all present
    if [[ "$HOOKS_HAS_POLICY" == "true" && "$HOOKS_HAS_SKILL_HOOK" == "true" && "$HOOKS_HAS_DISPATCH" == "true" ]]; then
        HOOKS_OUR_VERSION=true
        HOOKS_STATUS="ours-healthy"
        HOOKS_HEALTHY=true
    fi

    _hooks_export_and_print
}

_hooks_export_and_print() {
    export HOOKS_STATUS HOOKS_PATH HOOKS_COUNT HOOKS_BLOOM_COUNT HOOKS_OUR_VERSION HOOKS_HEALTHY
    export HOOKS_HAS_POLICY HOOKS_HAS_SKILL_HOOK HOOKS_HAS_DISPATCH HOOKS_REGISTERED

    log_debug "hooks/detect: STATUS=${HOOKS_STATUS} POLICY=${HOOKS_HAS_POLICY:-false} SKILL=${HOOKS_HAS_SKILL_HOOK:-false} DISPATCH=${HOOKS_HAS_DISPATCH:-false} REGISTERED=${HOOKS_REGISTERED:-false}"
    printf 'HOOKS_STATUS=%s\nHOOKS_PATH=%s\nHOOKS_COUNT=%s\nHOOKS_BLOOM_COUNT=%s\nHOOKS_OUR_VERSION=%s\nHOOKS_HEALTHY=%s\nHOOKS_HAS_POLICY=%s\nHOOKS_HAS_SKILL_HOOK=%s\nHOOKS_HAS_DISPATCH=%s\nHOOKS_REGISTERED=%s\n' \
        "$HOOKS_STATUS" "${HOOKS_PATH:-}" "$HOOKS_COUNT" "$HOOKS_BLOOM_COUNT" \
        "$HOOKS_OUR_VERSION" "$HOOKS_HEALTHY" \
        "${HOOKS_HAS_POLICY:-false}" "${HOOKS_HAS_SKILL_HOOK:-false}" \
        "${HOOKS_HAS_DISPATCH:-false}" "${HOOKS_REGISTERED:-false}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bloom_detect_hooks
fi
