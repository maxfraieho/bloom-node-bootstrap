#!/usr/bin/env bash
# profiles/arm-sbc.sh
# Profile for ARM single-board computers that are NOT Raspberry Pi.
# Target: Orange Pi, Odroid, Banana Pi, Rock Pi, Libre Computer, etc.
# These typically have 1-4GB RAM and run Armbian or vendor-specific Debian/Ubuntu.

PROFILE_NAME="arm-sbc"
PROFILE_DESC="ARM SBC (non-RPi): Orange Pi, Odroid, Banana Pi, Rock Pi, Libre Computer"

# Allow 2 parallel on SBCs with 1GB+ RAM
PROFILE_MAX_PARALLEL=2

PROFILE_SKIP_SWAP_CHECK=false
PROFILE_MIN_FREE_RAM_MB=256

PROFILE_COMPONENTS="system-tuning cgc chub workflow hooks tokens-config"

PROFILE_DEFAULT_MODE_CGC="install"
PROFILE_DEFAULT_MODE_CHUB="install"
PROFILE_DEFAULT_MODE_WORKFLOW="install"
PROFILE_DEFAULT_MODE_HOOKS="install"
PROFILE_DEFAULT_MODE_TOKENS_CONFIG="reuse"
PROFILE_DEFAULT_MODE_SYSTEM_TUNING="install"

# Recommend zram on SBCs — SD/eMMC swap is slow and wears media
PROFILE_ZRAM_RECOMMEND=true
PROFILE_ZRAM_SIZE_MB=512

PROFILE_PYTHON_MIN="3.8"
PROFILE_PYTHON_PREFERRED="3.10"

# Armbian ships as Debian/Ubuntu; some SBCs use Manjaro ARM or Arch ARM
PROFILE_PKG_MANAGERS="apt-get pacman"

# Shallow clones to save SD card writes
PROFILE_GIT_CLONE_DEPTH=1

PROFILE_INSTALL_DEV_DEPS=true   # SBCs with 2GB+ can handle it

# SBC-specific: avoid writing excessively to SD/eMMC
PROFILE_MINIMIZE_WRITES=true

# Some SBCs have hardware GPIO — preserve config
PROFILE_PRESERVE_GPIO_CONFIG=true

PROFILE_NOTES="ARM SBC detected (non-Raspberry Pi). Using Armbian-compatible defaults. zram is recommended over SD card swap. If running from SD card, enable log2ram or similar to reduce write cycles. Check vendor kernel for any quirks."

# ctx context profile: rpi boosts debugging/bootstrap/recovery skills (1.3-1.5x)
PROFILE_CTX_PROFILE="rpi"

export PROFILE_NAME PROFILE_DESC PROFILE_MAX_PARALLEL PROFILE_SKIP_SWAP_CHECK \
       PROFILE_MIN_FREE_RAM_MB PROFILE_COMPONENTS \
       PROFILE_DEFAULT_MODE_CGC PROFILE_DEFAULT_MODE_CHUB \
       PROFILE_DEFAULT_MODE_WORKFLOW PROFILE_DEFAULT_MODE_HOOKS \
       PROFILE_DEFAULT_MODE_TOKENS_CONFIG PROFILE_DEFAULT_MODE_SYSTEM_TUNING \
       PROFILE_ZRAM_RECOMMEND PROFILE_ZRAM_SIZE_MB \
       PROFILE_PYTHON_MIN PROFILE_PYTHON_PREFERRED \
       PROFILE_PKG_MANAGERS PROFILE_GIT_CLONE_DEPTH PROFILE_INSTALL_DEV_DEPS \
       PROFILE_MINIMIZE_WRITES PROFILE_PRESERVE_GPIO_CONFIG \
       PROFILE_CTX_PROFILE PROFILE_NOTES
