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
    for loc in "${HOME}/.bloom/sources/claude-codex-workflow" \
               "${HOME}/.claude/workflow" \
               "${HOME}/claude-codex-workflow" \
               "${HOME}/.local/share/bloom/workflow" \
               "${HOME}/.claude/workflow-bloom"; do
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

    # 5. Check skills/manifest.json (ctx routing)
    local manifest_found=false
    if [[ -f "${wf_dir}/skills/manifest.json" ]]; then
        manifest_found=true
        log_ok "workflow: skills/manifest.json found"
    fi
    if [[ "$manifest_found" == "false" ]]; then
        issues+=("skills/manifest.json not found — ctx profile-aware routing will fall back to embedded list")
        [[ $exit_code -lt 1 ]] && exit_code=1
    fi

    # 6. Check ctx binary is installed and functional
    local ctx_bin=""
    if command -v ctx &>/dev/null; then
        ctx_bin="$(command -v ctx)"
    elif [[ -f "${HOME}/.local/bin/ctx" ]]; then
        ctx_bin="${HOME}/.local/bin/ctx"
    fi

    if [[ -n "$ctx_bin" ]]; then
        # Verify ctx doctor exits without error
        if python3 "$ctx_bin" doctor &>/dev/null 2>&1; then
            log_ok "workflow: ctx installed and healthy (${ctx_bin})"
        else
            # ctx doctor may exit 1 for PARTIAL (chub/cgc missing) — check for BROKEN
            local doctor_out
            doctor_out=$(python3 "$ctx_bin" doctor 2>&1 || true)
            if echo "$doctor_out" | grep -q "BROKEN"; then
                issues+=("ctx doctor reports BROKEN environment")
                [[ $exit_code -lt 1 ]] && exit_code=1
            else
                log_ok "workflow: ctx installed at ${ctx_bin} (partial env, non-fatal)"
            fi
        fi
    else
        issues+=("ctx not found — run workflow install to deploy bin/ctx to ~/.local/bin/ctx")
        issues+=("  and ensure ~/.local/bin is in PATH")
        [[ $exit_code -lt 1 ]] && exit_code=1
    fi

    # 7. Check CTX_PROFILE env file
    local bloom_env="${HOME}/.bloom/env.sh"
    if [[ -f "$bloom_env" ]] && grep -q "CTX_PROFILE" "$bloom_env" 2>/dev/null; then
        local ctx_profile
        ctx_profile="$(grep "^export CTX_PROFILE=" "$bloom_env" | cut -d= -f2 | tr -d '"'"'" 2>/dev/null || echo "unknown")"
        log_ok "workflow: CTX_PROFILE=${ctx_profile} set in ${bloom_env}"
    else
        log_info "workflow: CTX_PROFILE not set in ~/.bloom/env.sh — will use 'default' profile"
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
