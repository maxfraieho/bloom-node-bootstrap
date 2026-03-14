#!/usr/bin/env bash
# bootstrap/state-store.sh
# Simple key-value state store backed by a flat file (~/.bloom-node-state).
# Format: KEY=VALUE lines (no spaces around =, values may contain spaces).
# Source this file; do not execute directly.
#
# Public API:
#   state_set KEY VALUE  — write or update a key
#   state_get KEY        — print value (or empty string if missing)
#   state_del KEY        — remove a key
#   state_dump           — print all key=value pairs
#   state_has KEY        — return 0 if key exists, 1 otherwise

set -euo pipefail

# ---------------------------------------------------------------------------
# Ensure STATE_FILE and common utils are available
# ---------------------------------------------------------------------------
if ! declare -f log_debug &>/dev/null; then
    _SS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=bootstrap/logging.sh
    source "${_SS_DIR}/logging.sh"
fi

STATE_FILE="${STATE_FILE:-${HOME}/.bloom-node-state}"

# ---------------------------------------------------------------------------
# _state_lock / _state_unlock — advisory flock around state file writes
# ---------------------------------------------------------------------------
_STATE_LOCK_FD=200
_STATE_LOCK_FILE="${STATE_FILE}.lock"

_state_lock() {
    exec 200>"${_STATE_LOCK_FILE}"
    flock -x 200
}

_state_unlock() {
    flock -u 200
    exec 200>&-
}

# ---------------------------------------------------------------------------
# _state_init
# Create state file if it does not exist.
# ---------------------------------------------------------------------------
_state_init() {
    if [[ ! -f "${STATE_FILE}" ]]; then
        mkdir -p "$(dirname "${STATE_FILE}")"
        touch "${STATE_FILE}"
        log_debug "state-store: created ${STATE_FILE}"
    fi
}

# ---------------------------------------------------------------------------
# state_set KEY VALUE
# Set (or overwrite) KEY to VALUE in the state file.
# ---------------------------------------------------------------------------
state_set() {
    local key="$1"
    local value="$2"
    _state_init
    _state_lock

    # Remove existing entry for this key, then append updated value
    local tmpfile
    tmpfile="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"
    grep -v "^${key}=" "${STATE_FILE}" > "$tmpfile" || true
    printf '%s=%s\n' "$key" "$value" >> "$tmpfile"
    mv "$tmpfile" "${STATE_FILE}"

    _state_unlock
    log_debug "state_set: ${key}=${value}"
}

# ---------------------------------------------------------------------------
# state_get KEY
# Print the value for KEY, or empty string if not set.
# ---------------------------------------------------------------------------
state_get() {
    local key="$1"
    _state_init
    local line
    line=$(grep "^${key}=" "${STATE_FILE}" 2>/dev/null | tail -1 || true)
    if [[ -n "$line" ]]; then
        printf '%s\n' "${line#*=}"
    fi
    # Empty string on miss is intentional
}

# ---------------------------------------------------------------------------
# state_has KEY
# Return 0 if KEY exists in the state file, 1 otherwise.
# ---------------------------------------------------------------------------
state_has() {
    local key="$1"
    _state_init
    grep -q "^${key}=" "${STATE_FILE}" 2>/dev/null
}

# ---------------------------------------------------------------------------
# state_del KEY
# Remove KEY from the state file.
# ---------------------------------------------------------------------------
state_del() {
    local key="$1"
    _state_init
    _state_lock

    local tmpfile
    tmpfile="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"
    grep -v "^${key}=" "${STATE_FILE}" > "$tmpfile" || true
    mv "$tmpfile" "${STATE_FILE}"

    _state_unlock
    log_debug "state_del: ${key}"
}

# ---------------------------------------------------------------------------
# state_dump
# Print all key=value pairs, sorted by key.
# ---------------------------------------------------------------------------
state_dump() {
    _state_init
    sort "${STATE_FILE}"
}

# ---------------------------------------------------------------------------
# state_set_component_installed COMPONENT VERSION MODE
# Convenience: record that a component was successfully installed.
# ---------------------------------------------------------------------------
state_set_component_installed() {
    local component="$1"
    local version="${2:-unknown}"
    local mode="${3:-install}"
    state_set "component.${component}.installed" "true"
    state_set "component.${component}.version" "$version"
    state_set "component.${component}.mode" "$mode"
    state_set "component.${component}.installed_at" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

# ---------------------------------------------------------------------------
# state_get_component_installed COMPONENT
# Return 0 if component is recorded as installed, 1 otherwise.
# ---------------------------------------------------------------------------
state_get_component_installed() {
    local component="$1"
    local val
    val="$(state_get "component.${component}.installed")"
    [[ "$val" == "true" ]]
}

# ---------------------------------------------------------------------------
# state_set_skip COMPONENT REASON
# Record that a component was explicitly skipped.
# ---------------------------------------------------------------------------
state_set_skip() {
    local component="$1"
    local reason="${2:-user-skip}"
    state_set "component.${component}.skip" "true"
    state_set "component.${component}.skip_reason" "$reason"
    state_set "component.${component}.skip_at" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

log_debug "state-store.sh loaded (STATE_FILE=${STATE_FILE})"
