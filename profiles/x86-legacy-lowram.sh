#!/usr/bin/env bash
# profiles/x86-legacy-lowram.sh
# Profile for x86_64 machines with less than 2GB RAM.
# Target: old laptops, netbooks, second-hand desktops running Ubuntu/Debian.
# Strategy: shallow clones, skip optional components, moderate parallelism.

PROFILE_NAME="x86-legacy-lowram"
PROFILE_DESC="x86_64 machine with <2GB RAM (old laptops, netbooks, legacy desktops)"

# Allow 2 parallel operations — x86 has better RAM management than ARM
PROFILE_MAX_PARALLEL=2

PROFILE_SKIP_SWAP_CHECK=false
PROFILE_MIN_FREE_RAM_MB=256

# All main components; skip system-tuning by default (user manages their own system)
PROFILE_COMPONENTS="cgc chub workflow hooks tokens-config"

PROFILE_DEFAULT_MODE_CGC="install"
PROFILE_DEFAULT_MODE_CHUB="install"
PROFILE_DEFAULT_MODE_WORKFLOW="install"
PROFILE_DEFAULT_MODE_HOOKS="install"
PROFILE_DEFAULT_MODE_TOKENS_CONFIG="reuse"
PROFILE_DEFAULT_MODE_SYSTEM_TUNING="skip"

# zram is helpful but not critical if swap exists
PROFILE_ZRAM_RECOMMEND=true
PROFILE_ZRAM_SIZE_MB=512

PROFILE_PYTHON_MIN="3.8"
PROFILE_PYTHON_PREFERRED="3.10"

# Likely running Debian/Ubuntu on old hardware
PROFILE_PKG_MANAGERS="apt-get"

# Shallow clones to keep disk I/O low on spinning HDDs
PROFILE_GIT_CLONE_DEPTH=1

# Skip heavy dev deps to keep install fast
PROFILE_INSTALL_DEV_DEPS=false

# x86-specific: check for 32-bit system (i686) and warn
PROFILE_WARN_IF_32BIT=true

PROFILE_NOTES="Old x86 machine detected with <2GB RAM. Shallow git clones are enabled. If running on a spinning HDD, expect slow clone times. Consider adding a swapfile if none exists: 'sudo fallocate -l 1G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile'."

# ctx context profile: rpi boosts debugging/bootstrap/recovery skills for constrained hardware
PROFILE_CTX_PROFILE="rpi"

export PROFILE_NAME PROFILE_DESC PROFILE_MAX_PARALLEL PROFILE_SKIP_SWAP_CHECK \
       PROFILE_MIN_FREE_RAM_MB PROFILE_COMPONENTS \
       PROFILE_DEFAULT_MODE_CGC PROFILE_DEFAULT_MODE_CHUB \
       PROFILE_DEFAULT_MODE_WORKFLOW PROFILE_DEFAULT_MODE_HOOKS \
       PROFILE_DEFAULT_MODE_TOKENS_CONFIG PROFILE_DEFAULT_MODE_SYSTEM_TUNING \
       PROFILE_ZRAM_RECOMMEND PROFILE_ZRAM_SIZE_MB \
       PROFILE_PYTHON_MIN PROFILE_PYTHON_PREFERRED \
       PROFILE_PKG_MANAGERS PROFILE_GIT_CLONE_DEPTH PROFILE_INSTALL_DEV_DEPS \
       PROFILE_WARN_IF_32BIT PROFILE_CTX_PROFILE PROFILE_NOTES
