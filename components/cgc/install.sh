#!/usr/bin/env bash
# components/cgc/install.sh
# Install/manage the cgc component.
#
# Reads MODE env var (default: install). Modes:
#   install      — fresh clone + setup (default)
#   reuse        — verify existing, register in state, done
#   wrap         — add our shim wrapper around foreign cgc
#   replace      — backup existing, install ours
#   side-by-side — install as cgc-bloom alongside existing
#   skip         — record skip decision, return

set -euo pipefail

_CGC_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BLOOM_ROOT_GUESS="$(cd "${_CGC_INSTALL_DIR}/../.." && pwd)"

if ! declare -f log_info &>/dev/null; then
    # shellcheck source=bootstrap/common.sh
    source "${_BLOOM_ROOT_GUESS}/bootstrap/common.sh"
fi
if ! declare -f state_set &>/dev/null; then
    # shellcheck source=bootstrap/state-store.sh
    source "${_BLOOM_ROOT_GUESS}/bootstrap/state-store.sh"
fi

# Source detect to know current state
# shellcheck source=components/cgc/detect.sh
source "${_CGC_INSTALL_DIR}/detect.sh"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
CGC_REPO_URL="${CGC_REPO_URL:-https://github.com/vokov/cgc-rpi}"
CGC_INSTALL_DIR="${CGC_INSTALL_DIR_OVERRIDE:-${HOME}/cgc-rpi}"
CGC_BIN_LINK="${HOME}/.local/bin/cgc"
CGC_SIDE_BY_SIDE_NAME="cgc-bloom"
MODE="${MODE:-install}"

# ---------------------------------------------------------------------------
# _cgc_clone_or_update
# Clone repo if missing; pull if present. Respects PROFILE_GIT_CLONE_DEPTH.
# ---------------------------------------------------------------------------
_cgc_clone_or_update() {
    local dest="$1"
    local depth="${PROFILE_GIT_CLONE_DEPTH:-0}"
    local depth_flag=""
    [[ "$depth" -gt 0 ]] && depth_flag="--depth=${depth}"

    if [[ -d "${dest}/.git" ]]; then
        log_info "cgc: repo exists at ${dest}, pulling latest"
        run_cmd git -C "$dest" pull --ff-only ${depth_flag}
    else
        log_info "cgc: cloning ${CGC_REPO_URL} → ${dest}"
        ensure_dir "$(dirname "$dest")"
        run_cmd git clone ${depth_flag} "$CGC_REPO_URL" "$dest"
    fi
}

# ---------------------------------------------------------------------------
# _cgc_setup_link BIN_PATH LINK_NAME
# Create ~/.local/bin symlink to the cgc binary.
# ---------------------------------------------------------------------------
_cgc_setup_link() {
    local bin_path="$1"
    local link_name="${2:-cgc}"
    local link_target="${HOME}/.local/bin/${link_name}"

    ensure_dir "${HOME}/.local/bin"

    if [[ -L "$link_target" ]]; then
        log_info "cgc: removing existing symlink ${link_target}"
        run_cmd rm "$link_target"
    elif [[ -f "$link_target" ]]; then
        backup_path "$link_target"
        run_cmd rm "$link_target"
    fi

    log_info "cgc: creating symlink ${link_target} → ${bin_path}"
    run_cmd ln -s "$bin_path" "$link_target"
}

# ---------------------------------------------------------------------------
# _cgc_find_binary DIR
# Find the main cgc executable inside the cloned repo.
# ---------------------------------------------------------------------------
_cgc_find_binary() {
    local dir="$1"
    for candidate in "${dir}/cgc" "${dir}/bin/cgc" "${dir}/cgc.sh"; do
        if [[ -f "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    # Try any executable with cgc in name at top level
    find "$dir" -maxdepth 2 -name "cgc*" -type f -executable 2>/dev/null | head -1
}

# ---------------------------------------------------------------------------
# _cgc_create_wrapper EXISTING_PATH
# Create a thin wrapper script that adds our environment before calling original.
# ---------------------------------------------------------------------------
_cgc_create_wrapper() {
    local original="$1"
    local wrapper="${HOME}/.local/bin/cgc"

    log_info "cgc: creating wrapper at ${wrapper} around ${original}"
    ensure_dir "${HOME}/.local/bin"

    if [[ -f "$wrapper" ]]; then
        backup_path "$wrapper"
    fi

    cat > "$wrapper" <<WRAPPER_EOF
#!/usr/bin/env bash
# bloom-node-bootstrap: cgc wrapper
# Wraps the original cgc at: ${original}
# Created: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
# BLOOM_WRAP=true

# Source bloom environment if available
if [[ -f "\${HOME}/.bloom-env" ]]; then
    # shellcheck disable=SC1090
    source "\${HOME}/.bloom-env"
fi

exec "${original}" "\$@"
WRAPPER_EOF
    run_cmd chmod +x "$wrapper"
    log_ok "cgc: wrapper installed at ${wrapper}"
}

# ---------------------------------------------------------------------------
# Mode implementations
# ---------------------------------------------------------------------------

_mode_install() {
    log_step "cgc: mode=install"
    bloom_detect_cgc

    if [[ "$CGC_STATUS" == "ours-healthy" ]]; then
        log_ok "cgc: already installed and healthy at ${CGC_PATH}"
        state_set_component_installed "cgc" "${CGC_VERSION:-unknown}" "install"
        return 0
    fi

    _cgc_clone_or_update "$CGC_INSTALL_DIR"

    local bin
    bin="$(_cgc_find_binary "$CGC_INSTALL_DIR")"

    if [[ -z "$bin" ]]; then
        # No pre-built binary found — try setup script
        if [[ -f "${CGC_INSTALL_DIR}/setup.sh" ]]; then
            log_info "cgc: running setup.sh"
            run_cmd bash "${CGC_INSTALL_DIR}/setup.sh"
            bin="$(_cgc_find_binary "$CGC_INSTALL_DIR")"
        fi
    fi

    if [[ -z "$bin" ]]; then
        # Final fallback: create minimal cgc wrapper for Python-based cgc
        if [[ -f "${CGC_INSTALL_DIR}/cgc.py" ]]; then
            local py_bin
            py_bin="$(command -v python3 || command -v python || echo python3)"
            cat > "${CGC_INSTALL_DIR}/cgc" <<PYWRAP
#!/usr/bin/env bash
exec "${py_bin}" "${CGC_INSTALL_DIR}/cgc.py" "\$@"
PYWRAP
            run_cmd chmod +x "${CGC_INSTALL_DIR}/cgc"
            bin="${CGC_INSTALL_DIR}/cgc"
        else
            log_error "cgc: cannot find or create cgc binary in ${CGC_INSTALL_DIR}"
            return 2
        fi
    fi

    run_cmd chmod +x "$bin"
    _cgc_setup_link "$bin" "cgc"

    local ver
    ver="$("$bin" --version 2>/dev/null | head -1 || echo "unknown")"
    state_set_component_installed "cgc" "$ver" "install"
    log_ok "cgc: installed (version: ${ver})"
}

_mode_reuse() {
    log_step "cgc: mode=reuse"
    bloom_detect_cgc

    if [[ "$CGC_STATUS" == "missing" ]]; then
        log_error "cgc: reuse requested but cgc is not installed"
        return 1
    fi

    log_ok "cgc: reuse — registering existing install at ${CGC_PATH}"
    state_set_component_installed "cgc" "${CGC_VERSION:-unknown}" "reuse"
    log_info "cgc: status=${CGC_STATUS}, version=${CGC_VERSION:-unknown}"
}

_mode_wrap() {
    log_step "cgc: mode=wrap"
    bloom_detect_cgc

    if [[ "$CGC_STATUS" == "missing" ]]; then
        log_warn "cgc: wrap requested but no cgc found — falling back to install"
        _mode_install
        return $?
    fi

    if [[ "$CGC_OUR_VERSION" == "true" ]]; then
        log_info "cgc: already our version — wrap not needed, using reuse"
        _mode_reuse
        return $?
    fi

    _cgc_create_wrapper "$CGC_PATH"
    state_set_component_installed "cgc" "${CGC_VERSION:-unknown}" "wrap"
    state_set "component.cgc.original_path" "$CGC_PATH"
}

_mode_replace() {
    log_step "cgc: mode=replace"
    bloom_detect_cgc

    if [[ "$CGC_STATUS" != "missing" ]]; then
        log_warn "cgc: existing install found at ${CGC_PATH} — backing up"
        if ! confirm "Replace existing cgc at ${CGC_PATH}?"; then
            log_info "cgc: replace cancelled by user"
            return 1
        fi
        backup_path "$CGC_PATH"
        if [[ -n "${CGC_REPO:-}" ]]; then
            backup_path "$CGC_REPO"
        fi
    fi

    _mode_install
}

_mode_side_by_side() {
    log_step "cgc: mode=side-by-side"
    _cgc_clone_or_update "${HOME}/${CGC_SIDE_BY_SIDE_NAME}"

    local bin
    bin="$(_cgc_find_binary "${HOME}/${CGC_SIDE_BY_SIDE_NAME}")"
    if [[ -z "$bin" ]]; then
        log_error "cgc: could not find binary for side-by-side install"
        return 2
    fi

    run_cmd chmod +x "$bin"
    _cgc_setup_link "$bin" "$CGC_SIDE_BY_SIDE_NAME"

    state_set_component_installed "cgc" "side-by-side" "side-by-side"
    state_set "component.cgc.sbs_path" "${HOME}/${CGC_SIDE_BY_SIDE_NAME}"
    log_ok "cgc: side-by-side install as '${CGC_SIDE_BY_SIDE_NAME}' complete"
}

_mode_skip() {
    log_step "cgc: mode=skip"
    state_set_skip "cgc" "user-requested-skip"
    log_info "cgc: skipped"
}

# ---------------------------------------------------------------------------
# bloom_install_cgc — main entry point
# ---------------------------------------------------------------------------
bloom_install_cgc() {
    log_section "Installing component: cgc"

    case "${MODE}" in
        install)      _mode_install ;;
        reuse)        _mode_reuse ;;
        wrap)         _mode_wrap ;;
        replace)      _mode_replace ;;
        side-by-side) _mode_side_by_side ;;
        skip)         _mode_skip ;;
        *)
            log_error "cgc: unknown MODE='${MODE}'"
            log_error "Valid modes: install reuse wrap replace side-by-side skip"
            return 1
            ;;
    esac
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bloom_install_cgc
fi
