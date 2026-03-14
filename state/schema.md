# State Store Schema

The state store is a plain-text key=value file at `~/.bloom-node-state` (path overridable via `BLOOM_STATE_FILE` env var).

## Format

```
KEY=VALUE
```

- One key per line
- No spaces around `=`
- Values may contain spaces (but not newlines)
- Keys use dot-separated namespacing
- Comments are not supported (lines must be valid `KEY=VALUE` pairs)

## Bootstrap Keys

| Key | Value Format | Set When | Cleared When |
|-----|-------------|----------|-------------|
| `bootstrap.started_at` | ISO 8601 UTC timestamp | `--apply` begins | Never (append-only) |
| `bootstrap.completed_at` | ISO 8601 UTC timestamp | `--apply` completes | Never |
| `bootstrap.profile` | profile name string | profile is resolved | Next run overwrites |
| `bootstrap.host` | short hostname | `--apply` begins | Never |

## Component Keys

All component keys follow the pattern `component.<name>.<attribute>`.

### Installed Component

| Key | Value Format | Set When | Cleared When |
|-----|-------------|----------|-------------|
| `component.<name>.installed` | `true` | install succeeds | On replace or uninstall |
| `component.<name>.version` | version string or `unknown` | install succeeds | On reinstall |
| `component.<name>.mode` | install / reuse / wrap / replace / side-by-side | install completes | On reinstall |
| `component.<name>.installed_at` | ISO 8601 UTC timestamp | install succeeds | Never |
| `component.<name>.path` | absolute path string | install records path | On reinstall |

### Skipped Component

| Key | Value Format | Set When | Cleared When |
|-----|-------------|----------|-------------|
| `component.<name>.skip` | `true` | `--mode skip` applied | User manually removes |
| `component.<name>.skip_reason` | reason string | `--mode skip` applied | User manually removes |
| `component.<name>.skip_at` | ISO 8601 UTC timestamp | `--mode skip` applied | Never |

### Wrap Mode

| Key | Value Format | Set When | Cleared When |
|-----|-------------|----------|-------------|
| `component.<name>.original_path` | absolute path to original binary | `--mode wrap` | On replace |

### Side-by-Side Mode

| Key | Value Format | Set When | Cleared When |
|-----|-------------|----------|-------------|
| `component.<name>.sbs_path` | absolute path to SBS install dir | `--mode side-by-side` | Never |

### System Tuning

| Key | Value Format | Set When | Cleared When |
|-----|-------------|----------|-------------|
| `component.system-tuning.status` | `applied` / `skipped` / `reuse` | system-tuning install | On replace |

### Tokens Config

| Key | Value Format | Set When | Cleared When |
|-----|-------------|----------|-------------|
| `component.tokens-config.status` | `configured` / `scaffold` / `scaffold-pending-key` / `missing` | tokens-config install | On reinstall |

**Note**: Token values are NEVER stored in the state file.

## Example State File

```
bootstrap.started_at=2025-01-15T10:22:01Z
bootstrap.completed_at=2025-01-15T10:24:33Z
bootstrap.profile=rpi-lowram
bootstrap.host=raspberrypi
component.system-tuning.installed=true
component.system-tuning.version=applied
component.system-tuning.mode=install
component.system-tuning.installed_at=2025-01-15T10:22:15Z
component.cgc.installed=true
component.cgc.version=0.3.1
component.cgc.mode=install
component.cgc.installed_at=2025-01-15T10:22:45Z
component.cgc.path=/home/pi/cgc-rpi/cgc
component.chub.installed=true
component.chub.version=1.2.0
component.chub.mode=install
component.chub.installed_at=2025-01-15T10:23:10Z
component.workflow.installed=true
component.workflow.version=git-abc1234
component.workflow.mode=install
component.workflow.installed_at=2025-01-15T10:23:40Z
component.workflow.path=/home/pi/.claude/workflow
component.hooks.installed=true
component.hooks.version=3
component.hooks.mode=install
component.hooks.installed_at=2025-01-15T10:23:55Z
component.hooks.path=/home/pi/.claude/hooks
component.tokens-config.installed=true
component.tokens-config.version=scaffold-pending-key
component.tokens-config.mode=install
component.tokens-config.installed_at=2025-01-15T10:24:00Z
```

## State Store API

Functions in `bootstrap/state-store.sh`:

```bash
state_set KEY VALUE           # Write or overwrite a key
state_get KEY                 # Print value (empty string on miss)
state_has KEY                 # Return 0 if key exists
state_del KEY                 # Remove a key
state_dump                    # Print all key=value pairs, sorted

# Convenience
state_set_component_installed COMPONENT VERSION MODE
state_get_component_installed COMPONENT  # returns 0/1
state_set_skip COMPONENT REASON
```

## Viewing State

```bash
# Show all state
source bootstrap/state-store.sh && state_dump

# Or simply
sort ~/.bloom-node-state

# Get one value
source bootstrap/state-store.sh && state_get "component.cgc.version"
```

## State File Security

The state file is created with default umask permissions (typically 644). It does not contain secrets. If you store sensitive keys in a custom integration, consider setting `chmod 600 ~/.bloom-node-state` manually.
