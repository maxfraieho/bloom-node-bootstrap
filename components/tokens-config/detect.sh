#!/usr/bin/env bash
# components/tokens-config/detect.sh
# Detection for API tokens and configuration state.
# Does NOT print or log token values — only presence.
#
# COMPONENT_STATUS: missing | ours-healthy | foreign | partial

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
    local has_claude_config=false
    local config_path=""
    local our_config=false

    # Check for ANTHROPIC_API_KEY in environment
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        has_api_key=true
        log_debug "tokens-config/detect: ANTHROPIC_API_KEY found in environment"
    fi

    # Check known config file locations (do NOT read values, just check existence)
    local config_locations=(
        "${HOME}/.claude/tokens"
        "${HOME}/.claude/.env"
        "${HOME}/.claude/config.json"
        "${HOME}/.config/claude/config.json"
        "${HOME}/.env"
        "${HOME}/.config/anthropic/api_key"
    )

    for loc in "${config_locations[@]}"; do
        if [[ -f "$loc" ]]; then
            # Check if it contains an API key reference (not the value)
            if grep -qi "anthropic\|api.key\|ANTHROPIC" "$loc" 2>/dev/null; then
                has_env_file=true
                config_path="$loc"
                log_debug "tokens-config/detect: token config found at ${loc}"
                break
            fi
        fi
    done

    # Check for ~/.claude directory (Claude Code config home)
    if [[ -d "${HOME}/.claude" ]]; then
        has_claude_config=true
    fi

    # Check if our bloom config is present
    if [[ -f "${HOME}/.claude/bloom-tokens.conf" ]] || \
       [[ -f "${HOME}/.bloom-env" ]]; then
        our_config=true
    fi

    # Determine status
    if [[ "$has_api_key" == "true" || "$has_env_file" == "true" ]]; then
        if [[ "$our_config" == "true" ]]; then
            TOKENS_CONFIG_STATUS="ours-healthy"
        else
            TOKENS_CONFIG_STATUS="foreign"
        fi
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
    TOKENS_CONFIG_HAS_CLAUDE_DIR="$has_claude_config"
    TOKENS_CONFIG_PATH="${config_path:-}"
    TOKENS_CONFIG_OUR_VERSION="$our_config"

    _tc_export_and_print
}

_tc_export_and_print() {
    export TOKENS_CONFIG_STATUS TOKENS_CONFIG_HEALTHY TOKENS_CONFIG_HAS_API_KEY \
           TOKENS_CONFIG_HAS_ENV_FILE TOKENS_CONFIG_HAS_CLAUDE_DIR \
           TOKENS_CONFIG_PATH TOKENS_CONFIG_OUR_VERSION

    log_debug "tokens-config/detect: STATUS=${TOKENS_CONFIG_STATUS} HAS_KEY=${TOKENS_CONFIG_HAS_API_KEY}"
    # Note: never print actual token values
    printf 'TOKENS_CONFIG_STATUS=%s\nTOKENS_CONFIG_HAS_API_KEY=%s\nTOKENS_CONFIG_HAS_ENV_FILE=%s\nTOKENS_CONFIG_HAS_CLAUDE_DIR=%s\nTOKENS_CONFIG_PATH=%s\nTOKENS_CONFIG_OUR_VERSION=%s\nTOKENS_CONFIG_HEALTHY=%s\n' \
        "$TOKENS_CONFIG_STATUS" "$TOKENS_CONFIG_HAS_API_KEY" "$TOKENS_CONFIG_HAS_ENV_FILE" \
        "$TOKENS_CONFIG_HAS_CLAUDE_DIR" "${TOKENS_CONFIG_PATH:-}" \
        "$TOKENS_CONFIG_OUR_VERSION" "$TOKENS_CONFIG_HEALTHY"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bloom_detect_tokens_config
fi
