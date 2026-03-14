#!/usr/bin/env bash
# components/workflow/detect.sh
# Detection for claude-codex-workflow component.
#
# COMPONENT_STATUS: missing | ours-healthy | ours-broken | foreign | partial

set -euo pipefail

_WF_DETECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BLOOM_ROOT_GUESS="$(cd "${_WF_DETECT_DIR}/../.." && pwd)"

if ! declare -f log_debug &>/dev/null; then
    source "${_BLOOM_ROOT_GUESS}/bootstrap/common.sh"
fi

bloom_detect_workflow() {
    log_debug "workflow/detect: starting"

    local wf_path=""
    local wf_version=""
    local wf_our_version=false

    # Known install locations
    local search_dirs=(
        "${HOME}/.claude/workflow"
        "${HOME}/claude-codex-workflow"
        "${HOME}/.local/share/bloom/workflow"
        "${HOME}/.config/claude/workflow"
    )

    for loc in "${search_dirs[@]}"; do
        if [[ -d "$loc" ]]; then
            wf_path="$loc"
            break
        fi
    done

    if [[ -z "$wf_path" ]]; then
        log_debug "workflow/detect: not found"
        WORKFLOW_STATUS="missing"
        WORKFLOW_PATH=""
        WORKFLOW_VERSION=""
        WORKFLOW_OUR_VERSION=false
        WORKFLOW_HEALTHY=false
        _wf_export_and_print
        return 0
    fi

    log_debug "workflow/detect: found at ${wf_path}"

    # Get version from VERSION file or git tag
    if [[ -f "${wf_path}/VERSION" ]]; then
        wf_version="$(cat "${wf_path}/VERSION")"
    elif [[ -d "${wf_path}/.git" ]]; then
        wf_version="$(git -C "$wf_path" describe --tags --always 2>/dev/null || echo "git-unknown")"
    else
        wf_version="unknown"
    fi

    # Check if ours: look for git remote or bloom marker
    if [[ -d "${wf_path}/.git" ]]; then
        local remote
        remote="$(git -C "$wf_path" remote get-url origin 2>/dev/null || echo "")"
        if [[ "$remote" == *"vokov/claude-codex-workflow"* ]] || \
           [[ -f "${wf_path}/.bloom-marker" ]]; then
            wf_our_version=true
        fi
    fi
    [[ -f "${wf_path}/bloom-workflow.conf" ]] && wf_our_version=true

    # Health check: required files present?
    local required_files=()
    local partial=false

    # Workflow should have at least a README or main entry point
    if [[ ! -f "${wf_path}/README.md" ]] && [[ ! -f "${wf_path}/workflow.sh" ]] && \
       [[ ! -f "${wf_path}/CLAUDE.md" ]]; then
        partial=true
    fi

    if [[ "$partial" == "true" ]]; then
        WORKFLOW_STATUS="partial"
        WORKFLOW_HEALTHY=false
    elif [[ "$wf_our_version" == "true" ]]; then
        WORKFLOW_STATUS="ours-healthy"
        WORKFLOW_HEALTHY=true
    else
        WORKFLOW_STATUS="foreign"
        WORKFLOW_HEALTHY=true
    fi

    WORKFLOW_PATH="$wf_path"
    WORKFLOW_VERSION="$wf_version"
    WORKFLOW_OUR_VERSION="$wf_our_version"

    _wf_export_and_print
}

_wf_export_and_print() {
    export WORKFLOW_STATUS WORKFLOW_PATH WORKFLOW_VERSION WORKFLOW_OUR_VERSION WORKFLOW_HEALTHY

    log_debug "workflow/detect: STATUS=${WORKFLOW_STATUS} PATH=${WORKFLOW_PATH}"
    printf 'WORKFLOW_STATUS=%s\nWORKFLOW_PATH=%s\nWORKFLOW_VERSION=%s\nWORKFLOW_OUR_VERSION=%s\nWORKFLOW_HEALTHY=%s\n' \
        "$WORKFLOW_STATUS" "$WORKFLOW_PATH" "$WORKFLOW_VERSION" "$WORKFLOW_OUR_VERSION" "$WORKFLOW_HEALTHY"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bloom_detect_workflow
fi
