# bloom-node-bootstrap

A component-based adaptive installer for deploying a lightweight dev stack on heterogeneous low-resource Linux nodes: Raspberry Pi, old x86 laptops, Alpine micro nodes, and ARM SBCs.

Installs and manages: **cgc**, **chub**, **workflow**, **hooks**, **system-tuning**, **tokens-config**.

## Design Principles

- **Shell-first** — POSIX sh where possible, bash where needed
- **Idempotent** — safe to re-run at any time
- **Component-based** — each tool has its own detect/install/verify
- **Profile-based** — machine class drives decisions (RAM, arch, distro)
- **State-preserving** — never destroys tokens, configs, hooks, or skills
- **Five install modes** per component: `reuse` / `wrap` / `replace` / `side-by-side` / `skip`

## Quick Start

```bash
# Clone
git clone https://github.com/vokov/bloom-node-bootstrap
cd bloom-node-bootstrap

# See what's on this machine
./install.sh --detect

# See the install plan (no changes made)
./install.sh --plan

# Apply with dry-run first
./install.sh --apply --dry-run

# Actually install
./install.sh --apply
```

## Supported Hardware

| Device | RAM | Profile |
|--------|-----|---------|
| Raspberry Pi Zero / 1 / 2 / 3 | 512 MB – 1 GB | `rpi-lowram` |
| Orange Pi, Odroid, Banana Pi, Rock Pi | 1–4 GB | `arm-sbc` |
| Old x86 laptops / netbooks | < 2 GB | `x86-legacy-lowram` |
| Alpine Linux containers | any | `x86-alpine-minimal` |
| Cloud micro instances (t3.nano, DO 512MB) | < 1 GB | `cloud-micro` |
| Everything else | any | `generic-safe` |

Full matrix: [docs/supported-systems.md](docs/supported-systems.md)

## Components

| Component | Description |
|-----------|-------------|
| `cgc` | Claude git CLI optimized for low-RAM nodes |
| `chub` | Context hub — manages Claude context across sessions |
| `workflow` | claude-codex-workflow: CLAUDE.md, hooks, and skill scaffolding |
| `hooks` | Claude Code lifecycle hooks (~/.claude/hooks/) |
| `system-tuning` | zram, swappiness, swap setup for resource-constrained nodes |
| `tokens-config` | API key configuration scaffold (never stores values) |

## Install Modes

Each component can be installed in one of five modes:

| Mode | When to Use |
|------|-------------|
| `install` | Fresh install, nothing there yet |
| `reuse` | Already installed — just register it |
| `wrap` | Foreign install exists — add bloom layer on top |
| `replace` | Full takeover with backup of existing |
| `side-by-side` | Coexist with existing under a different name |
| `skip` | Explicitly opt out, remember this decision |

See [docs/migration.md](docs/migration.md) for detailed mode guidance.

## Usage

```
install.sh [OPTIONS]

Pipeline Modes:
  --detect              Run system detection and print results
  --plan                Show what would be installed and how
  --apply               Execute the full install pipeline  [DEFAULT]
  --verify              Run component verification
  --doctor              Run full health check report

Targeting:
  --component COMP      Operate on one component only
  --profile PROFILE     Override auto-resolved profile
  --mode MODE           Override install mode for all components

Behavior:
  --dry-run             Print actions without executing them
  --yes                 Assume yes to all interactive prompts
  --log-level LEVEL     debug | info | warn | error
```

## Examples

```bash
# Full install with auto-detection
./install.sh --apply

# Install only cgc, forcing replace mode
./install.sh --apply --component cgc --mode replace

# Install on Raspberry Pi with explicit profile
./install.sh --apply --profile rpi-lowram

# Verify all components
./install.sh --verify

# Health check
./doctor.sh

# Just detect (no changes)
./detect.sh

# See the plan for an rpi-lowram install
./plan.sh --profile rpi-lowram
```

## Profiles

Auto-detected from system properties. Override with `--profile NAME`.

```bash
# List available profiles
ls profiles/

# See profile details
cat profiles/rpi-lowram.sh
```

Full profile docs: [docs/profiles.md](docs/profiles.md)

## Architecture

The pipeline:
```
detect → profile-resolve → plan → [apply per component] → verify
```

Each component is a directory with three scripts:
```
components/COMPONENT/
    detect.sh   → current state (missing/ours-healthy/foreign/...)
    install.sh  → apply chosen mode
    verify.sh   → assert health (exit 0/1/2)
```

Full architecture docs: [docs/architecture.md](docs/architecture.md)

## State

Install decisions are tracked in `~/.bloom-node-state` (plain key=value). The state file does not contain secrets.

```bash
# View state
sort ~/.bloom-node-state

# Or via API
source bootstrap/state-store.sh
state_dump
```

State schema: [state/schema.md](state/schema.md)

## Prerequisites

- bash 4.0+
- git 2.0+
- python3 3.8+ (for some components)
- Internet access (for git clones)
- `~/.local/bin` in your PATH (installer adds it if missing)

On Alpine:
```bash
apk add bash git python3
```

## Security Notes

- Token values are **never** logged, stored in state, or printed
- No `rm -rf` without explicit confirmation
- All code is cloned from git (no curl-pipe)
- Components verify themselves post-install

## License

MIT
