# Supported Systems

## Device Support Matrix

| Device | Arch | Distro | RAM | Profile | Status | Notes |
|--------|------|--------|-----|---------|--------|-------|
| Raspberry Pi Zero / Zero 2 W | armv6 / armv8 | Raspberry Pi OS Lite | 512 MB | `rpi-lowram` | tested | zram required; Pi Zero (v1) is very slow |
| Raspberry Pi 1 Model B+ | armv6 | Raspberry Pi OS Lite | 512 MB | `rpi-lowram` | expected | Same as Zero; shallow clones essential |
| Raspberry Pi 2 Model B | armv7 | Raspberry Pi OS Lite | 1 GB | `rpi-lowram` | tested | Comfortable with zram |
| Raspberry Pi 3 Model B / B+ | armv8 | Raspberry Pi OS Lite | 1 GB | `rpi-lowram` | tested | Works well; enable zram for headroom |
| Raspberry Pi 4 Model B | armv8 | Raspberry Pi OS | 2–8 GB | `generic-safe` | tested | 2 GB RAM → comfortable; full install |
| Raspberry Pi 5 | armv8 | Raspberry Pi OS | 4–8 GB | `generic-safe` | expected | Should work identically to Pi 4 |
| Orange Pi Zero 3 | armv8 (Cortex-A53) | Armbian Bookworm | 1–4 GB | `arm-sbc` | tested | Armbian apt-based; zram recommended |
| Orange Pi 5 | armv8 (Cortex-A76) | Armbian Bookworm | 4–16 GB | `generic-safe` | expected | Fast enough for full install |
| Odroid XU4 | armv7 (big.LITTLE) | Armbian | 2 GB | `arm-sbc` | expected | USB3 boot recommended over SD |
| Odroid HC4 | armv8 | Armbian | 4 GB | `arm-sbc` | expected | NAS target; SATA is fast |
| Banana Pi M5 | armv8 | Armbian | 4 GB | `arm-sbc` | untested | Should work with arm-sbc profile |
| Rock Pi 4 | armv8 | Armbian | 2–4 GB | `arm-sbc` | untested | |
| Libre Computer AML-S905X-CC (Le Potato) | armv8 | Raspbian / Armbian | 2 GB | `arm-sbc` | expected | apt-based |
| Beaglebone Black | armv7 | Debian | 512 MB | `rpi-lowram` | untested | Very slow eMMC; patience required |
| ThinkPad X220 (old laptop) | x86_64 | Ubuntu 22.04 | 4–8 GB | `generic-safe` | tested | HDD: use shallow clones |
| ThinkPad X200 (old laptop) | x86_64 | Debian 12 | 2 GB | `x86-legacy-lowram` | tested | Add swapfile before install |
| Netbook (Atom N450) | x86 | Ubuntu 20.04 | 1 GB | `x86-legacy-lowram` | expected | 32-bit may need special handling |
| Acer Aspire One | x86_64 | Lubuntu 22.04 | 2 GB | `x86-legacy-lowram` | untested | SSD preferred |
| AWS t3.nano | x86_64 | Ubuntu 22.04 | 512 MB | `cloud-micro` | tested | Works; tight on RAM during git clone |
| AWS t4g.nano | armv8 | Ubuntu 22.04 | 512 MB | `cloud-micro` | tested | Graviton2; ARM cloud-micro |
| AWS t3.micro | x86_64 | Ubuntu 22.04 | 1 GB | `cloud-micro` | tested | Comfortable target |
| DigitalOcean Droplet 512MB | x86_64 | Ubuntu 22.04 | 512 MB | `cloud-micro` | tested | |
| Hetzner CX11 | x86_64 | Ubuntu 22.04 | 2 GB | `generic-safe` | tested | Good value; enough RAM |
| Oracle Cloud A1 (free tier) | armv8 | Ubuntu 22.04 | 1–24 GB | `arm-sbc` / `generic-safe` | expected | Ampere Altra ARM; fast |
| Alpine Linux container (Docker) | x86_64 | Alpine 3.18+ | any | `x86-alpine-minimal` | tested | Requires: `apk add bash git python3` |
| Debian container (Docker) | x86_64 | Debian 12 | any | `generic-safe` | tested | Full install works |
| VirtualBox VM | x86_64 | Ubuntu 22.04 | ≥ 1 GB | `generic-safe` | tested | Development/testing |

## Status Definitions

| Status | Meaning |
|--------|---------|
| **tested** | Installed and verified on real hardware/VM |
| **expected** | Similar enough to a tested system that it should work |
| **untested** | Theoretically compatible but not verified |

## OS/Distro Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| Bash | 4.0 | 5.0+ |
| Git | 2.0 | 2.30+ |
| Python | 3.8 | 3.10+ |
| OpenSSL | 1.1 | 3.0+ |
| cURL or wget | any | any |
| Disk free (home) | 500 MB | 2 GB |
| RAM (available during install) | 128 MB | 512 MB |

## Known Limitations

### Raspberry Pi Zero v1 (armv6)
The original Pi Zero with armv6 is extremely slow for git operations. Shallow clones (`--depth=1`) are mandatory. Expect 5–15 minutes for a full install.

### Alpine Linux (musl libc)
Some Python packages with C extensions do not have pre-built wheels for musl. You may need `apk add build-base python3-dev` to compile from source. The `x86-alpine-minimal` profile skips packages that commonly fail on musl.

### 32-bit x86 (i686)
Partially supported via the `x86-legacy-lowram` profile. The `PROFILE_WARN_IF_32BIT=true` flag triggers a warning. Some components may not provide 32-bit binaries.

### Systems Without `apt`/`apk`
Profiles `rpi-lowram`, `x86-legacy-lowram`, and `x86-alpine-minimal` assume specific package managers. On Arch ARM or Manjaro ARM, use the `arm-sbc` profile which accepts `pacman` as an alternative.

### ARM64 macOS (Apple Silicon)
Not a target — this tool is for Linux nodes. macOS lacks `/proc/meminfo`, `/etc/os-release`, and the init system checks. Use native macOS tooling.

## Tested Configurations (Reference)

The following combinations were used during initial development and testing:

1. Raspberry Pi 3B+ / 1 GB RAM / Raspberry Pi OS Lite Bullseye / micro-SD
2. Orange Pi Zero 3 / 1 GB RAM / Armbian Bookworm minimal
3. AWS t3.nano / 512 MB / Ubuntu 22.04 LTS
4. Alpine 3.18 Docker container on x86_64 Linux host
5. ThinkPad X200s / 2 GB RAM / Debian 12 Bookworm / HDD
6. VirtualBox Ubuntu 22.04 VM / 1 GB RAM (x86-legacy-lowram validation)
