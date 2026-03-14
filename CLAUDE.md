# bloom-node-bootstrap

Adaptive installer for low-resource Linux nodes. Installs cgc + chub + workflow + hooks
via a profile-aware component system. Designed for machines with constrained RAM/storage
(Acer Aspire x86-legacy, Raspberry Pi, generic fallback).

---

## Key Commands

```bash
bash install.sh --detect                         # identify machine profile
bash install.sh --plan --profile PROFILE         # preview what will run
bash install.sh --dry-run --profile PROFILE      # full dry-run (no writes)
bash install.sh --apply --profile PROFILE --yes  # real install
bash install.sh --verify --component COMP        # verify one component
bash doctor.sh                                   # full health check
```

---

## Profile System

Profiles live in `profiles/`. Each profile is a shell fragment that sets component
selection and tuning variables.

| Profile | PROFILE_CTX_PROFILE | Targets |
|---------|--------------------|---------|
| `rpi-lowram` | `rpi` | Raspberry Pi, low-RAM nodes |
| `arm-sbc` | `rpi` | ARM SBCs (Orange Pi, Banana Pi) |
| `x86-legacy-lowram` | `rpi` | x86 nodes with low RAM |
| `cloud-micro` | `default` | Cloud micro VMs |
| `x86-alpine-minimal` | `default` | Minimal Alpine x86 |
| `generic-safe` | `default` | Default fallback profile |

`detect.sh` reads hardware and writes the detected profile to `state/profile`.

---

## Component Structure

Each component lives under `components/COMPONENT/`:

```
components/COMPONENT/
  detect.sh    # check if component is needed / already present
  install.sh   # perform installation
  verify.sh    # confirm component is healthy post-install
```

Components: `cgc`, `chub`, `workflow`, `hooks`, `system-tuning`, `tokens-config`.

---

## Workflow Source

The workflow component pulls from `WORKFLOW_REPO_URL`
(default: `https://github.com/maxfraieho/claude-codex-workflow`).
It installs to `~/.bloom/sources/claude-codex-workflow`.

After workflow install, activate with:

```bash
source ~/.bloom/env.sh
```

This exports `CTX_PROFILE` and makes `ctx skills` and `ctx context` available
for AI-assisted workflow integration.

---

## Engineering Tasks — Codex Gate

Before starting any task that modifies ≥2 components or ≥3 files with identical changes,
fill the gate template and dispatch Codex for eligible subtasks.
See: ~/.claude/skills/codex-usage-policy.md
