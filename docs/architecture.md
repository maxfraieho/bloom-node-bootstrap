# Architecture

## Why a Separate Repo

bloom-node-bootstrap is intentionally decoupled from the tools it installs (cgc, chub, workflow, hooks). This separation provides:

- **Bootstrap independence**: The installer can be updated without touching the installed stack.
- **Idempotent re-entry**: Re-running bootstrap on an already-configured node is always safe.
- **Clean audit surface**: Security review of "what ran during setup" is limited to this repo.
- **Multi-node parity**: The same bootstrap repo can configure a fleet of heterogeneous nodes from a single source.

## Component-Based Design

Each installable unit is a **component**: a named directory under `components/` with three scripts:

```
components/COMPONENT/
    detect.sh   — read current state, output status vars
    install.sh  — apply changes (MODE-aware)
    verify.sh   — assert post-install health (exit 0/1/2)
```

Components are independent. They communicate only through:
- The state store (`~/.bloom-node-state`)
- Exported environment variables from detect

This means you can install, verify, or re-run any single component without touching others.

### Adding a New Component

1. Create `components/mycomp/`
2. Write `detect.sh`: set `MYCOMP_STATUS` (missing/ours-healthy/ours-broken/foreign/partial) and export detection vars. Print `KEY=VALUE` lines to stdout.
3. Write `install.sh`: implement all six modes. Export a function `bloom_install_mycomp()`.
4. Write `verify.sh`: exit 0=OK, 1=WARN, 2=FAIL. Export a function `bloom_verify_mycomp()`.
5. Add `MYCOMP` to `PROFILE_COMPONENTS` in the relevant profiles.
6. Add a `PROFILE_DEFAULT_MODE_MYCOMP` var to each profile.

## Profile System

A **profile** is a shell file in `profiles/` that exports variables controlling installer behavior for a specific machine class. Profiles drive:

- Which components are installed (`PROFILE_COMPONENTS`)
- What mode each component uses (`PROFILE_DEFAULT_MODE_*`)
- Resource constraints (`PROFILE_MAX_PARALLEL`, `PROFILE_GIT_CLONE_DEPTH`)
- Hardware-specific settings (`PROFILE_ZRAM_RECOMMEND`, `PROFILE_PKG_MANAGERS`)

Profile selection is automatic via `bootstrap/profile-resolver.sh`, which inspects CPU architecture, RAM, distro, and cloud markers. The user can override with `--profile PROFILE_NAME`.

### Adding a New Profile

1. Create `profiles/myprofile.sh`
2. Set all required `PROFILE_*` vars (copy from `generic-safe.sh` as template)
3. Add detection logic to `bootstrap/profile-resolver.sh`'s `resolve_profile()` function

## Install Modes

Each component supports five install modes, allowing the installer to coexist with pre-existing tools:

| Mode | Description |
|------|-------------|
| `install` | Fresh installation: clone + setup |
| `reuse` | Accept existing install, register in state, skip install |
| `wrap` | Leave existing install in place, add a thin bloom shim/layer on top |
| `replace` | Backup existing, install ours |
| `side-by-side` | Install under a different name/path alongside existing |
| `skip` | Do nothing, record skip decision |

Mode is selected per component by the profile, then potentially overridden by detect status (e.g., if detect says `ours-healthy`, mode becomes `reuse` regardless of profile).

The user can force a mode globally with `--mode MODE`.

## State Store

Persistent state lives in `~/.bloom-node-state` (plain key=value file). It tracks:

- Which components are installed, at what version, in what mode
- When they were installed
- Skip decisions and reasons

The state store is append-and-replace (never accumulates duplicates). It is never consulted for correctness — detect.sh always reads live system state. The store is used for: auditing, plan generation, and remembering explicit user decisions (skip).

## Pipeline: detect → profile → plan → apply → verify

```
install.sh --apply
    │
    ├─ detect.sh          # snapshot system state → env vars
    │
    ├─ profile-resolver   # arch + RAM + distro → profile name
    │
    ├─ source_profile     # load profile vars
    │
    ├─ for each component:
    │       detect.sh     # current component status
    │       install.sh    # apply chosen mode
    │       verify.sh     # assert health
    │
    └─ state_set          # record results
```

`--plan` runs detect + profile resolution + per-component detect, then prints the table without applying.

`--dry-run` runs the full pipeline including install scripts, but `run_cmd` prints commands instead of executing them.

## Security Considerations

- Token values are **never** logged, printed, or stored in the state file.
- `tokens-config` only creates scaffold files with placeholders; the user fills in API keys.
- `rm -rf` is never called without explicit user confirmation.
- The state file (`~/.bloom-node-state`) does not contain secrets.
- All installed scripts are reviewed before execution (git clone, not curl-pipe).
