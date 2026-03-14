#!/usr/bin/env bash
# components/chub/install.sh
# Install/manage the chub (context-hub) component.
#
# MODE env var controls behavior:
#   install | reuse | wrap | replace | side-by-side | skip

set -euo pipefail

_CHUB_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BLOOM_ROOT_GUESS="$(cd "${_CHUB_INSTALL_DIR}/../.." && pwd)"

if ! declare -f log_info &>/dev/null; then
    source "${_BLOOM_ROOT_GUESS}/bootstrap/common.sh"
fi
if ! declare -f state_set &>/dev/null; then
    source "${_BLOOM_ROOT_GUESS}/bootstrap/state-store.sh"
fi

source "${_CHUB_INSTALL_DIR}/detect.sh"

CHUB_REPO_URL="${CHUB_REPO_URL:-https://github.com/vokov/context-hub-rpi}"
CHUB_INSTALL_DIR="${CHUB_INSTALL_DIR_OVERRIDE:-${HOME}/context-hub-rpi}"
CHUB_BIN_LINK="${HOME}/.local/bin/chub"
MODE="${MODE:-install}"

_chub_clone_or_update() {
    local dest="$1"
    local depth="${PROFILE_GIT_CLONE_DEPTH:-0}"
    local depth_flag=""
    [[ "$depth" -gt 0 ]] && depth_flag="--depth=${depth}"

    if [[ -d "${dest}/.git" ]]; then
        log_info "chub: repo exists at ${dest}, pulling"
        run_cmd git -C "$dest" pull --ff-only ${depth_flag}
    else
        log_info "chub: cloning ${CHUB_REPO_URL} → ${dest}"
        ensure_dir "$(dirname "$dest")"
        run_cmd git clone ${depth_flag} "$CHUB_REPO_URL" "$dest"
    fi
}

_chub_find_binary() {
    local dir="$1"
    for candidate in "${dir}/chub" "${dir}/bin/chub" "${dir}/chub.sh" "${dir}/chub.py"; do
        if [[ -f "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    find "$dir" -maxdepth 2 -name "chub*" -type f -executable 2>/dev/null | head -1 || true
}

_chub_setup_link() {
    local bin_path="$1"
    local link_name="${2:-chub}"
    local link_target="${HOME}/.local/bin/${link_name}"
    ensure_dir "${HOME}/.local/bin"

    [[ -L "$link_target" ]] && run_cmd rm "$link_target"
    if [[ -f "$link_target" && ! -L "$link_target" ]]; then
        backup_path "$link_target"
        run_cmd rm "$link_target"
    fi
    run_cmd ln -s "$bin_path" "$link_target"
    log_ok "chub: linked ${link_target} → ${bin_path}"
}

_chub_run_setup() {
    local dir="$1"
    if [[ -f "${dir}/setup.sh" ]]; then
        log_info "chub: running setup.sh"
        run_cmd bash "${dir}/setup.sh"
    elif [[ -f "${dir}/install.sh" ]]; then
        log_info "chub: running install.sh from repo"
        run_cmd bash "${dir}/install.sh" --no-interactive
    fi
}

# ---------------------------------------------------------------------------
# Mode: install
# ---------------------------------------------------------------------------
_mode_install() {
    log_step "chub: mode=install"
    bloom_detect_chub

    if [[ "$CHUB_STATUS" == "ours-healthy" ]]; then
        log_ok "chub: already installed and healthy at ${CHUB_PATH}"
        state_set_component_installed "chub" "${CHUB_VERSION:-unknown}" "install"
        return 0
    fi

    _chub_clone_or_update "$CHUB_INSTALL_DIR"
    _chub_run_setup "$CHUB_INSTALL_DIR"

    local bin
    bin="$(_chub_find_binary "$CHUB_INSTALL_DIR")"
    if [[ -z "$bin" ]]; then
        log_error "chub: cannot find binary after setup in ${CHUB_INSTALL_DIR}"
        return 2
    fi

    run_cmd chmod +x "$bin"
    _chub_setup_link "$bin" "chub"

    local ver
    ver="$("$bin" --version 2>/dev/null | head -1 || echo "unknown")"
    state_set_component_installed "chub" "$ver" "install"
    log_ok "chub: installed (${ver})"
}

# ---------------------------------------------------------------------------
# Mode: reuse
# ---------------------------------------------------------------------------
_mode_reuse() {
    log_step "chub: mode=reuse"
    bloom_detect_chub

    if [[ "$CHUB_STATUS" == "missing" ]]; then
        log_error "chub: reuse requested but not installed"
        return 1
    fi

    state_set_component_installed "chub" "${CHUB_VERSION:-unknown}" "reuse"
    log_ok "chub: reuse — registered ${CHUB_PATH}"
}

# ---------------------------------------------------------------------------
# Mode: wrap
# ---------------------------------------------------------------------------
_mode_wrap() {
    log_step "chub: mode=wrap"
    bloom_detect_chub

    if [[ "$CHUB_STATUS" == "missing" ]]; then
        log_warn "chub: wrap requested but not found — falling back to install"
        _mode_install; return $?
    fi

    if [[ "$CHUB_OUR_VERSION" == "true" ]]; then
        log_info "chub: already ours — using reuse"
        _mode_reuse; return $?
    fi

    local original_path="$CHUB_PATH"
    local wrapper="${HOME}/.local/bin/chub"
    ensure_dir "${HOME}/.local/bin"

    [[ -f "$wrapper" ]] && backup_path "$wrapper"

    cat > "$wrapper" <<WRAP
#!/usr/bin/env bash
# bloom-node-bootstrap: chub wrapper around ${original_path}
# BLOOM_WRAP=true
[[ -f "\${HOME}/.bloom-env" ]] && source "\${HOME}/.bloom-env"
exec "${original_path}" "\$@"
WRAP
    run_cmd chmod +x "$wrapper"
    state_set_component_installed "chub" "${CHUB_VERSION:-unknown}" "wrap"
    state_set "component.chub.original_path" "$original_path"
    log_ok "chub: wrapper installed at ${wrapper}"
}

# ---------------------------------------------------------------------------
# Mode: replace
# ---------------------------------------------------------------------------
_mode_replace() {
    log_step "chub: mode=replace"
    bloom_detect_chub

    if [[ "$CHUB_STATUS" != "missing" ]]; then
        if ! confirm "Replace existing chub at ${CHUB_PATH}?"; then
            log_info "chub: replace cancelled"
            return 1
        fi
        backup_path "$CHUB_PATH"
        [[ -n "${CHUB_REPO:-}" ]] && backup_path "$CHUB_REPO"
    fi

    _mode_install
}

# ---------------------------------------------------------------------------
# Mode: side-by-side
# ---------------------------------------------------------------------------
_mode_side_by_side() {
    log_step "chub: mode=side-by-side"
    local sbs_dir="${HOME}/context-hub-bloom"
    _chub_clone_or_update "$sbs_dir"
    _chub_run_setup "$sbs_dir"

    local bin
    bin="$(_chub_find_binary "$sbs_dir")"
    if [[ -z "$bin" ]]; then
        log_error "chub: no binary found in side-by-side dir ${sbs_dir}"
        return 2
    fi

    run_cmd chmod +x "$bin"
    _chub_setup_link "$bin" "chub-bloom"
    state_set_component_installed "chub" "side-by-side" "side-by-side"
    state_set "component.chub.sbs_path" "$sbs_dir"
    log_ok "chub: side-by-side install as 'chub-bloom' complete"
}

# ---------------------------------------------------------------------------
# Mode: skip
# ---------------------------------------------------------------------------
_mode_skip() {
    log_step "chub: mode=skip"
    state_set_skip "chub" "user-requested-skip"
    log_info "chub: skipped"
}

# ---------------------------------------------------------------------------
# bloom_install_chub
# ---------------------------------------------------------------------------
bloom_install_chub() {
    log_section "Installing component: chub"
    case "${MODE}" in
        install)      _mode_install ;;
        reuse)        _mode_reuse ;;
        wrap)         _mode_wrap ;;
        replace)      _mode_replace ;;
        side-by-side) _mode_side_by_side ;;
        skip)         _mode_skip ;;
        *) log_error "chub: unknown MODE='${MODE}'"; return 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bloom_install_chub
fi
