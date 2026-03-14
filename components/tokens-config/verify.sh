#!/usr/bin/env bash
# components/tokens-config/verify.sh
# Health check for tokens-config component.
# NEVER logs token values — only checks presence/format.
# Exit codes: 0=OK, 1=WARN, 2=FAIL

set -euo pipefail

_TC_VERIFY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BLOOM_ROOT_GUESS="$(cd "${_TC_VERIFY_DIR}/../.." && pwd)"

if ! declare -f log_info &>/dev/null; then
    source "${_BLOOM_ROOT_GUESS}/bootstrap/common.sh"
fi

bloom_verify_tokens_config() {
    log_section "Verifying component: tokens-config"

    local exit_code=0
    local issues=()

    # 1. ~/.claude directory
    if [[ ! -d "${HOME}/.claude" ]]; then
        issues+=("~/.claude directory missing")
        exit_code=2
    else
        log_ok "tokens-config: ~/.claude directory exists"
        # Check permissions
        local perms
        perms=$(stat -c "%a" "${HOME}/.claude" 2>/dev/null || stat -f "%A" "${HOME}/.claude" 2>/dev/null || echo "unknown")
        if [[ "$perms" != "700" && "$perms" != "unknown" ]]; then
            issues+=("~/.claude has permissions ${perms} — should be 700")
            [[ $exit_code -lt 1 ]] && exit_code=1
        else
            log_ok "tokens-config: ~/.claude permissions OK (${perms})"
        fi
    fi

    # 2. API key presence (don't log value)
    local has_key=false
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        has_key=true
        # Basic format check: should start with sk-ant-
        if [[ "${ANTHROPIC_API_KEY}" == sk-ant-* ]]; then
            log_ok "tokens-config: ANTHROPIC_API_KEY present (format looks valid)"
        else
            issues+=("ANTHROPIC_API_KEY present but format unexpected (expected sk-ant-...)")
            [[ $exit_code -lt 1 ]] && exit_code=1
        fi
    fi

    # Check env file
    local env_file="${HOME}/.claude/.env"
    if [[ -f "$env_file" ]]; then
        log_ok "tokens-config: ${env_file} exists"
        # Check permissions
        local env_perms
        env_perms=$(stat -c "%a" "$env_file" 2>/dev/null || stat -f "%A" "$env_file" 2>/dev/null || echo "unknown")
        if [[ "$env_perms" != "600" && "$env_perms" != "unknown" ]]; then
            issues+=("${env_file} has permissions ${env_perms} — should be 600")
            [[ $exit_code -lt 1 ]] && exit_code=1
        fi
        # Check if it has an API key (without reading it)
        if grep -q "^ANTHROPIC_API_KEY=sk-ant-" "$env_file" 2>/dev/null; then
            has_key=true
            log_ok "tokens-config: API key found in ${env_file}"
        elif grep -q "^ANTHROPIC_API_KEY=" "$env_file" 2>/dev/null; then
            issues+=("ANTHROPIC_API_KEY= line found but appears to be a placeholder")
            [[ $exit_code -lt 1 ]] && exit_code=1
        fi
    fi

    if [[ "$has_key" == "false" ]]; then
        issues+=("no ANTHROPIC_API_KEY found in environment or ${HOME}/.claude/.env")
        [[ $exit_code -lt 2 ]] && exit_code=2
    fi

    # 3. bloom-env loader
    if [[ -f "${HOME}/.bloom-env" ]]; then
        log_ok "tokens-config: bloom env loader present at ~/.bloom-env"
    else
        log_info "tokens-config: ~/.bloom-env not found (run install to create)"
    fi

    for issue in "${issues[@]}"; do
        log_warn "tokens-config: ${issue}"
    done

    case $exit_code in
        0) log_ok "tokens-config: verification PASSED" ;;
        1) log_warn "tokens-config: verification PASSED with warnings" ;;
        2) log_error "tokens-config: verification FAILED — API key required" ;;
    esac

    return $exit_code
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bloom_verify_tokens_config
fi
