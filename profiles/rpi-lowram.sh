#!/usr/bin/env bash
# profiles/rpi-lowram.sh
# Profile for Raspberry Pi with less than 1GB RAM (Pi Zero, Pi 1, Pi 2, Pi 3 with 512MB).
# Priorities: minimize RAM usage, use shallow clones, enable zram, skip heavy deps.

PROFILE_NAME="rpi-lowram"
PROFILE_DESC="Raspberry Pi with <1GB RAM (Pi Zero / Pi 1 / Pi 2 / Pi 3 512MB)"

# Single-threaded — don't thrash on low-RAM ARM
PROFILE_MAX_PARALLEL=1

# Warn if swap is missing — critical on RPi with 512MB
PROFILE_SKIP_SWAP_CHECK=false
PROFILE_MIN_FREE_RAM_MB=128

# Components (exclude system-tuning from default — handled separately)
PROFILE_COMPONENTS="system-tuning cgc chub workflow hooks tokens-config"

# Install modes
PROFILE_DEFAULT_MODE_CGC="install"
PROFILE_DEFAULT_MODE_CHUB="install"
PROFILE_DEFAULT_MODE_WORKFLOW="install"
PROFILE_DEFAULT_MODE_HOOKS="install"
PROFILE_DEFAULT_MODE_TOKENS_CONFIG="reuse"
PROFILE_DEFAULT_MODE_SYSTEM_TUNING="install"

# Strongly recommend zram on RPi < 1GB
PROFILE_ZRAM_RECOMMEND=true
PROFILE_ZRAM_SIZE_MB=256

# Python — 3.9 available on RPi OS (Bullseye), 3.8 on Buster
PROFILE_PYTHON_MIN="3.8"
PROFILE_PYTHON_PREFERRED="3.9"

# RPi uses apt
PROFILE_PKG_MANAGERS="apt-get"

# Shallow clones save time and disk on SD cards
PROFILE_GIT_CLONE_DEPTH=1

# Skip optional dev deps to keep RAM free during install
PROFILE_INSTALL_DEV_DEPS=false

# RPi-specific tuning flags
PROFILE_DISABLE_MANDB=true          # mandb update is slow and RAM-hungry
PROFILE_DISABLE_TRIGGERHAPPY=false  # keep for GPIO usage
PROFILE_REDUCE_GPU_MEM=true         # gpu_mem=16 in /boot/config.txt if headless

PROFILE_NOTES="Enable zram before installing on Pi with 512MB RAM. Use 'raspi-config' to set GPU memory to 16MB if running headless. Avoid npm build steps — prefer pre-built binaries. Run one component at a time."

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
       PROFILE_DISABLE_MANDB PROFILE_DISABLE_TRIGGERHAPPY PROFILE_REDUCE_GPU_MEM \
       PROFILE_CTX_PROFILE PROFILE_NOTES
