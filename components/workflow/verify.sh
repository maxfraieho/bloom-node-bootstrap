#!/usr/bin/env bash
# components/workflow/verify.sh
# Health check for workflow component.
# Exit codes: 0=OK, 1=WARN, 2=FAIL

set -euo pipefail

_WF_VERIFY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BLOOM_ROOT_GUESS="$(cd "${_WF_VERIFY_DIR}/../.." && pwd)"

if ! declare -f log_info &>/dev/null; then
    source "${_BLOOM_ROOT_GUESS}/bootstrap/common.sh"
fi

bloom_verify_workflow() {
    log_section "Verifying component: workflow"

    local exit_code=0
    local issues=()

    # 1. Find workflow directory
    local wf_dir=""
    for loc in "${HOME}/.claude/workflow" "${HOME}/claude-codex-workflow" \
                "${HOME}/.local/share/bloom/workflow"; do
        if [[ -d "$loc" ]]; then
            wf_dir="$loc"
            break
        fi
    done

    if [[ -z "$wf_dir" ]]; then
        log_error "workflow: directory not found in any expected location"
        return 2
    fi
    log_ok "workflow: directory found at ${wf_dir}"

    # 2. Check for key content files
    local has_content=false
    for marker in "README.md" "CLAUDE.md" "workflow.sh" "bloom-workflow.conf" ".bloom-marker"; do
        if [[ -f "${wf_dir}/${marker}" ]]; then
            has_content=true
            log_ok "workflow: found ${marker}"
            break
        fi
    done

    if [[ "$has_content" == "false" ]]; then
        issues+=("workflow directory exists but contains no expected content files")
        exit_code=2
    fi

    # 3. Git repo integrity (if applicable)
    if [[ -d "${wf_dir}/.git" ]]; then
        if git -C "$wf_dir" status &>/dev/null 2>&1; then
            local branch
            branch="$(git -C "$wf_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
            log_ok "workflow: git repo healthy (branch: ${branch})"
        else
            issues+=("workflow git repo is corrupt")
            [[ $exit_code -lt 2 ]] && exit_code=2
        fi
    fi

    # 4. CLAUDE.md linked or referenced from project?
    if [[ -f "${wf_dir}/CLAUDE.md" ]]; then
        # Just informational — not a failure
        log_info "workflow: CLAUDE.md present — ensure it is sourced in your project CLAUDE.md"
    fi

    for issue in "${issues[@]}"; do
        log_warn "workflow: ${issue}"
    done

    case $exit_code in
        0) log_ok "workflow: verification PASSED" ;;
        1) log_warn "workflow: verification PASSED with warnings" ;;
        2) log_error "workflow: verification FAILED" ;;
    esac

    return $exit_code
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bloom_verify_workflow
fi
