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

    # Known install locations (canonical path first)
    local search_dirs=(
        "${HOME}/.bloom/sources/claude-codex-workflow"
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
        WORKFLOW_HAS_MANIFEST=false
        WORKFLOW_HAS_ARTIFACTS=false
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

    # Detect ctx availability
    WORKFLOW_HAS_CTX=false
    WORKFLOW_CTX_PATH=""
    if command -v ctx &>/dev/null; then
        WORKFLOW_HAS_CTX=true
        WORKFLOW_CTX_PATH="$(command -v ctx)"
    elif [[ -f "${HOME}/.local/bin/ctx" ]]; then
        WORKFLOW_HAS_CTX=true
        WORKFLOW_CTX_PATH="${HOME}/.local/bin/ctx"
    fi

    # Detect skill installation
    WORKFLOW_HAS_SKILL=false
    [[ -f "${HOME}/.claude/skills/claude-codex-workflow.md" ]] && WORKFLOW_HAS_SKILL=true

    # Detect routing manifest and artifacts
    WORKFLOW_HAS_MANIFEST=false
    WORKFLOW_HAS_ARTIFACTS=false
    if [[ -f "${wf_path}/skills/manifest.json" ]]; then
        WORKFLOW_HAS_MANIFEST=true
    fi
    if [[ -f "${wf_path}/skills/context_artifacts.json" ]]; then
        WORKFLOW_HAS_ARTIFACTS=true
    fi

    _wf_export_and_print
}

_wf_export_and_print() {
    export WORKFLOW_STATUS WORKFLOW_PATH WORKFLOW_VERSION WORKFLOW_OUR_VERSION WORKFLOW_HEALTHY
    export WORKFLOW_HAS_CTX WORKFLOW_CTX_PATH WORKFLOW_HAS_SKILL
    export WORKFLOW_HAS_MANIFEST WORKFLOW_HAS_ARTIFACTS

    log_debug "workflow/detect: STATUS=${WORKFLOW_STATUS} PATH=${WORKFLOW_PATH} CTX=${WORKFLOW_HAS_CTX:-false} SKILL=${WORKFLOW_HAS_SKILL:-false} MANIFEST=${WORKFLOW_HAS_MANIFEST:-false}"
    printf 'WORKFLOW_STATUS=%s\nWORKFLOW_PATH=%s\nWORKFLOW_VERSION=%s\nWORKFLOW_OUR_VERSION=%s\nWORKFLOW_HEALTHY=%s\nWORKFLOW_HAS_CTX=%s\nWORKFLOW_CTX_PATH=%s\nWORKFLOW_HAS_SKILL=%s\nWORKFLOW_HAS_MANIFEST=%s\nWORKFLOW_HAS_ARTIFACTS=%s\n' \
        "$WORKFLOW_STATUS" "${WORKFLOW_PATH:-}" "$WORKFLOW_VERSION" "$WORKFLOW_OUR_VERSION" \
        "$WORKFLOW_HEALTHY" "${WORKFLOW_HAS_CTX:-false}" "${WORKFLOW_CTX_PATH:-}" \
        "${WORKFLOW_HAS_SKILL:-false}" "${WORKFLOW_HAS_MANIFEST:-false}" "${WORKFLOW_HAS_ARTIFACTS:-false}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bloom_detect_workflow
fi
