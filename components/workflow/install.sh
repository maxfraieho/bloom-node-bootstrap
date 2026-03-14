#!/usr/bin/env bash
# components/workflow/install.sh
# Install/manage the claude-codex-workflow component.
# MODE: install | reuse | wrap | replace | side-by-side | skip

set -euo pipefail

_WF_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BLOOM_ROOT_GUESS="$(cd "${_WF_INSTALL_DIR}/../.." && pwd)"

if ! declare -f log_info &>/dev/null; then
    source "${_BLOOM_ROOT_GUESS}/bootstrap/common.sh"
fi
if ! declare -f state_set &>/dev/null; then
    source "${_BLOOM_ROOT_GUESS}/bootstrap/state-store.sh"
fi
source "${_WF_INSTALL_DIR}/detect.sh"

WORKFLOW_REPO_URL="${WORKFLOW_REPO_URL:-https://github.com/maxfraieho/claude-codex-workflow}"
WORKFLOW_INSTALL_PATH="${WORKFLOW_INSTALL_PATH:-${HOME}/.bloom/sources/claude-codex-workflow}"
MODE="${MODE:-install}"

_wf_clone_or_update() {
    local dest="$1"
    local depth="${PROFILE_GIT_CLONE_DEPTH:-0}"
    local depth_flag=""
    [[ "$depth" -gt 0 ]] && depth_flag="--depth=${depth}"

    if [[ -d "${dest}/.git" ]]; then
        log_info "workflow: repo exists at ${dest}, pulling"
        run_cmd git -C "$dest" pull --ff-only ${depth_flag}
    else
        log_info "workflow: cloning ${WORKFLOW_REPO_URL} → ${dest}"
        ensure_dir "$(dirname "$dest")"
        run_cmd git clone ${depth_flag} "$WORKFLOW_REPO_URL" "$dest"
    fi
    # Place bloom marker
    touch "${dest}/.bloom-marker"
}

_wf_run_post_install() {
    local dir="$1"
    # Run any post-install script if present
    if [[ -f "${dir}/post-install.sh" ]]; then
        log_info "workflow: running post-install.sh"
        run_cmd bash "${dir}/post-install.sh"
    fi

    # Install bin/ctx to ~/.local/bin/ctx
    if [[ -f "${dir}/bin/ctx" ]]; then
        ensure_dir "${HOME}/.local/bin"
        run_cmd cp "${dir}/bin/ctx" "${HOME}/.local/bin/ctx"
        run_cmd chmod +x "${HOME}/.local/bin/ctx"
        log_ok "workflow: installed ctx → ${HOME}/.local/bin/ctx"
    fi

    # Install skill.md to ~/.claude/skills/claude-codex-workflow.md
    if [[ -f "${dir}/skill.md" ]]; then
        ensure_dir "${HOME}/.claude/skills"
        run_cmd cp "${dir}/skill.md" "${HOME}/.claude/skills/claude-codex-workflow.md"
        log_ok "workflow: installed skill → ${HOME}/.claude/skills/claude-codex-workflow.md"
    fi
}

_mode_install() {
    log_step "workflow: mode=install"
    bloom_detect_workflow

    if [[ "$WORKFLOW_STATUS" == "ours-healthy" ]]; then
        log_ok "workflow: already installed and healthy at ${WORKFLOW_PATH}"
        state_set_component_installed "workflow" "${WORKFLOW_VERSION:-unknown}" "install"
        return 0
    fi

    ensure_dir "${HOME}/.claude"
    _wf_clone_or_update "$WORKFLOW_INSTALL_PATH"
    _wf_run_post_install "$WORKFLOW_INSTALL_PATH"

    local ver=""
    [[ -f "${WORKFLOW_INSTALL_PATH}/VERSION" ]] && ver="$(cat "${WORKFLOW_INSTALL_PATH}/VERSION")"
    ver="${ver:-$(git -C "$WORKFLOW_INSTALL_PATH" describe --tags --always 2>/dev/null || echo "unknown")}"

    state_set_component_installed "workflow" "$ver" "install"
    state_set "component.workflow.path" "$WORKFLOW_INSTALL_PATH"
    log_ok "workflow: installed at ${WORKFLOW_INSTALL_PATH} (${ver})"
}

_mode_reuse() {
    log_step "workflow: mode=reuse"
    bloom_detect_workflow

    if [[ "$WORKFLOW_STATUS" == "missing" ]]; then
        log_error "workflow: reuse requested but not found"
        return 1
    fi

    state_set_component_installed "workflow" "${WORKFLOW_VERSION:-unknown}" "reuse"
    state_set "component.workflow.path" "$WORKFLOW_PATH"
    log_ok "workflow: reuse — registered ${WORKFLOW_PATH}"
}

_mode_wrap() {
    log_step "workflow: mode=wrap"
    bloom_detect_workflow

    if [[ "$WORKFLOW_STATUS" == "missing" ]]; then
        log_warn "workflow: wrap requested but not found — falling back to install"
        _mode_install; return $?
    fi

    if [[ "$WORKFLOW_OUR_VERSION" == "true" ]]; then
        _mode_reuse; return $?
    fi

    # For workflow, "wrap" means we layer our CLAUDE.md on top of existing workflow dir
    local overlay_conf="${WORKFLOW_PATH}/bloom-workflow.conf"
    log_info "workflow: creating bloom overlay config at ${overlay_conf}"

    cat > "$overlay_conf" <<WFCONF
# bloom-node-bootstrap workflow overlay
# Created: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
BLOOM_OVERLAY=true
BLOOM_ORIGINAL_PATH=${WORKFLOW_PATH}
WFCONF

    state_set_component_installed "workflow" "${WORKFLOW_VERSION:-unknown}" "wrap"
    state_set "component.workflow.path" "$WORKFLOW_PATH"
    log_ok "workflow: wrap overlay installed"
}

_mode_replace() {
    log_step "workflow: mode=replace"
    bloom_detect_workflow

    if [[ "$WORKFLOW_STATUS" != "missing" ]]; then
        if ! confirm "Replace existing workflow at ${WORKFLOW_PATH}?"; then
            log_info "workflow: replace cancelled"
            return 1
        fi
        backup_path "$WORKFLOW_PATH"
        [[ -d "$WORKFLOW_PATH" ]] && run_cmd rm -rf "$WORKFLOW_PATH"
    fi

    _mode_install
}

_mode_side_by_side() {
    log_step "workflow: mode=side-by-side"
    local sbs_path="${HOME}/.claude/workflow-bloom"
    _wf_clone_or_update "$sbs_path"
    _wf_run_post_install "$sbs_path"

    state_set_component_installed "workflow" "side-by-side" "side-by-side"
    state_set "component.workflow.sbs_path" "$sbs_path"
    log_ok "workflow: side-by-side install at ${sbs_path}"
}

_mode_skip() {
    log_step "workflow: mode=skip"
    state_set_skip "workflow" "user-requested-skip"
    log_info "workflow: skipped"
}

bloom_install_workflow() {
    log_section "Installing component: workflow"
    case "${MODE}" in
        install)      _mode_install ;;
        reuse)        _mode_reuse ;;
        wrap)         _mode_wrap ;;
        replace)      _mode_replace ;;
        side-by-side) _mode_side_by_side ;;
        skip)         _mode_skip ;;
        *) log_error "workflow: unknown MODE='${MODE}'"; return 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bloom_install_workflow
fi
