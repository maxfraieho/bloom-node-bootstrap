#!/usr/bin/env bash
# detect.sh
# Standalone system detection script for bloom-node-bootstrap.
# Outputs key=value pairs (one per line) suitable for sourcing or parsing.
#
# Usage:
#   ./detect.sh                  # prints key=value to stdout
#   ./detect.sh --json           # prints JSON object to stdout
#   ./detect.sh --export         # prints 'export KEY=VALUE' lines
#   source <(./detect.sh --export)  # load into current shell
#
# Exit codes: 0 on success, 1 on critical detection failure.

set -euo pipefail

DETECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Source common only for log_debug; handle gracefully if already sourced
if ! declare -f log_debug &>/dev/null; then
    # shellcheck source=bootstrap/logging.sh
    source "${DETECT_DIR}/bootstrap/logging.sh"
fi

# ---------------------------------------------------------------------------
# Output format flag
# ---------------------------------------------------------------------------
OUTPUT_FORMAT="kv"  # kv | json | export
for arg in "$@"; do
    case "$arg" in
        --json)   OUTPUT_FORMAT="json" ;;
        --export) OUTPUT_FORMAT="export" ;;
        --kv)     OUTPUT_FORMAT="kv" ;;
        --help|-h)
            printf 'Usage: %s [--json|--kv|--export]\n' "$(basename "$0")" >&2
            exit 0 ;;
    esac
done

# ---------------------------------------------------------------------------
# Detection functions
# ---------------------------------------------------------------------------

# Detect system architecture
_detect_arch() {
    uname -m
}

# Normalize arch to CPU class
_detect_cpu_class() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        armv6*)  echo "armv6" ;;
        armv7*)  echo "armv7" ;;
        aarch64|arm64) echo "armv8" ;;
        x86_64|amd64)  echo "x86_64" ;;
        i?86)          echo "x86" ;;
        *)             echo "unknown" ;;
    esac
}

# RAM in MB
_detect_ram_mb() {
    awk '/MemTotal/ { printf "%d", $2/1024 }' /proc/meminfo 2>/dev/null || echo "0"
}

# Swap in MB
_detect_swap_mb() {
    awk '/SwapTotal/ { printf "%d", $2/1024 }' /proc/meminfo 2>/dev/null || echo "0"
}

# Distro from /etc/os-release
_detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        (source /etc/os-release && printf '%s' "${ID:-unknown}")
    else
        echo "unknown"
    fi
}

# Distro version
_detect_distro_version() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        (source /etc/os-release && printf '%s' "${VERSION_ID:-unknown}")
    else
        echo "unknown"
    fi
}

# Package manager
_detect_pkg_manager() {
    for pm in apt-get apk dnf yum pacman zypper; do
        if command -v "$pm" &>/dev/null; then
            echo "$pm"
            return
        fi
    done
    echo "none"
}

# Init system
_detect_init_system() {
    if [[ -d /run/systemd/system ]]; then
        echo "systemd"
    elif [[ -f /sbin/openrc ]] || [[ -f /usr/sbin/openrc ]]; then
        echo "openrc"
    elif command -v sv &>/dev/null && [[ -d /etc/runit ]]; then
        echo "runit"
    elif [[ -f /sbin/init ]] && /sbin/init --version 2>&1 | grep -q busybox; then
        echo "busybox-init"
    else
        echo "none"
    fi
}

# Python availability
_detect_python() {
    for py in python3 python; do
        if command -v "$py" &>/dev/null; then
            local ver
            ver="$($py --version 2>&1 | awk '{print $2}')"
            printf '%s %s' "yes" "$ver"
            return
        fi
    done
    echo "no"
}

_detect_python_path() {
    for py in python3 python; do
        if command -v "$py" &>/dev/null; then
            command -v "$py"
            return
        fi
    done
    echo ""
}

# Detect whether chub (context-hub) is installed
_detect_chub() {
    # Look for chub binary, or common install locations
    local chub_path=""
    for loc in "${HOME}/.local/bin/chub" "${HOME}/context-hub/chub" \
                "/usr/local/bin/chub" "${HOME}/.local/bin/ctx"; do
        if [[ -f "$loc" ]]; then
            chub_path="$loc"
            break
        fi
    done
    # Also check PATH
    if [[ -z "$chub_path" ]] && command -v chub &>/dev/null; then
        chub_path="$(command -v chub)"
    fi
    if [[ -n "$chub_path" ]]; then
        printf 'yes %s' "$chub_path"
    else
        echo "no"
    fi
}

# Detect cgc (Claude git CLI or similar)
_detect_cgc() {
    local cgc_path=""
    for loc in "${HOME}/.local/bin/cgc" "${HOME}/cgc/cgc" \
                "${HOME}/cgc-rpi/cgc" "/usr/local/bin/cgc"; do
        if [[ -f "$loc" ]]; then
            cgc_path="$loc"
            break
        fi
    done
    if [[ -z "$cgc_path" ]] && command -v cgc &>/dev/null; then
        cgc_path="$(command -v cgc)"
    fi
    if [[ -n "$cgc_path" ]]; then
        # Check if this is "our" version by looking for bloom marker
        local our_ver="no"
        if grep -q "bloom-node-bootstrap\|vokov/cgc" "$cgc_path" 2>/dev/null; then
            our_ver="yes"
        fi
        printf 'yes %s our=%s' "$cgc_path" "$our_ver"
    else
        echo "no"
    fi
}

# Detect ctx (Claude context CLI)
_detect_ctx() {
    local ctx_path=""
    for loc in "${HOME}/.local/bin/ctx" "/usr/local/bin/ctx"; do
        if [[ -f "$loc" ]]; then
            ctx_path="$loc"
            break
        fi
    done
    if [[ -z "$ctx_path" ]] && command -v ctx &>/dev/null; then
        ctx_path="$(command -v ctx)"
    fi
    if [[ -n "$ctx_path" ]]; then
        printf 'yes %s' "$ctx_path"
    else
        echo "no"
    fi
}

# Detect ~/.claude directory
_detect_claude_dir() {
    [[ -d "${HOME}/.claude" ]] && echo "yes" || echo "no"
}

# Detect tokens/API key config
_detect_tokens() {
    local found="no"
    # Check common locations for API keys / token files
    for f in "${HOME}/.claude/tokens" "${HOME}/.claude/.env" \
              "${HOME}/.claude/config.json" "${HOME}/.config/claude/tokens"; do
        if [[ -f "$f" ]]; then
            found="yes"
            break
        fi
    done
    # Also check environment
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        found="yes"
    fi
    echo "$found"
}

# Detect hooks directory / presence of bloom hooks
_detect_hooks() {
    local hooks_dir="${HOME}/.claude/hooks"
    if [[ -d "$hooks_dir" ]] && [[ -n "$(ls -A "$hooks_dir" 2>/dev/null)" ]]; then
        local count
        count=$(find "$hooks_dir" -maxdepth 1 -type f 2>/dev/null | wc -l)
        printf 'yes count=%d path=%s' "$count" "$hooks_dir"
    else
        echo "no"
    fi
}

# Detect workflow installation
_detect_workflow() {
    local wf_path=""
    for loc in "${HOME}/.claude/workflow" "${HOME}/claude-codex-workflow" \
                "${HOME}/.local/share/bloom/workflow"; do
        if [[ -d "$loc" ]]; then
            wf_path="$loc"
            break
        fi
    done
    if [[ -n "$wf_path" ]]; then
        printf 'yes %s' "$wf_path"
    else
        echo "no"
    fi
}

# Detect kernel version
_detect_kernel() {
    uname -r
}

# Detect hostname
_detect_hostname() {
    hostname -s 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "unknown"
}

# Detect number of CPUs
_detect_cpus() {
    nproc 2>/dev/null || grep -c processor /proc/cpuinfo 2>/dev/null || echo "1"
}

# Detect disk free in MB for $HOME
_detect_disk_free_mb() {
    df -m "$HOME" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0"
}

# ---------------------------------------------------------------------------
# Collect all detections
# ---------------------------------------------------------------------------
_run_all_detections() {
    ARCH="$(_detect_arch)"
    CPU_CLASS="$(_detect_cpu_class)"
    RAM_MB="$(_detect_ram_mb)"
    SWAP_MB="$(_detect_swap_mb)"
    DISTRO="$(_detect_distro)"
    DISTRO_VERSION="$(_detect_distro_version)"
    PKG_MANAGER="$(_detect_pkg_manager)"
    INIT_SYSTEM="$(_detect_init_system)"
    PYTHON_AVAIL="$(_detect_python)"
    PYTHON_PATH="$(_detect_python_path)"
    HAS_CHUB="$(_detect_chub)"
    HAS_CGC="$(_detect_cgc)"
    HAS_CTX="$(_detect_ctx)"
    HAS_CLAUDE_DIR="$(_detect_claude_dir)"
    HAS_TOKENS="$(_detect_tokens)"
    HAS_HOOKS="$(_detect_hooks)"
    HAS_WORKFLOW="$(_detect_workflow)"
    KERNEL="$(_detect_kernel)"
    HOSTNAME_SHORT="$(_detect_hostname)"
    NUM_CPUS="$(_detect_cpus)"
    DISK_FREE_MB="$(_detect_disk_free_mb)"
    DETECT_TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

# ---------------------------------------------------------------------------
# Output formatters
# ---------------------------------------------------------------------------

_output_kv() {
    cat <<EOF
ARCH=${ARCH}
CPU_CLASS=${CPU_CLASS}
RAM_MB=${RAM_MB}
SWAP_MB=${SWAP_MB}
DISTRO=${DISTRO}
DISTRO_VERSION=${DISTRO_VERSION}
PKG_MANAGER=${PKG_MANAGER}
INIT_SYSTEM=${INIT_SYSTEM}
PYTHON_AVAIL=${PYTHON_AVAIL}
PYTHON_PATH=${PYTHON_PATH}
HAS_CHUB=${HAS_CHUB}
HAS_CGC=${HAS_CGC}
HAS_CTX=${HAS_CTX}
HAS_CLAUDE_DIR=${HAS_CLAUDE_DIR}
HAS_TOKENS=${HAS_TOKENS}
HAS_HOOKS=${HAS_HOOKS}
HAS_WORKFLOW=${HAS_WORKFLOW}
KERNEL=${KERNEL}
HOSTNAME_SHORT=${HOSTNAME_SHORT}
NUM_CPUS=${NUM_CPUS}
DISK_FREE_MB=${DISK_FREE_MB}
DETECT_TIMESTAMP=${DETECT_TIMESTAMP}
EOF
}

_output_export() {
    while IFS='=' read -r key val; do
        [[ -z "$key" ]] && continue
        printf "export %s='%s'\n" "$key" "$val"
    done < <(_output_kv)
}

_output_json() {
    # Minimal JSON without jq dependency
    printf '{\n'
    local first=true
    while IFS='=' read -r key val; do
        [[ -z "$key" ]] && continue
        [[ "$first" == "true" ]] && first=false || printf ',\n'
        # Escape double quotes in value
        val="${val//\"/\\\"}"
        printf '  "%s": "%s"' "$key" "$val"
    done < <(_output_kv)
    printf '\n}\n'
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
_run_all_detections

case "$OUTPUT_FORMAT" in
    json)   _output_json ;;
    export) _output_export ;;
    kv|*)   _output_kv ;;
esac
