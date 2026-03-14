#!/usr/bin/env bash
# components/hooks/verify.sh
# Health check for hooks component.
# Exit codes: 0=OK, 1=WARN, 2=FAIL

set -euo pipefail

_HOOKS_VERIFY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BLOOM_ROOT_GUESS="$(cd "${_HOOKS_VERIFY_DIR}/../.." && pwd)"

if ! declare -f log_info &>/dev/null; then
    source "${_BLOOM_ROOT_GUESS}/bootstrap/common.sh"
fi

bloom_verify_hooks() {
    log_section "Verifying component: hooks"

    local exit_code=0
    local issues=()
    local hooks_dir="${HOME}/.claude/hooks"

    # 1. Directory exists
    if [[ ! -d "$hooks_dir" ]]; then
        log_error "hooks: directory not found at ${hooks_dir}"
        return 2
    fi
    log_ok "hooks: directory exists at ${hooks_dir}"

    # 2. Count hooks
    local total_hooks
    total_hooks=$(find "$hooks_dir" -maxdepth 1 -type f 2>/dev/null | wc -l)
    if [[ "$total_hooks" -eq 0 ]]; then
        issues+=("hooks directory exists but is empty")
        exit_code=1
    else
        log_ok "hooks: ${total_hooks} hook file(s) found"
    fi

    # 3. All hook scripts are executable
    local non_exec=0
    while IFS= read -r hookfile; do
        [[ -x "$hookfile" ]] || non_exec=$((non_exec + 1))
    done < <(find "$hooks_dir" -maxdepth 1 -type f -name "*.sh" 2>/dev/null)

    if [[ "$non_exec" -gt 0 ]]; then
        issues+=("${non_exec} hook script(s) are not executable")
        [[ $exit_code -lt 1 ]] && exit_code=1
    else
        log_ok "hooks: all shell hooks are executable"
    fi

    # 4. Hook scripts have valid shebang
    local bad_shebang=0
    while IFS= read -r hookfile; do
        local first_line
        first_line=$(head -1 "$hookfile" 2>/dev/null || true)
        if [[ "$first_line" != "#!"* ]]; then
            bad_shebang=$((bad_shebang + 1))
            log_warn "hooks: ${hookfile} has no shebang line"
        fi
    done < <(find "$hooks_dir" -maxdepth 1 -type f -name "*.sh" 2>/dev/null)

    if [[ "$bad_shebang" -gt 0 ]]; then
        issues+=("${bad_shebang} hook script(s) missing shebang")
        [[ $exit_code -lt 1 ]] && exit_code=1
    fi

    # 5. Bloom hooks specifically
    local bloom_hooks
    bloom_hooks=$(grep -rl "BLOOM_HOOK\|bloom-node-bootstrap" "$hooks_dir" 2>/dev/null | wc -l || echo 0)
    if [[ "$bloom_hooks" -gt 0 ]]; then
        log_ok "hooks: ${bloom_hooks} bloom-managed hook(s) found"
    else
        log_info "hooks: no bloom-managed hooks found (may be foreign hooks)"
    fi

    # 6. Python hooks: verify python3 available if any .py hooks exist
    local py_hooks
    py_hooks=$(find "$hooks_dir" -maxdepth 1 -type f -name "*.py" 2>/dev/null | wc -l)
    if [[ "$py_hooks" -gt 0 ]]; then
        if ! command -v python3 &>/dev/null; then
            issues+=("${py_hooks} Python hook(s) found but python3 not in PATH")
            [[ $exit_code -lt 1 ]] && exit_code=1
        else
            log_ok "hooks: python3 available for ${py_hooks} Python hook(s)"
        fi
    fi

    for issue in "${issues[@]}"; do
        log_warn "hooks: ${issue}"
    done

    case $exit_code in
        0) log_ok "hooks: verification PASSED" ;;
        1) log_warn "hooks: verification PASSED with warnings" ;;
        2) log_error "hooks: verification FAILED" ;;
    esac

    return $exit_code
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bloom_verify_hooks
fi
