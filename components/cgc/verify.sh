#!/usr/bin/env bash
# components/cgc/verify.sh
# Health verification for cgc component.
# Exit codes: 0=OK, 1=WARN, 2=FAIL

set -euo pipefail

_CGC_VERIFY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BLOOM_ROOT_GUESS="$(cd "${_CGC_VERIFY_DIR}/../.." && pwd)"

if ! declare -f log_info &>/dev/null; then
    # shellcheck source=bootstrap/common.sh
    source "${_BLOOM_ROOT_GUESS}/bootstrap/common.sh"
fi

bloom_verify_cgc() {
    log_section "Verifying component: cgc"

    local exit_code=0
    local issues=()

    # 1. Check binary exists and is executable
    local cgc_bin=""
    for loc in "${HOME}/.local/bin/cgc" "${HOME}/cgc-rpi/cgc" "${HOME}/cgc/cgc" "/usr/local/bin/cgc"; do
        if [[ -f "$loc" && -x "$loc" ]]; then
            cgc_bin="$loc"
            break
        fi
    done
    if command -v cgc &>/dev/null; then
        cgc_bin="${cgc_bin:-$(command -v cgc)}"
    fi

    if [[ -z "$cgc_bin" ]]; then
        log_error "cgc: binary not found in any expected location"
        return 2
    fi
    log_ok "cgc: binary found at ${cgc_bin}"

    # 2. Binary responds to --help or --version
    if ! "$cgc_bin" --help &>/dev/null 2>&1 && ! "$cgc_bin" --version &>/dev/null 2>&1; then
        issues+=("cgc binary does not respond to --help or --version")
        exit_code=2
    else
        local ver
        ver="$("$cgc_bin" --version 2>/dev/null | head -1 || echo "unknown")"
        log_ok "cgc: responds to version query (${ver})"
    fi

    # 3. Check for bloom wrapper marker if we installed it
    if [[ -f "$cgc_bin" ]]; then
        if grep -q "BLOOM_WRAP\|bloom-node-bootstrap" "$cgc_bin" 2>/dev/null; then
            log_ok "cgc: bloom wrapper/marker detected"
        fi
    fi

    # 4. ~/.local/bin in PATH?
    if [[ ":${PATH}:" != *":${HOME}/.local/bin:"* ]]; then
        issues+=("~/.local/bin not in PATH — cgc may not be reachable from shell")
        [[ $exit_code -lt 1 ]] && exit_code=1
    else
        log_ok "cgc: ~/.local/bin is in PATH"
    fi

    # 5. Report issues
    if [[ ${#issues[@]} -gt 0 ]]; then
        for issue in "${issues[@]}"; do
            log_warn "cgc: ${issue}"
        done
    fi

    case $exit_code in
        0) log_ok "cgc: verification PASSED" ;;
        1) log_warn "cgc: verification PASSED with warnings" ;;
        2) log_error "cgc: verification FAILED" ;;
    esac

    return $exit_code
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    bloom_verify_cgc
fi
