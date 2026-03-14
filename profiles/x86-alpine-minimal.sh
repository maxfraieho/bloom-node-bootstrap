#!/usr/bin/env bash
# profiles/x86-alpine-minimal.sh
# Profile for Alpine Linux on x86_64.
# Target: containers, diskless servers, minimal VMs.
# Strategy: apk only, musl-aware installs, no systemd, OpenRC or none.

PROFILE_NAME="x86-alpine-minimal"
PROFILE_DESC="Alpine Linux on x86_64 (containers, diskless, minimal VMs)"

# Containers often have limited CPU quota too
PROFILE_MAX_PARALLEL=1

# Alpine containers often have no swap
PROFILE_SKIP_SWAP_CHECK=true
PROFILE_MIN_FREE_RAM_MB=64

PROFILE_COMPONENTS="cgc chub workflow hooks tokens-config"

PROFILE_DEFAULT_MODE_CGC="install"
PROFILE_DEFAULT_MODE_CHUB="install"
PROFILE_DEFAULT_MODE_WORKFLOW="install"
PROFILE_DEFAULT_MODE_HOOKS="install"
PROFILE_DEFAULT_MODE_TOKENS_CONFIG="reuse"
PROFILE_DEFAULT_MODE_SYSTEM_TUNING="skip"

# zram not applicable in containers
PROFILE_ZRAM_RECOMMEND=false

# Alpine ships Python 3 via apk; musl may affect some pip packages
PROFILE_PYTHON_MIN="3.9"
PROFILE_PYTHON_PREFERRED="3.11"

# apk only
PROFILE_PKG_MANAGERS="apk"

# Shallow clones in containers (disk is ephemeral)
PROFILE_GIT_CLONE_DEPTH=1

PROFILE_INSTALL_DEV_DEPS=false

# Alpine uses musl libc — some Python wheels must be built from source
PROFILE_MUSL_COMPAT=true

# Init system: OpenRC in full Alpine, none in containers
PROFILE_INIT_SYSTEM="openrc"  # will be overridden at detect time if none

# Alpine doesn't have bash by default — verify before using bash features
PROFILE_REQUIRE_BASH_INSTALL=true

PROFILE_NOTES="Alpine Linux detected. Bash may need to be installed first: 'apk add bash git python3'. Some Python packages with C extensions may require build tools: 'apk add build-base python3-dev'. musl libc compatibility checked per component."

# ctx context profile: default (Alpine containers use general-purpose workflow)
PROFILE_CTX_PROFILE="default"

export PROFILE_NAME PROFILE_DESC PROFILE_MAX_PARALLEL PROFILE_SKIP_SWAP_CHECK \
       PROFILE_MIN_FREE_RAM_MB PROFILE_COMPONENTS \
       PROFILE_DEFAULT_MODE_CGC PROFILE_DEFAULT_MODE_CHUB \
       PROFILE_DEFAULT_MODE_WORKFLOW PROFILE_DEFAULT_MODE_HOOKS \
       PROFILE_DEFAULT_MODE_TOKENS_CONFIG PROFILE_DEFAULT_MODE_SYSTEM_TUNING \
       PROFILE_ZRAM_RECOMMEND PROFILE_PYTHON_MIN PROFILE_PYTHON_PREFERRED \
       PROFILE_PKG_MANAGERS PROFILE_GIT_CLONE_DEPTH PROFILE_INSTALL_DEV_DEPS \
       PROFILE_MUSL_COMPAT PROFILE_INIT_SYSTEM PROFILE_REQUIRE_BASH_INSTALL \
       PROFILE_CTX_PROFILE PROFILE_NOTES
