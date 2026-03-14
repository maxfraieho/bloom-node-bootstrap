#!/usr/bin/env bash
# profiles/cloud-micro.sh
# Profile for cloud micro instances with <1GB RAM.
# Target: t3.nano, t4g.nano, DigitalOcean 512MB, Hetzner CX11, etc.
# Strategy: no swap needed (EBS/cloud handles it), fast network available,
#           full clones OK, minimal footprint preferred.

PROFILE_NAME="cloud-micro"
PROFILE_DESC="Cloud micro instance with <1GB RAM (t3.nano, DO 512MB, Hetzner CX11)"

# Cloud CPU is often shared/burstable — don't overwhelm it
PROFILE_MAX_PARALLEL=1

# Cloud instances often run without swap by default
PROFILE_SKIP_SWAP_CHECK=true
PROFILE_MIN_FREE_RAM_MB=128

PROFILE_COMPONENTS="cgc chub workflow hooks tokens-config"

PROFILE_DEFAULT_MODE_CGC="install"
PROFILE_DEFAULT_MODE_CHUB="install"
PROFILE_DEFAULT_MODE_WORKFLOW="install"
PROFILE_DEFAULT_MODE_HOOKS="install"
PROFILE_DEFAULT_MODE_TOKENS_CONFIG="reuse"
PROFILE_DEFAULT_MODE_SYSTEM_TUNING="skip"

# No zram in cloud VMs — memory is managed by hypervisor
PROFILE_ZRAM_RECOMMEND=false

PROFILE_PYTHON_MIN="3.8"
PROFILE_PYTHON_PREFERRED="3.11"

# Cloud instances run various distros
PROFILE_PKG_MANAGERS="apt-get dnf yum apk"

# Fast network in cloud — full clones are fine; save time with shallow
PROFILE_GIT_CLONE_DEPTH=1

# Skip optional deps — keep footprint small
PROFILE_INSTALL_DEV_DEPS=false

# Cloud: systemd is almost always available
PROFILE_INIT_SYSTEM="systemd"

# Cloud instances often have tmpfs for /tmp — use it for temp work
PROFILE_USE_TMPFS_WORK=true

PROFILE_NOTES="Cloud micro instance detected (<1GB RAM). Network is fast; shallow clones enabled. System-tuning skipped — cloud hypervisor manages resources. If you need more RAM, consider upgrading to the next instance tier before installing heavy components."

# ctx context profile: default (cloud instances use general-purpose workflow)
PROFILE_CTX_PROFILE="default"

export PROFILE_NAME PROFILE_DESC PROFILE_MAX_PARALLEL PROFILE_SKIP_SWAP_CHECK \
       PROFILE_MIN_FREE_RAM_MB PROFILE_COMPONENTS \
       PROFILE_DEFAULT_MODE_CGC PROFILE_DEFAULT_MODE_CHUB \
       PROFILE_DEFAULT_MODE_WORKFLOW PROFILE_DEFAULT_MODE_HOOKS \
       PROFILE_DEFAULT_MODE_TOKENS_CONFIG PROFILE_DEFAULT_MODE_SYSTEM_TUNING \
       PROFILE_ZRAM_RECOMMEND PROFILE_PYTHON_MIN PROFILE_PYTHON_PREFERRED \
       PROFILE_PKG_MANAGERS PROFILE_GIT_CLONE_DEPTH PROFILE_INSTALL_DEV_DEPS \
       PROFILE_INIT_SYSTEM PROFILE_USE_TMPFS_WORK \
       PROFILE_CTX_PROFILE PROFILE_NOTES
