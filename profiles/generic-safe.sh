#!/usr/bin/env bash
# profiles/generic-safe.sh
# Fallback profile for any unrecognized machine.
# Conservative defaults: install all components, no aggressive tuning.

PROFILE_NAME="generic-safe"
PROFILE_DESC="Generic fallback profile — safe defaults for unrecognized hardware"

# Parallelism: allow up to 2 concurrent operations on unknown hardware
PROFILE_MAX_PARALLEL=2

# RAM / swap
PROFILE_SKIP_SWAP_CHECK=false
PROFILE_MIN_FREE_RAM_MB=256

# Components to install (space-separated, in order)
PROFILE_COMPONENTS="cgc chub workflow hooks tokens-config"

# Default install mode per component
# Values: install | reuse | wrap | replace | side-by-side | skip
PROFILE_DEFAULT_MODE_CGC="install"
PROFILE_DEFAULT_MODE_CHUB="install"
PROFILE_DEFAULT_MODE_WORKFLOW="install"
PROFILE_DEFAULT_MODE_HOOKS="install"
PROFILE_DEFAULT_MODE_TOKENS_CONFIG="reuse"
PROFILE_DEFAULT_MODE_SYSTEM_TUNING="skip"

# zram: don't recommend unless we know RAM is tight
PROFILE_ZRAM_RECOMMEND=false

# Python requirements
PROFILE_PYTHON_MIN="3.8"
PROFILE_PYTHON_PREFERRED="3.10"

# Accepted package managers
PROFILE_PKG_MANAGERS="apt-get apk dnf yum pacman"

# Git clone depth (use 1 for shallow on resource-constrained machines)
PROFILE_GIT_CLONE_DEPTH=0   # 0 = full clone

# Whether to install optional dev dependencies
PROFILE_INSTALL_DEV_DEPS=true

# Notes shown to user before install
PROFILE_NOTES="Generic profile — all components will be installed with default settings. Re-run with --detect to see a more specific profile."

export PROFILE_NAME PROFILE_DESC PROFILE_MAX_PARALLEL PROFILE_SKIP_SWAP_CHECK \
       PROFILE_MIN_FREE_RAM_MB PROFILE_COMPONENTS \
       PROFILE_DEFAULT_MODE_CGC PROFILE_DEFAULT_MODE_CHUB \
       PROFILE_DEFAULT_MODE_WORKFLOW PROFILE_DEFAULT_MODE_HOOKS \
       PROFILE_DEFAULT_MODE_TOKENS_CONFIG PROFILE_DEFAULT_MODE_SYSTEM_TUNING \
       PROFILE_ZRAM_RECOMMEND PROFILE_PYTHON_MIN PROFILE_PYTHON_PREFERRED \
       PROFILE_PKG_MANAGERS PROFILE_GIT_CLONE_DEPTH PROFILE_INSTALL_DEV_DEPS \
       PROFILE_NOTES
