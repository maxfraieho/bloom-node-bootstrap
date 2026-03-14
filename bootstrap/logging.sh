#!/usr/bin/env bash
# bootstrap/logging.sh
# Colored, leveled logging for bloom-node-bootstrap.
# Source this file; do not execute directly.
#
# Environment:
#   BLOOM_LOG_LEVEL  — debug | info | warn | error  (default: info)
#   BLOOM_NO_COLOR   — set to any value to disable color output
#   BLOOM_LOG_TS     — set to any value to prefix lines with timestamps

set -euo pipefail

# ---------------------------------------------------------------------------
# Log level constants (numeric for comparison)
# ---------------------------------------------------------------------------
readonly _LOG_DEBUG=0
readonly _LOG_INFO=1
readonly _LOG_WARN=2
readonly _LOG_ERROR=3

# ---------------------------------------------------------------------------
# Color codes (disabled when BLOOM_NO_COLOR is set or stdout is not a tty)
# ---------------------------------------------------------------------------
_init_colors() {
    if [[ -n "${BLOOM_NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
        CLR_RESET=""
        CLR_BOLD=""
        CLR_DIM=""
        CLR_RED=""
        CLR_YELLOW=""
        CLR_GREEN=""
        CLR_CYAN=""
        CLR_BLUE=""
        CLR_MAGENTA=""
    else
        CLR_RESET="\033[0m"
        CLR_BOLD="\033[1m"
        CLR_DIM="\033[2m"
        CLR_RED="\033[31m"
        CLR_YELLOW="\033[33m"
        CLR_GREEN="\033[32m"
        CLR_CYAN="\033[36m"
        CLR_BLUE="\033[34m"
        CLR_MAGENTA="\033[35m"
    fi
}

_init_colors

# ---------------------------------------------------------------------------
# Resolve numeric log level from BLOOM_LOG_LEVEL env var
# ---------------------------------------------------------------------------
_current_log_level() {
    case "${BLOOM_LOG_LEVEL:-info}" in
        debug) echo $_LOG_DEBUG ;;
        info)  echo $_LOG_INFO  ;;
        warn)  echo $_LOG_WARN  ;;
        error) echo $_LOG_ERROR ;;
        *)     echo $_LOG_INFO  ;;  # safe default
    esac
}

# ---------------------------------------------------------------------------
# Internal: _log LEVEL_NUM LABEL COLOR MESSAGE...
# ---------------------------------------------------------------------------
_log() {
    local level_num="$1"
    local label="$2"
    local color="$3"
    shift 3
    local message="$*"

    local current
    current=$(_current_log_level)

    # Skip if below current log level
    [[ "$level_num" -lt "$current" ]] && return 0

    local ts=""
    if [[ -n "${BLOOM_LOG_TS:-}" ]]; then
        ts="$(date '+%Y-%m-%dT%H:%M:%S') "
    fi

    printf "%b%s[%s]%b %s\n" \
        "${color}" \
        "${ts}" \
        "${label}" \
        "${CLR_RESET}" \
        "${message}" >&2
}

# ---------------------------------------------------------------------------
# Public logging functions
# ---------------------------------------------------------------------------

# log_debug MESSAGE — verbose detail, shown only at debug level
log_debug() {
    _log $_LOG_DEBUG "DEBUG" "${CLR_DIM}" "$*"
}

# log_info MESSAGE — normal progress information
log_info() {
    _log $_LOG_INFO "INFO " "${CLR_CYAN}" "$*"
}

# log_warn MESSAGE — non-fatal warning
log_warn() {
    _log $_LOG_WARN "WARN " "${CLR_YELLOW}" "$*"
}

# log_error MESSAGE — fatal or serious error
log_error() {
    _log $_LOG_ERROR "ERROR" "${CLR_RED}" "$*"
}

# log_ok MESSAGE — success confirmation
log_ok() {
    _log $_LOG_INFO "OK   " "${CLR_GREEN}" "$*"
}

# log_step MESSAGE — high-level pipeline step header
log_step() {
    local msg="$*"
    local line
    line="$(printf '%.0s─' {1..60})"
    _log $_LOG_INFO "STEP " "${CLR_BOLD}${CLR_BLUE}" "${line}"
    _log $_LOG_INFO "STEP " "${CLR_BOLD}${CLR_BLUE}" "  ${msg}"
    _log $_LOG_INFO "STEP " "${CLR_BOLD}${CLR_BLUE}" "${line}"
}

# log_section TITLE — section separator
log_section() {
    printf "%b\n>>> %s\n%b\n" "${CLR_BOLD}${CLR_MAGENTA}" "$*" "${CLR_RESET}" >&2
}

# die MESSAGE [EXIT_CODE] — log error and exit
die() {
    local msg="$1"
    local code="${2:-1}"
    log_error "${msg}"
    exit "$code"
}
