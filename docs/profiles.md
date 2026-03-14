# Profiles

Profiles drive install decisions for specific machine classes. The installer auto-detects the best profile, but you can override with `--profile NAME`.

## Profile Summary Table

| Profile | Target Hardware | RAM Threshold | CPU Arch | Distro | Max Parallel | zram | Git Depth | Dev Deps |
|---------|----------------|--------------|----------|--------|-------------|------|-----------|----------|
| `rpi-lowram` | Raspberry Pi (Zero, 1, 2, 3/512MB) | < 1 GB | armv6/armv7/armv8 | Raspberry Pi OS | 1 | recommended | shallow (1) | no |
| `arm-sbc` | Orange Pi, Odroid, Banana Pi, Rock Pi | ≥ 1 GB | armv7/armv8 | Armbian / Manjaro ARM | 2 | recommended | shallow (1) | yes |
| `x86-legacy-lowram` | Old laptops, netbooks, legacy desktops | < 2 GB | x86_64 | Ubuntu / Debian | 2 | optional | shallow (1) | no |
| `x86-alpine-minimal` | Containers, diskless servers, minimal VMs | any | x86_64 | Alpine Linux | 1 | no | shallow (1) | no |
| `cloud-micro` | t3.nano, DO 512MB, Hetzner CX11 | < 1 GB | any | any | 1 | no | shallow (1) | no |
| `generic-safe` | Unrecognized / development machines | any | any | any | 2 | no | full | yes |

## Profile Details

### `rpi-lowram`
**Target**: Raspberry Pi Zero, Pi 1, Pi 2, Pi 3 with 512MB RAM, running Raspberry Pi OS (Debian-based).

**Key settings**:
- Single-threaded install (`PROFILE_MAX_PARALLEL=1`) to avoid OOM
- Strongly recommends enabling zram (256MB compressed swap) before starting
- Shallow git clones to reduce SD card I/O
- Skips optional dev dependencies
- Includes `system-tuning` component to apply zram + swappiness tuning
- Package manager: `apt-get` only

**Before installing**:
```bash
# Enable zram (if not already)
sudo apt-get install -y zram-tools
echo "PERCENT=50" | sudo tee -a /etc/default/zramswap
sudo systemctl restart zramswap

# Optional: reduce GPU memory if headless
sudo raspi-config nonint do_memory_split 16
```

---

### `arm-sbc`
**Target**: ARM single-board computers that are not Raspberry Pi — Orange Pi, Odroid, Banana Pi, Rock Pi, Libre Computer boards. Typically 1–4 GB RAM running Armbian.

**Key settings**:
- 2 parallel workers (more RAM available)
- zram recommended (SD/eMMC swap wears flash)
- Includes `system-tuning`
- Minimizes unnecessary writes to protect flash storage

**Notes**: Check your vendor's kernel for hardware-specific quirks. Armbian boards may have different boot configurations.

---

### `x86-legacy-lowram`
**Target**: x86_64 machines with less than 2 GB RAM — old laptops (netbooks, Thinkpad X200 era), second-hand desktops.

**Key settings**:
- 2 parallel workers (x86 memory management is better than ARM)
- Shallow clones to reduce I/O on spinning HDDs
- zram recommended if no swap exists
- Package manager: `apt-get`

**Before installing on HDD systems**:
```bash
# Add swapfile if none exists
sudo fallocate -l 1G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

---

### `x86-alpine-minimal`
**Target**: Alpine Linux on x86_64 — Docker containers, diskless servers, minimal VMs.

**Key settings**:
- Single-threaded (container CPU is often limited)
- No swap check (containers rarely have swap configured)
- No zram (hypervisor manages memory)
- musl libc compatibility flag set (affects Python wheel builds)
- Package manager: `apk` only

**Before installing**:
```bash
# Alpine doesn't have bash or git by default
apk add bash git python3 py3-pip
```

**musl notes**: Some Python packages with C extensions need compilation on Alpine:
```bash
apk add build-base python3-dev libffi-dev
```

---

### `cloud-micro`
**Target**: Cloud instances with less than 1 GB RAM — AWS t3.nano, t4g.nano, DigitalOcean 512MB Droplet, Hetzner CX11, Oracle free tier.

**Key settings**:
- Single-threaded (burstable CPU, don't burn credits)
- Swap check skipped (cloud manages memory at hypervisor level)
- No zram (not appropriate in VMs)
- System tuning skipped (cloud hypervisor handles it)
- Shallow clones (network is fast but RAM is tight)

**Notes**: If you need more headroom, upgrade to the next instance tier before installing. The t3.micro (1 GB) or equivalent is a more comfortable target.

---

### `generic-safe`
**Target**: Any unrecognized system — development machines, servers with > 2 GB RAM, machines that don't match other profiles.

**Key settings**:
- 2 parallel workers
- Full git clones
- Dev deps included
- No system tuning (assume user manages their own system)
- All package managers accepted

**Notes**: This is the fallback profile. If you're on an explicitly unsupported system, this installs everything with safe defaults.

## Profile Resolution Logic

Resolution runs in priority order:

1. Is it a Raspberry Pi? → `rpi-lowram`
2. Alpine Linux on x86_64? → `x86-alpine-minimal`
3. x86_64 with RAM < 2 GB? → `x86-legacy-lowram`
4. Cloud environment with RAM < 1 GB? → `cloud-micro`
5. ARM (non-RPi)? → `arm-sbc`
6. Everything else → `generic-safe`

Override: `./install.sh --profile rpi-lowram`
