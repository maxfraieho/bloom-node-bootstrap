#!/usr/bin/env bash
# components/tokens-config/detect.sh
# Detection for API tokens and configuration state.
# Does NOT print or log token values — only presence.
#
# COMPONENT_STATUS: missing | ours-healthy | foreign | partial
#
# Auth methods checked (any one = PASS):
#   1. Claude Code login session  (claude auth status loggedIn=true)
#   2. ANTHROPIC_API_KEY in environment
#   3. API key in known config file
#   4. Third-party provider key (OPENAI, GEMINI, OPENROUTER)

set -euo pipefail

_TC_DETECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BLOOM_ROOT_GUESS="$(cd "${_TC_DETECT_DIR}/../.." && pwd)"

if ! declare -f log_debug &>/dev/null; then
    source "${_BLOOM_ROOT_GUESS}/bootstrap/common.sh"
fi

bloom_detect_tokens_config() {
    log_debug "tokens-config/detect: starting"

    local has_api_key=false
    local has_env_file=false
    local has_claude_login=false
    local has_third_party=false
    local has_claude_config=false
    local config_path=""
    local our_config=false
    local auth_method="none"

    # 1. Claude Code login session (highest priority — no API key needed)
    if command -v claude &>/dev/null; then
        local auth_json
        auth_json="$(claude auth status 2>/dev/null || echo '{}')"
        if echo "$auth_json" | grep -q '"loggedIn": *true'; then
            has_claude_login=true
            auth_method="$(echo "$auth_json" | grep '"authMethod"' | \
                sed 's/.*"authMethod": *"\([^"]*\)".*/\1/' 2>/dev/null || echo 'claude-login')"
            log_debug "tokens-config/detect: Claude login session active (${auth_method})"
        fi
    fi

    # 2. ANTHROPIC_API_KEY in environment
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        has_api_key=true
        [[ "$auth_method" == "none" ]] && auth_method="api-key-env"
        log_debug "tokens-config/detect: ANTHROPIC_API_KEY found in environment"
    fi

    # 3. Known config file locations (presence check only, no value logging)
    local config_locations=(
        "${HOME}/.claude/tokens"
        "${HOME}/.claude/.env"
        "${HOME}/.claude/config.json"
        "${HOME}/.config/claude/config.json"
        "${HOME}/.env"
        "${HOME}/.config/anthropic/api_key"
    )
    for loc in "${config_locations[@]}"; do
        if [[ -f "$loc" ]] && grep -qi "anthropic\|api.key\|ANTHROPIC" "$loc" 2>/dev/null; then
            has_env_file=true
            config_path="$loc"
            [[ "$auth_method" == "none" ]] && auth_method="api-key-file"
            log_debug "tokens-config/detect: token config found at ${loc}"
            break
        fi
    done

    # 4. Third-party provider (presence only, no values)
    if [[ -n "${OPENAI_API_KEY:-}" ]] || [[ -n "${GEMINI_API_KEY:-}" ]] || \
       [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
        has_third_party=true
        [[ "$auth_method" == "none" ]] && auth_method="third-party-provider"
        log_debug "tokens-config/detect: third-party provider key found"
    fi

    # 5. ~/.claude directory presence
    [[ -d "${HOME}/.claude" ]] && has_claude_config=true

    # Bloom config marker
    if [[ -f "${HOME}/.claude/bloom-tokens.conf" ]] || [[ -f "${HOME}/.bloom-env" ]]; then
        our_config=true
    fi

    # PASS if ANY valid auth method present
    local is_authenticated=false
    [[ "$has_claude_login" == "true" ]] && is_authenticated=true
    [[ "$has_api_key" == "true" ]]      && is_authenticated=true
    [[ "$has_env_file" == "true" ]]     && is_authenticated=true
    [[ "$has_third_party" == "true" ]]  && is_authenticated=true

    if [[ "$is_authenticated" == "true" ]]; then
        TOKENS_CONFIG_STATUS="$( [[ "$our_config" == "true" ]] && echo "ours-healthy" || echo "foreign" )"
        TOKENS_CONFIG_HEALTHY=true
    elif [[ "$has_claude_config" == "true" ]]; then
        TOKENS_CONFIG_STATUS="partial"
        TOKENS_CONFIG_HEALTHY=false
    else
        TOKENS_CONFIG_STATUS="missing"
        TOKENS_CONFIG_HEALTHY=false
    fi

    TOKENS_CONFIG_HAS_API_KEY="$has_api_key"
    TOKENS_CONFIG_HAS_ENV_FILE="$has_env_file"
    TOKENS_CONFIG_HAS_CLAUDE_LOGIN="$has_claude_login"
    TOKENS_CONFIG_HAS_THIRD_PARTY="$has_third_party"
    TOKENS_CONFIG_HAS_CLAUDE_DIR="$has_claude_config"
    TOKENS_CONFIG_PATH="${config_path:-}"
    TOKENS_CONFIG_OUR_VERSION="$our_config"
    TOKENS_CONFIG_AUTH_METHOD="$auth_method"

    _tc_export_and_print
}

_tc_export_and_print() {
    export TOKENS_CONFIG_STATUS TOKENS_CONFIG_HEALTHY TOKENS_CONFIG_HAS_API_KEY \
           TOKENS_CONFIG_HAS_ENV_FILE TOKENS_CONFIG_HAS_CLAUDE_LOGIN \
           TOKENS_CONFIG_HAS_THIRD_PARTY TOKENS_CONFIG_HAS_CLAUDE_DIR \
           TOKENS_CONFIG_PATH TOKENS_CONFIG_OUR_VERSION TOKENS_CONFIG_AUTH_METHOD

    log_debug "tokens-config/detect: STATUS=${TOKENS_CONFIG_STATUS} AUTH=${TOKENS_CONFIG_AUTH_METHOD}"
    # Note: never print actual token values
    printf 'TOKENS_CONFIG_STATUS=%s\nTOKENS_CONFIG_HAS_API_KEY=%s\nTOKENS_CONFIG_HAS_ENV_FILE=%s\nTOKENS_CONFIG_HAS_CLAUDE_LOGIN=%s\nTOKENS_CONFIG_HAS_THIRD_PARTY=%s\nTOKENS_CONFIG_HAS_CLAUDE_DIR=%s\nTOKENS_CONFIG_PATH=%s\nTOKENS_CONFIG_OUR_VERSION=%s\nTOKENS_CONFIG_HEALTHY=%s\nTOKENS_CONFIG_AUTH_METHOD=%s\n' \
        "$TOKENS_CONFIG_STATUS" "$TOKENS_CONFIG_HAS_API_KEY" "$TOKENS_CONFIG_HAS_ENV_FILE" \
        "$TOKENS_CONFIG_HAS_CLAUDE_LOGIN" "$TOKENS_CONFIG_HAS_THIRD_PARTY" \
        "$TOKENS_CONFIG_HAS_CLAUDE_DIR" "${TOKENS_CONFIG_PATH:-}" \
        "$TOKENS_CONFIG_OUR_VERSION" "$TOKENS_CONFIG_HEALTHY" "$TOKENS_CONFIG_AUTH_METHOD"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bloom_detect_tokens_config
fi
