#!/usr/bin/env bash
# components/tokens-config/install.sh
# Manage API token configuration.
# CRITICAL: This component NEVER stores or logs token values.
# It creates the scaffolding (dirs, template files) — the user fills in tokens.
#
# MODE: install | reuse | replace | skip
# (wrap/side-by-side collapse to reuse for tokens — we don't touch existing tokens)

set -euo pipefail

_TC_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BLOOM_ROOT_GUESS="$(cd "${_TC_INSTALL_DIR}/../.." && pwd)"

if ! declare -f log_info &>/dev/null; then
    source "${_BLOOM_ROOT_GUESS}/bootstrap/common.sh"
fi
if ! declare -f state_set &>/dev/null; then
    source "${_BLOOM_ROOT_GUESS}/bootstrap/state-store.sh"
fi
source "${_TC_INSTALL_DIR}/detect.sh"

MODE="${MODE:-reuse}"   # Default to reuse — never clobber tokens without asking

# ---------------------------------------------------------------------------
# _tc_create_scaffold
# Create the ~/.claude directory structure and template files.
# Does NOT write any token values.
# ---------------------------------------------------------------------------
_tc_create_scaffold() {
    ensure_dir "${HOME}/.claude"
    # Secure permissions on .claude directory
    run_cmd chmod 700 "${HOME}/.claude"

    # Create a .env template if no env file exists
    local env_file="${HOME}/.claude/.env"
    if [[ ! -f "$env_file" ]]; then
        log_info "tokens-config: creating token template at ${env_file}"
        cat > "$env_file" <<'ENVTEMPLATE'
# Claude Code / bloom-node-bootstrap token configuration
# Fill in your API key below. Keep this file private (chmod 600).
#
# Get your API key from: https://console.anthropic.com/
#
# ANTHROPIC_API_KEY=sk-ant-...
#
# Optional: override Claude model
# ANTHROPIC_MODEL=claude-sonnet-4-5
#
# Optional: bloom-specific settings
# BLOOM_LOG_LEVEL=info
# BLOOM_ASSUME_YES=false
ENVTEMPLATE
        run_cmd chmod 600 "$env_file"
        log_ok "tokens-config: template created at ${env_file}"
        log_warn "tokens-config: IMPORTANT — open ${env_file} and add your ANTHROPIC_API_KEY"
    else
        log_info "tokens-config: ${env_file} already exists — not overwriting"
    fi

    # Create bloom-specific env loader
    local bloom_env="${HOME}/.bloom-env"
    if [[ ! -f "$bloom_env" ]]; then
        cat > "$bloom_env" <<'BLOOMENV'
#!/usr/bin/env bash
# bloom-node-bootstrap environment loader
# Source this file to load bloom + claude configuration.
# Add to your ~/.bashrc: source ~/.bloom-env

# Load .claude/.env if it exists
if [[ -f "${HOME}/.claude/.env" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${HOME}/.claude/.env"
    set +a
fi

# Ensure ~/.local/bin is in PATH
if [[ ":${PATH}:" != *":${HOME}/.local/bin:"* ]]; then
    export PATH="${HOME}/.local/bin:${PATH}"
fi

# bloom settings
export BLOOM_ROOT="${BLOOM_ROOT:-${HOME}/bloom-node-bootstrap}"
BLOOMENV
        run_cmd chmod 600 "$bloom_env"
        log_ok "tokens-config: bloom env loader created at ${bloom_env}"
    fi

    # Write our marker
    cat > "${HOME}/.claude/bloom-tokens.conf" <<MARKER
# bloom-node-bootstrap tokens-config marker
# Created: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
BLOOM_TOKENS_SCAFFOLD=true
MARKER
    run_cmd chmod 600 "${HOME}/.claude/bloom-tokens.conf"
}

# ---------------------------------------------------------------------------
# _tc_check_shell_rc
# Suggest adding bloom-env to user's shell RC file.
# ---------------------------------------------------------------------------
_tc_check_shell_rc() {
    local shell_rc=""
    local shell_name
    shell_name="$(basename "${SHELL:-/bin/sh}")"

    case "$shell_name" in
        bash) shell_rc="${HOME}/.bashrc" ;;
        zsh)  shell_rc="${HOME}/.zshrc" ;;
        fish) shell_rc="${HOME}/.config/fish/config.fish" ;;
    esac

    if [[ -n "$shell_rc" && -f "$shell_rc" ]]; then
        if ! grep -q "bloom-env\|bloom-node-bootstrap" "$shell_rc" 2>/dev/null; then
            log_info "tokens-config: to auto-load config, add to ${shell_rc}:"
            log_info "  source \${HOME}/.bloom-env"
        else
            log_ok "tokens-config: bloom-env already referenced in ${shell_rc}"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------

_mode_install() {
    log_step "tokens-config: mode=install"
    bloom_detect_tokens_config

    if [[ "$TOKENS_CONFIG_STATUS" == "ours-healthy" ]]; then
        log_ok "tokens-config: already configured"
        state_set_component_installed "tokens-config" "configured" "install"
        return 0
    fi

    if [[ "$TOKENS_CONFIG_HAS_API_KEY" == "true" ]] || [[ "$TOKENS_CONFIG_HAS_ENV_FILE" == "true" ]]; then
        log_ok "tokens-config: existing tokens found — creating bloom scaffold only"
        _tc_create_scaffold
        _tc_check_shell_rc
        state_set_component_installed "tokens-config" "scaffold" "install"
        return 0
    fi

    # No tokens at all — create scaffold and guide user
    _tc_create_scaffold
    _tc_check_shell_rc

    log_warn "tokens-config: no API key detected"
    log_warn "tokens-config: add your ANTHROPIC_API_KEY to ${HOME}/.claude/.env"
    state_set_component_installed "tokens-config" "scaffold-pending-key" "install"
}

_mode_reuse() {
    log_step "tokens-config: mode=reuse"
    bloom_detect_tokens_config

    if [[ "$TOKENS_CONFIG_HAS_API_KEY" == "false" && "$TOKENS_CONFIG_HAS_ENV_FILE" == "false" ]]; then
        log_warn "tokens-config: reuse requested but no tokens found"
        log_warn "tokens-config: set ANTHROPIC_API_KEY in environment or ${HOME}/.claude/.env"
        state_set "component.tokens-config.status" "missing"
        return 0  # Not an error — user may set it later
    fi

    state_set_component_installed "tokens-config" "reuse" "reuse"
    log_ok "tokens-config: existing token config registered"
}

_mode_replace() {
    log_step "tokens-config: mode=replace"
    bloom_detect_tokens_config

    if [[ "$TOKENS_CONFIG_HAS_ENV_FILE" == "true" ]]; then
        if ! confirm "Overwrite existing token config at ${TOKENS_CONFIG_PATH}? (values will be backed up)"; then
            log_info "tokens-config: replace cancelled — protecting existing tokens"
            return 1
        fi
        backup_path "$TOKENS_CONFIG_PATH"
    fi

    _mode_install
}

_mode_skip() {
    log_step "tokens-config: mode=skip"
    state_set_skip "tokens-config" "user-requested-skip"
    log_info "tokens-config: skipped — ensure ANTHROPIC_API_KEY is set before using Claude"
}

bloom_install_tokens_config() {
    log_section "Installing component: tokens-config"
    case "${MODE}" in
        install)      _mode_install ;;
        reuse)        _mode_reuse ;;
        wrap)         _mode_reuse ;;          # wrap = reuse for tokens
        replace)      _mode_replace ;;
        side-by-side) _mode_install ;;        # same as install for tokens
        skip)         _mode_skip ;;
        *) log_error "tokens-config: unknown MODE='${MODE}'"; return 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bloom_install_tokens_config
fi
