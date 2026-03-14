#!/usr/bin/env bash
# components/hooks/install.sh
# Install Claude lifecycle hooks into ~/.claude/hooks/.
# Hooks are sourced from the workflow repo (if installed) or from this repo's
# bundled hooks directory.
#
# MODE: install | reuse | wrap | replace | side-by-side | skip

set -euo pipefail

_HOOKS_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BLOOM_ROOT_GUESS="$(cd "${_HOOKS_INSTALL_DIR}/../.." && pwd)"

if ! declare -f log_info &>/dev/null; then
    source "${_BLOOM_ROOT_GUESS}/bootstrap/common.sh"
fi
if ! declare -f state_set &>/dev/null; then
    source "${_BLOOM_ROOT_GUESS}/bootstrap/state-store.sh"
fi
source "${_HOOKS_INSTALL_DIR}/detect.sh"

HOOKS_TARGET_DIR="${HOME}/.claude/hooks"
MODE="${MODE:-install}"

# ---------------------------------------------------------------------------
# _hooks_find_source_dir
# Locate the directory that contains our hook templates.
# Priority: workflow repo > this bootstrap repo's bundled hooks
# ---------------------------------------------------------------------------
_hooks_find_source_dir() {
    # 1. Workflow repo (preferred — canonical hooks live there)
    local workflow_hooks=""
    for wf_loc in "${HOME}/.bloom/sources/claude-codex-workflow/hooks" \
                   "${HOME}/.claude/workflow/hooks" \
                   "${HOME}/claude-codex-workflow/hooks" \
                   "${HOME}/.claude/workflow-bloom/hooks"; do
        if [[ -d "$wf_loc" ]]; then
            workflow_hooks="$wf_loc"
            break
        fi
    done

    if [[ -n "$workflow_hooks" ]]; then
        echo "$workflow_hooks"
        return 0
    fi

    # 2. Bundled in this bootstrap repo
    local bundled="${_BLOOM_ROOT_GUESS}/components/hooks/bundled"
    if [[ -d "$bundled" ]]; then
        echo "$bundled"
        return 0
    fi

    echo ""
}

# ---------------------------------------------------------------------------
# _hooks_install_from_source SOURCE_DIR TARGET_DIR
# Copy/link hook files into target dir, stamping each with our marker.
# ---------------------------------------------------------------------------
_hooks_install_from_source() {
    local src="$1"
    local dst="$2"

    ensure_dir "$dst"

    local installed=0
    while IFS= read -r hook_file; do
        local base
        base="$(basename "$hook_file")"
        local dst_file="${dst}/${base}"

        # Skip non-executable non-JSON files that aren't hook scripts
        [[ "$base" == .* ]] && continue

        if [[ -f "$dst_file" ]]; then
            # Check if it's ours or foreign
            if grep -q "BLOOM_HOOK\|bloom-node-bootstrap" "$dst_file" 2>/dev/null; then
                log_debug "hooks: overwriting our existing hook ${base}"
            else
                log_warn "hooks: ${base} exists and is not ours — backing up"
                backup_path "$dst_file"
            fi
        fi

        log_info "hooks: installing ${base} → ${dst_file}"
        run_cmd cp "$hook_file" "$dst_file"
        run_cmd chmod +x "$dst_file"
        installed=$((installed + 1))
    # Include executables without extension (e.g. UserPromptSubmit)
    done < <(find "$src" -maxdepth 1 -type f \( -name "*.sh" -o -name "*.py" -o -name "*.json" -o \( ! -name "*.*" ! -name "README*" \) \) 2>/dev/null)

    log_ok "hooks: installed ${installed} hook(s) from ${src}"
    echo "$installed"
}

# ---------------------------------------------------------------------------
# _hooks_patch_settings
# Ensure ctx-workflow-policy.sh and unified-skill-hook.sh are registered
# in ~/.claude/settings.json under hooks.UserPromptSubmit.
# Preserves existing entries (machine-local hooks like claude-mem-minio).
# ---------------------------------------------------------------------------
_hooks_patch_settings() {
    local settings_file="${HOME}/.claude/settings.json"
    local hooks_dir="${HOME}/.claude/hooks"
    local policy_hook="${hooks_dir}/ctx-workflow-policy.sh"
    local skill_hook="${hooks_dir}/unified-skill-hook.sh"

    if [[ ! -f "$settings_file" ]]; then
        log_warn "hooks: settings.json not found at ${settings_file} — creating minimal"
        ensure_dir "${HOME}/.claude"
        cat > "$settings_file" <<SETTINGS
{
  "hooks": {
    "UserPromptSubmit": []
  }
}
SETTINGS
    fi

    # Backup before patching
    run_cmd cp "$settings_file" "${settings_file}.bloom.bak"

    # Use python3 to safely patch the JSON
    python3 - "$settings_file" "$policy_hook" "$skill_hook" <<'PYEOF'
import sys, json, os

settings_path, policy_hook, skill_hook = sys.argv[1], sys.argv[2], sys.argv[3]

with open(settings_path) as f:
    data = json.load(f)

data.setdefault("hooks", {})
data["hooks"].setdefault("UserPromptSubmit", [])

# Collect existing hook commands
existing_cmds = set()
for entry in data["hooks"]["UserPromptSubmit"]:
    for h in entry.get("hooks", []):
        existing_cmds.add(h.get("command", ""))

# Add missing hooks
for hook_cmd in [skill_hook, policy_hook]:
    if hook_cmd not in existing_cmds:
        data["hooks"]["UserPromptSubmit"].append({
            "hooks": [{"type": "command", "command": hook_cmd}]
        })
        print(f"  registered: {hook_cmd}", file=sys.stderr)
    else:
        print(f"  already registered: {hook_cmd}", file=sys.stderr)

with open(settings_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

print("settings.json patched OK", file=sys.stderr)
PYEOF

    log_ok "hooks: settings.json patched — hooks registered"
}

# ---------------------------------------------------------------------------
# _hooks_create_minimal_set
# If no source directory is available, create a minimal set of bloom hooks.
# ---------------------------------------------------------------------------
_hooks_create_minimal_set() {
    local dst="$1"
    ensure_dir "$dst"

    log_info "hooks: creating minimal bloom hook set"

    # pre-tool hook: log tool calls
    cat > "${dst}/pre-tool.sh" <<'HOOK'
#!/usr/bin/env bash
# bloom-node-bootstrap pre-tool hook
# BLOOM_HOOK=pre-tool
# Called by Claude Code before each tool use.
# Input: JSON on stdin with tool name and parameters.
# Exit 0 to allow, non-zero to block.

# Read input (optional — tools can be allowed without reading)
input="$(cat)"

# Log tool calls in debug mode
if [[ -n "${BLOOM_HOOK_DEBUG:-}" ]]; then
    echo "[bloom pre-tool] $(date -u '+%H:%M:%S') $input" >> "${HOME}/.bloom-hook.log"
fi

exit 0
HOOK
    chmod +x "${dst}/pre-tool.sh"

    # post-tool hook: log results
    cat > "${dst}/post-tool.sh" <<'HOOK'
#!/usr/bin/env bash
# bloom-node-bootstrap post-tool hook
# BLOOM_HOOK=post-tool
# Called by Claude Code after each tool use completes.

input="$(cat)"

if [[ -n "${BLOOM_HOOK_DEBUG:-}" ]]; then
    echo "[bloom post-tool] $(date -u '+%H:%M:%S') $input" >> "${HOME}/.bloom-hook.log"
fi

exit 0
HOOK
    chmod +x "${dst}/post-tool.sh"

    # notification hook
    cat > "${dst}/notification.sh" <<'HOOK'
#!/usr/bin/env bash
# bloom-node-bootstrap notification hook
# BLOOM_HOOK=notification
# Called when Claude Code sends a notification.

input="$(cat)"
message="$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('message',''))" 2>/dev/null || echo "$input")"

# On systems with notify-send, show desktop notification
if command -v notify-send &>/dev/null && [[ -n "$message" ]]; then
    notify-send "Claude Code" "$message" 2>/dev/null || true
fi

exit 0
HOOK
    chmod +x "${dst}/notification.sh"

    log_ok "hooks: created 3 minimal bloom hooks in ${dst}"
}

# ---------------------------------------------------------------------------
# Mode implementations
# ---------------------------------------------------------------------------

_mode_install() {
    log_step "hooks: mode=install"
    bloom_detect_hooks

    if [[ "$HOOKS_STATUS" == "ours-healthy" ]]; then
        log_ok "hooks: already installed and healthy (${HOOKS_BLOOM_COUNT} bloom hooks)"
        state_set_component_installed "hooks" "${HOOKS_BLOOM_COUNT}" "install"
        return 0
    fi

    ensure_dir "$HOOKS_TARGET_DIR"

    local src_dir
    src_dir="$(_hooks_find_source_dir)"

    if [[ -n "$src_dir" ]]; then
        _hooks_install_from_source "$src_dir" "$HOOKS_TARGET_DIR"
    else
        log_warn "hooks: no source directory found — creating minimal built-in set"
        _hooks_create_minimal_set "$HOOKS_TARGET_DIR"
    fi

    local count
    count=$(find "$HOOKS_TARGET_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l)
    state_set_component_installed "hooks" "$count" "install"
    state_set "component.hooks.path" "$HOOKS_TARGET_DIR"

    # Register hooks in ~/.claude/settings.json
    _hooks_patch_settings
}

_mode_reuse() {
    log_step "hooks: mode=reuse"
    bloom_detect_hooks

    if [[ "$HOOKS_STATUS" == "missing" ]]; then
        log_error "hooks: reuse requested but no hooks found"
        return 1
    fi

    state_set_component_installed "hooks" "${HOOKS_COUNT:-0}" "reuse"
    state_set "component.hooks.path" "${HOOKS_PATH:-${HOOKS_TARGET_DIR}}"
    log_ok "hooks: reuse — registered ${HOOKS_COUNT:-0} hooks"
}

_mode_wrap() {
    log_step "hooks: mode=wrap"
    bloom_detect_hooks

    if [[ "$HOOKS_STATUS" == "missing" ]]; then
        log_warn "hooks: wrap but none found — installing"
        _mode_install; return $?
    fi

    # Wrap: add our hooks alongside existing ones, don't touch foreign hooks
    local src_dir
    src_dir="$(_hooks_find_source_dir)"

    if [[ -n "$src_dir" ]]; then
        # Only install our hooks that don't conflict with existing names
        while IFS= read -r hook_file; do
            local base
            base="$(basename "$hook_file")"
            local dst_file="${HOOKS_TARGET_DIR}/${base}"
            if [[ -f "$dst_file" ]] && ! grep -q "BLOOM_HOOK" "$dst_file" 2>/dev/null; then
                # Rename ours to bloom-prefixed to avoid conflict
                local bloom_name="${HOOKS_TARGET_DIR}/bloom-${base}"
                log_info "hooks: wrap — installing as bloom-${base} (${base} is foreign)"
                run_cmd cp "$hook_file" "$bloom_name"
                run_cmd chmod +x "$bloom_name"
            else
                log_info "hooks: wrap — installing ${base}"
                run_cmd cp "$hook_file" "$dst_file"
                run_cmd chmod +x "$dst_file"
            fi
        done < <(find "$src_dir" -maxdepth 1 -type f -name "*.sh" 2>/dev/null)
    else
        _hooks_create_minimal_set "$HOOKS_TARGET_DIR"
    fi

    state_set_component_installed "hooks" "wrap" "wrap"
}

_mode_replace() {
    log_step "hooks: mode=replace"
    bloom_detect_hooks

    if [[ "$HOOKS_STATUS" != "missing" ]]; then
        if ! confirm "Replace all hooks in ${HOOKS_TARGET_DIR}?"; then
            log_info "hooks: replace cancelled"
            return 1
        fi
        # Backup existing hooks
        if [[ -d "$HOOKS_TARGET_DIR" ]]; then
            backup_path "$HOOKS_TARGET_DIR"
            run_cmd rm -rf "$HOOKS_TARGET_DIR"
        fi
    fi

    _mode_install
}

_mode_side_by_side() {
    log_step "hooks: mode=side-by-side"
    local sbs_dir="${HOME}/.claude/hooks-bloom"
    ensure_dir "$sbs_dir"

    local src_dir
    src_dir="$(_hooks_find_source_dir)"
    if [[ -n "$src_dir" ]]; then
        _hooks_install_from_source "$src_dir" "$sbs_dir"
    else
        _hooks_create_minimal_set "$sbs_dir"
    fi

    state_set_component_installed "hooks" "side-by-side" "side-by-side"
    state_set "component.hooks.sbs_path" "$sbs_dir"
    log_ok "hooks: side-by-side install at ${sbs_dir}"
    log_info "hooks: to use, set CLAUDE_HOOKS_DIR=${sbs_dir} in your environment"
}

_mode_skip() {
    log_step "hooks: mode=skip"
    state_set_skip "hooks" "user-requested-skip"
    log_info "hooks: skipped"
}

bloom_install_hooks() {
    log_section "Installing component: hooks"
    case "${MODE}" in
        install)      _mode_install ;;
        reuse)        _mode_reuse ;;
        wrap)         _mode_wrap ;;
        replace)      _mode_replace ;;
        side-by-side) _mode_side_by_side ;;
        skip)         _mode_skip ;;
        *) log_error "hooks: unknown MODE='${MODE}'"; return 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bloom_install_hooks
fi
