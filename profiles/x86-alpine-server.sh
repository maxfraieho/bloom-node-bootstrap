#!/usr/bin/env bash
# profiles/x86-alpine-server.sh
# Profile for a persistent Alpine Linux x86_64 server node.
# Target: AMD C-60 / similar low-power x86 APUs running Alpine with OpenRC.
# Strategy: full capability mode — not a container, not ephemeral.
#           shallow clones only to protect disk (constrained partition).
#           Memory layer (membridge/SQLite/MinIO) is external — reuse.

PROFILE_NAME="x86-alpine-server"
PROFILE_DESC="Alpine Linux x86_64 persistent server (AMD C-60 class, constrained disk)"

# 2 cores available, but I/O is the bottleneck on this class of hardware
PROFILE_MAX_PARALLEL=2

PROFILE_SKIP_SWAP_CHECK=false
PROFILE_MIN_FREE_RAM_MB=256

# All components active
PROFILE_COMPONENTS="cgc chub workflow hooks tokens-config system-tuning"

PROFILE_DEFAULT_MODE_CGC="install"
PROFILE_DEFAULT_MODE_CHUB="install"
PROFILE_DEFAULT_MODE_WORKFLOW="install"
PROFILE_DEFAULT_MODE_HOOKS="wrap"          # membridge hooks already present — wrap around them
PROFILE_DEFAULT_MODE_TOKENS_CONFIG="reuse"
PROFILE_DEFAULT_MODE_SYSTEM_TUNING="skip"  # user-managed OpenRC system

# zram not needed — plenty of swap (4GB)
PROFILE_ZRAM_RECOMMEND=false

PROFILE_PYTHON_MIN="3.10"
PROFILE_PYTHON_PREFERRED="3.12"

PROFILE_PKG_MANAGERS="apk"

# Disk is partitioned at 26G — use shallow clones to be safe
PROFILE_GIT_CLONE_DEPTH=1

# Alpine is a real server here — install dev deps where needed
PROFILE_INSTALL_DEV_DEPS=true

# musl libc — some wheels need build tools
PROFILE_MUSL_COMPAT=true

# OpenRC (not systemd, not a container)
PROFILE_INIT_SYSTEM="openrc"

PROFILE_REQUIRE_BASH_INSTALL=false  # bash is already installed

# Memory subsystem: reuse existing membridge + SQLite + MinIO
PROFILE_MEMORY_BACKEND="membridge"
PROFILE_MEMORY_DB_PATH="${HOME}/.claude-mem/claude-mem.db"
PROFILE_MEMORY_VECTOR_PATH="${HOME}/.claude-mem/vector-db"
PROFILE_MEMORY_AGENT_PORT="8001"

# ctx context profile: x86 server → default (not rpi constrained mode)
PROFILE_CTX_PROFILE="default"

PROFILE_NOTES="Alpine Linux x86_64 server on AMD C-60. Full capability mode. Shallow git clones enabled to protect disk quota. membridge memory layer is external — reuse mode. Ensure apk add bash git python3 build-base are present before component installs."

export PROFILE_NAME PROFILE_DESC PROFILE_MAX_PARALLEL PROFILE_SKIP_SWAP_CHECK \
       PROFILE_MIN_FREE_RAM_MB PROFILE_COMPONENTS \
       PROFILE_DEFAULT_MODE_CGC PROFILE_DEFAULT_MODE_CHUB \
       PROFILE_DEFAULT_MODE_WORKFLOW PROFILE_DEFAULT_MODE_HOOKS \
       PROFILE_DEFAULT_MODE_TOKENS_CONFIG PROFILE_DEFAULT_MODE_SYSTEM_TUNING \
       PROFILE_ZRAM_RECOMMEND PROFILE_PYTHON_MIN PROFILE_PYTHON_PREFERRED \
       PROFILE_PKG_MANAGERS PROFILE_GIT_CLONE_DEPTH PROFILE_INSTALL_DEV_DEPS \
       PROFILE_MUSL_COMPAT PROFILE_INIT_SYSTEM PROFILE_REQUIRE_BASH_INSTALL \
       PROFILE_MEMORY_BACKEND PROFILE_MEMORY_DB_PATH PROFILE_MEMORY_VECTOR_PATH \
       PROFILE_MEMORY_AGENT_PORT PROFILE_CTX_PROFILE PROFILE_NOTES
