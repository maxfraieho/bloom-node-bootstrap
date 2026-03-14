#!/usr/bin/env bash
# bootstrap/common.sh
# Shared utilities for all bloom-node-bootstrap scripts.
# Source this file; do not execute directly.
#
# Sets BLOOM_ROOT to the repo root (auto-detected from this file's location).

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve BLOOM_ROOT: the directory containing this repo
# ---------------------------------------------------------------------------
_THIS_FILE="${BASH_SOURCE[0]}"
# Resolve symlinks
while [[ -L "$_THIS_FILE" ]]; do
    _THIS_FILE="$(readlink "$_THIS_FILE")"
done
# bootstrap/ is one level inside the repo root
BLOOM_ROOT="$(cd "$(dirname "$_THIS_FILE")/.." && pwd)"
export BLOOM_ROOT

# State file location (can be overridden by caller)
STATE_FILE="${BLOOM_STATE_FILE:-${HOME}/.bloom-node-state}"
export STATE_FILE

# Dry-run flag — set to "true" to print commands without executing them
DRY_RUN="${DRY_RUN:-false}"
export DRY_RUN

# ---------------------------------------------------------------------------
# Source logging if not already loaded
# ---------------------------------------------------------------------------
if ! declare -f log_info &>/dev/null; then
    # shellcheck source=bootstrap/logging.sh
    source "${BLOOM_ROOT}/bootstrap/logging.sh"
fi

# ---------------------------------------------------------------------------
# require_cmd CMD [HINT]
# Exit with an error if CMD is not found in PATH.
# ---------------------------------------------------------------------------
require_cmd() {
    local cmd="$1"
    local hint="${2:-}"
    if ! command -v "$cmd" &>/dev/null; then
        if [[ -n "$hint" ]]; then
            die "Required command not found: '${cmd}'. ${hint}"
        else
            die "Required command not found: '${cmd}'"
        fi
    fi
    log_debug "require_cmd: '${cmd}' found at $(command -v "$cmd")"
}

# ---------------------------------------------------------------------------
# confirm QUESTION
# Interactive yes/no prompt. Returns 0 for yes, 1 for no.
# Non-interactive (no tty) defaults to "no" unless BLOOM_ASSUME_YES=true.
# ---------------------------------------------------------------------------
confirm() {
    local question="$1"
    if [[ "${BLOOM_ASSUME_YES:-false}" == "true" ]]; then
        log_debug "confirm: BLOOM_ASSUME_YES set — answering yes to: ${question}"
        return 0
    fi
    if [[ ! -t 0 ]]; then
        log_warn "Non-interactive mode; defaulting to no for: ${question}"
        return 1
    fi
    local answer
    while true; do
        printf "%b%s [y/N]: %b" "${CLR_BOLD}" "${question}" "${CLR_RESET}" >&2
        read -r answer
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no|"") return 1 ;;
            *) printf "Please answer y or n.\n" >&2 ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# run_cmd CMD [ARGS...]
# Run a command with logging. In DRY_RUN mode, print but don't execute.
# ---------------------------------------------------------------------------
run_cmd() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] would run: $*"
        return 0
    fi
    log_debug "run_cmd: $*"
    "$@"
}

# ---------------------------------------------------------------------------
# run_cmd_safe CMD [ARGS...]
# Like run_cmd but does not abort on failure; caller checks return value.
# ---------------------------------------------------------------------------
run_cmd_safe() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] would run: $*"
        return 0
    fi
    log_debug "run_cmd_safe: $*"
    "$@" || true
}

# ---------------------------------------------------------------------------
# source_profile PROFILE_NAME
# Load a profile file from ${BLOOM_ROOT}/profiles/.
# ---------------------------------------------------------------------------
source_profile() {
    local name="$1"
    local profile_file="${BLOOM_ROOT}/profiles/${name}.sh"
    if [[ ! -f "$profile_file" ]]; then
        die "Profile not found: '${name}' (looked for ${profile_file})"
    fi
    log_debug "source_profile: loading ${profile_file}"
    # shellcheck disable=SC1090
    source "$profile_file"
}

# ---------------------------------------------------------------------------
# load_component COMPONENT ACTION [EXTRA_ARGS...]
# Source components/COMPONENT/ACTION.sh and call bloom_component_ACTION.
# ACTION: detect | install | verify
# ---------------------------------------------------------------------------
load_component() {
    local component="$1"
    local action="$2"
    shift 2
    local script="${BLOOM_ROOT}/components/${component}/${action}.sh"
    if [[ ! -f "$script" ]]; then
        die "Component script not found: ${script}"
    fi
    log_debug "load_component: ${component}/${action}"
    # shellcheck disable=SC1090
    source "$script"
    # Each component script exports a function named bloom_<action>_<component>
    local fn="bloom_${action}_${component//-/_}"
    if declare -f "$fn" &>/dev/null; then
        "$fn" "$@"
    else
        die "Function '${fn}' not defined in ${script}"
    fi
}

# ---------------------------------------------------------------------------
# is_dry_run — convenience predicate
# ---------------------------------------------------------------------------
is_dry_run() {
    [[ "${DRY_RUN}" == "true" ]]
}

# ---------------------------------------------------------------------------
# ensure_dir DIR
# Create directory if it does not exist.
# ---------------------------------------------------------------------------
ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        log_debug "ensure_dir: creating ${dir}"
        run_cmd mkdir -p "$dir"
    fi
}

# ---------------------------------------------------------------------------
# backup_path PATH
# Copy PATH to PATH.bloom-backup.<timestamp> before overwriting.
# ---------------------------------------------------------------------------
backup_path() {
    local target="$1"
    if [[ -e "$target" ]]; then
        local backup="${target}.bloom-backup.$(date '+%Y%m%d%H%M%S')"
        log_info "Backing up '${target}' → '${backup}'"
        run_cmd cp -a "$target" "$backup"
        echo "$backup"
    fi
}

# ---------------------------------------------------------------------------
# check_min_ram MB
# Return 0 if available RAM >= MB, 1 otherwise.
# ---------------------------------------------------------------------------
check_min_ram() {
    local min_mb="$1"
    local mem_mb
    mem_mb=$(awk '/MemTotal/ { printf "%d", $2/1024 }' /proc/meminfo 2>/dev/null || echo 0)
    log_debug "check_min_ram: system has ${mem_mb}MB, minimum is ${min_mb}MB"
    [[ "$mem_mb" -ge "$min_mb" ]]
}

# ---------------------------------------------------------------------------
# get_distro_id
# Print the distro ID from /etc/os-release (e.g. ubuntu, alpine, debian).
# ---------------------------------------------------------------------------
get_distro_id() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        (source /etc/os-release && echo "${ID:-unknown}")
    else
        echo "unknown"
    fi
}

# ---------------------------------------------------------------------------
# get_pkg_manager
# Detect the system package manager.
# ---------------------------------------------------------------------------
get_pkg_manager() {
    for pm in apt-get apk dnf yum pacman zypper; do
        if command -v "$pm" &>/dev/null; then
            echo "$pm"
            return 0
        fi
    done
    echo "none"
}

# ---------------------------------------------------------------------------
# version_gte VERSION_A VERSION_B
# Return 0 if VERSION_A >= VERSION_B (simple dot-separated comparison).
# ---------------------------------------------------------------------------
version_gte() {
    local a="$1"
    local b="$2"
    # Use sort -V if available
    if command -v sort &>/dev/null && sort --version-sort /dev/null 2>/dev/null; then
        [[ "$(printf '%s\n%s' "$a" "$b" | sort -V | tail -1)" == "$a" ]]
    else
        # Fallback: compare major.minor only
        local a_maj a_min b_maj b_min
        a_maj="${a%%.*}"; a="${a#*.}"; a_min="${a%%.*}"
        b_maj="${b%%.*}"; b="${b#*.}"; b_min="${b%%.*}"
        if [[ "$a_maj" -gt "$b_maj" ]]; then return 0; fi
        if [[ "$a_maj" -eq "$b_maj" && "$a_min" -ge "$b_min" ]]; then return 0; fi
        return 1
    fi
}

log_debug "common.sh loaded (BLOOM_ROOT=${BLOOM_ROOT}, STATE_FILE=${STATE_FILE})"
