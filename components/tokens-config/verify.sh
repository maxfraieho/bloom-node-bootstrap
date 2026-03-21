#!/usr/bin/env bash
# components/tokens-config/verify.sh
# Health check for tokens-config component.
# NEVER logs token values — only checks presence/format.
# Exit codes: 0=OK, 1=WARN, 2=FAIL
#
# PASS if any ONE of:
#   1. Claude Code login session active  (claude auth status loggedIn=true)
#   2. ANTHROPIC_API_KEY in environment
#   3. ANTHROPIC_API_KEY in config file
#   4. Third-party provider key present (OPENAI, GEMINI, OPENROUTER)
#
# FAIL only when none of the above.

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
    local auth_method="none"
    local is_authenticated=false

    # 1. ~/.claude directory
    if [[ ! -d "${HOME}/.claude" ]]; then
        issues+=("~/.claude directory missing")
        exit_code=2
    else
        log_ok "tokens-config: ~/.claude directory exists"
        local perms
        perms=$(stat -c "%a" "${HOME}/.claude" 2>/dev/null || stat -f "%A" "${HOME}/.claude" 2>/dev/null || echo "unknown")
        if [[ "$perms" != "700" && "$perms" != "unknown" ]]; then
            issues+=("~/.claude has permissions ${perms} — should be 700")
            [[ $exit_code -lt 1 ]] && exit_code=1
        else
            log_ok "tokens-config: ~/.claude permissions OK (${perms})"
        fi
    fi

    # 2. Auth method 1: Claude Code login session
    if command -v claude &>/dev/null; then
        local auth_json
        auth_json="$(claude auth status 2>/dev/null || echo '{}')"
        if echo "$auth_json" | grep -q '"loggedIn": *true'; then
            is_authenticated=true
            local method_raw
            method_raw="$(echo "$auth_json" | grep '"authMethod"' | \
                sed 's/.*"authMethod": *"\([^"]*\)".*/\1/' 2>/dev/null || echo 'claude-login')"
            auth_method="${method_raw:-claude-login}"
            log_ok "tokens-config: Claude login session active (${auth_method})"
        fi
    fi

    # 3. Auth method 2: ANTHROPIC_API_KEY in environment
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        is_authenticated=true
        [[ "$auth_method" == "none" ]] && auth_method="api-key-env"
        if [[ "${ANTHROPIC_API_KEY}" == sk-ant-* ]]; then
            log_ok "tokens-config: ANTHROPIC_API_KEY present in env (format valid)"
        else
            issues+=("ANTHROPIC_API_KEY present but format unexpected (expected sk-ant-...)")
            [[ $exit_code -lt 1 ]] && exit_code=1
        fi
    fi

    # 4. Auth method 3: ANTHROPIC_API_KEY in config file
    local env_file="${HOME}/.claude/.env"
    if [[ -f "$env_file" ]]; then
        log_ok "tokens-config: ${env_file} exists"
        local env_perms
        env_perms=$(stat -c "%a" "$env_file" 2>/dev/null || stat -f "%A" "$env_file" 2>/dev/null || echo "unknown")
        if [[ "$env_perms" != "600" && "$env_perms" != "unknown" ]]; then
            issues+=("${env_file} has permissions ${env_perms} — should be 600")
            [[ $exit_code -lt 1 ]] && exit_code=1
        fi
        if grep -q "^ANTHROPIC_API_KEY=sk-ant-" "$env_file" 2>/dev/null; then
            is_authenticated=true
            [[ "$auth_method" == "none" ]] && auth_method="api-key-file"
            log_ok "tokens-config: API key found in ${env_file}"
        elif grep -q "^ANTHROPIC_API_KEY=" "$env_file" 2>/dev/null; then
            issues+=("ANTHROPIC_API_KEY= line in ${env_file} appears to be a placeholder")
            [[ $exit_code -lt 1 ]] && exit_code=1
        fi
    fi

    # Also check other known config locations
    local extra_locations=(
        "${HOME}/.claude/tokens"
        "${HOME}/.claude/config.json"
        "${HOME}/.config/claude/config.json"
        "${HOME}/.env"
        "${HOME}/.config/anthropic/api_key"
    )
    for loc in "${extra_locations[@]}"; do
        if [[ -f "$loc" ]] && grep -qi "anthropic\|api.key\|ANTHROPIC" "$loc" 2>/dev/null; then
            is_authenticated=true
            [[ "$auth_method" == "none" ]] && auth_method="api-key-file"
            log_ok "tokens-config: token config found at ${loc}"
            break
        fi
    done

    # 5. Auth method 4: Third-party provider
    if [[ -n "${OPENAI_API_KEY:-}" ]] || [[ -n "${GEMINI_API_KEY:-}" ]] || \
       [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
        is_authenticated=true
        [[ "$auth_method" == "none" ]] && auth_method="third-party-provider"
        log_ok "tokens-config: third-party provider key present"
    fi

    # FAIL only if no auth method found
    if [[ "$is_authenticated" == "false" ]]; then
        issues+=("no auth method found: need Claude login, ANTHROPIC_API_KEY, or third-party provider key")
        [[ $exit_code -lt 2 ]] && exit_code=2
    else
        log_ok "tokens-config: authenticated via ${auth_method}"
    fi

    # 6. bloom-env loader (informational only)
    if [[ -f "${HOME}/.bloom-env" ]]; then
        log_ok "tokens-config: bloom env loader present at ~/.bloom-env"
    else
        log_info "tokens-config: ~/.bloom-env not found (optional)"
    fi

    for issue in "${issues[@]}"; do
        log_warn "tokens-config: ${issue}"
    done

    case $exit_code in
        0) log_ok "tokens-config: verification PASSED (auth=${auth_method})" ;;
        1) log_warn "tokens-config: verification PASSED with warnings (auth=${auth_method})" ;;
        2) log_error "tokens-config: verification FAILED — no auth method available" ;;
    esac

    return $exit_code
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bloom_verify_tokens_config
fi
