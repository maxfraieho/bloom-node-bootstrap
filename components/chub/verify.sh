#!/usr/bin/env bash
# components/chub/verify.sh
# Health check for chub component.
# Exit codes: 0=OK, 1=WARN, 2=FAIL

set -euo pipefail

_CHUB_VERIFY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BLOOM_ROOT_GUESS="$(cd "${_CHUB_VERIFY_DIR}/../.." && pwd)"

if ! declare -f log_info &>/dev/null; then
    source "${_BLOOM_ROOT_GUESS}/bootstrap/common.sh"
fi

bloom_verify_chub() {
    log_section "Verifying component: chub"

    local exit_code=0
    local issues=()

    # 1. Binary presence
    local chub_bin=""
    for loc in "${HOME}/.local/bin/chub" "${HOME}/context-hub-rpi/chub" \
                "${HOME}/context-hub/chub" "/usr/local/bin/chub"; do
        if [[ -f "$loc" && -x "$loc" ]]; then
            chub_bin="$loc"
            break
        fi
    done
    command -v chub &>/dev/null && chub_bin="${chub_bin:-$(command -v chub)}"

    if [[ -z "$chub_bin" ]]; then
        log_error "chub: binary not found"
        return 2
    fi
    log_ok "chub: binary at ${chub_bin}"

    # 2. Responds to help/version
    if ! "$chub_bin" --help &>/dev/null 2>&1 && \
       ! "$chub_bin" --version &>/dev/null 2>&1 && \
       ! "$chub_bin" status &>/dev/null 2>&1; then
        issues+=("chub does not respond to --help/--version/status")
        exit_code=2
    else
        log_ok "chub: responds to CLI"
    fi

    # 3. PATH check
    if [[ ":${PATH}:" != *":${HOME}/.local/bin:"* ]]; then
        issues+=("~/.local/bin not in PATH")
        [[ $exit_code -lt 1 ]] && exit_code=1
    fi

    # 4. Wrapper integrity check
    if grep -q "BLOOM_WRAP=true" "$chub_bin" 2>/dev/null; then
        # Extract original path from wrapper
        local orig
        orig="$(grep 'exec "' "$chub_bin" 2>/dev/null | head -1 | sed 's/.*exec "//;s/".*//' || true)"
        if [[ -n "$orig" && ! -f "$orig" ]]; then
            issues+=("chub wrapper points to missing original: ${orig}")
            exit_code=2
        else
            log_ok "chub: wrapper original exists at ${orig}"
        fi
    fi

    for issue in "${issues[@]}"; do
        log_warn "chub: ${issue}"
    done

    case $exit_code in
        0) log_ok "chub: verification PASSED" ;;
        1) log_warn "chub: verification PASSED with warnings" ;;
        2) log_error "chub: verification FAILED" ;;
    esac

    return $exit_code
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bloom_verify_chub
fi
