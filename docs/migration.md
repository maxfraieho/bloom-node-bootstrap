# Migration Guide — Install Modes

When deploying to a node that already has some tools installed, bloom-node-bootstrap uses **install modes** to determine how to handle the existing state. This avoids destroying working setups.

## The Five Modes

### `install`
**Use when**: Component is not present at all, or you want to do a clean fresh install.

**What it does**:
1. Clones the component repo into the standard install location
2. Runs any setup scripts
3. Creates symlinks in `~/.local/bin`
4. Records install in state store

**Idempotent**: If the component is already installed by us and healthy, mode automatically degrades to `reuse`.

**Example**:
```bash
./install.sh --apply --component cgc --mode install
```

---

### `reuse`
**Use when**: The tool is already installed and working — you just want bloom to know about it and track it.

**What it does**:
1. Runs `detect.sh` to find the existing install
2. Records the existing path/version in the state store
3. Skips all installation steps
4. Runs verify to confirm it's healthy

**Use cases**:
- You already installed cgc manually before running bloom
- You want to register a foreign tool in bloom's state without changing it
- You're adding bloom to a node that already has a working stack

**Example**:
```bash
./install.sh --apply --component chub --mode reuse
```

---

### `wrap`
**Use when**: A foreign version of the tool is installed (not by us), and you want to add bloom's environment/layer on top without removing the original.

**What it does**:
1. Finds the existing binary/tool
2. Creates a thin wrapper script at `~/.local/bin/TOOL` that:
   - Sources bloom's environment (`~/.bloom-env`)
   - Calls the original binary with all arguments forwarded
3. Does not modify or remove the original
4. Marks the wrapper as bloom-owned (with `BLOOM_WRAP=true` comment)

**Use cases**:
- System-managed cgc from a package manager — you want bloom env vars injected
- A colleague installed chub manually and you need bloom's config layer
- Testing bloom's integration without committing to a full replace

**Example**:
```bash
./install.sh --apply --component cgc --mode wrap
```

**Unwrapping**: To remove the wrap, delete `~/.local/bin/cgc` (bloom's wrapper) and the original binary will be found directly.

---

### `replace`
**Use when**: You want to fully take over an existing install. The existing installation is backed up first.

**What it does**:
1. Prompts for confirmation (or proceeds if `--yes` flag set)
2. Creates a timestamped backup of the existing binary/directory: `foo.bloom-backup.20250101120000`
3. Runs a fresh `install` as if nothing was there
4. The backup is never automatically deleted — you remove it when satisfied

**Use cases**:
- Replacing a manually-installed version with our canonical repo version
- Recovering a broken install while preserving the broken state for debugging
- Upgrading after a major version change that isn't backward-compatible

**Example**:
```bash
./install.sh --apply --component workflow --mode replace
```

**Recovery**: If replace goes wrong:
```bash
# Find backup
ls -la ~/.claude/workflow.bloom-backup.*

# Restore
rm -rf ~/.claude/workflow
mv ~/.claude/workflow.bloom-backup.20250101120000 ~/.claude/workflow
```

---

### `side-by-side`
**Use when**: You want bloom's version of a tool to coexist with an existing installation, each accessible by a different name.

**What it does**:
1. Installs bloom's version to an alternate location (e.g., `~/cgc-bloom` instead of `~/cgc`)
2. Creates a symlink with the bloom-prefixed name: `~/.local/bin/cgc-bloom`
3. Does not touch the original `cgc` at all
4. State store records the side-by-side path

**Use cases**:
- You want to test bloom's cgc without disrupting your existing workflow
- Different projects need different versions of the tool
- Gradual migration: run side-by-side for a week, then replace when confident

**Example**:
```bash
./install.sh --apply --component cgc --mode side-by-side
# Now you have: cgc (original) and cgc-bloom (ours)
```

---

### `skip`
**Use when**: You explicitly do not want a component installed on this node, and you want that decision remembered.

**What it does**:
1. Records the skip decision in the state store with a timestamp
2. Sets `component.COMP.skip=true` and `component.COMP.skip_reason`
3. Future `--apply` runs will not prompt about this component again
4. `--doctor` reports it as "SKIP" (not a failure)

**Use cases**:
- This node doesn't need workflow (it's a pure agent node)
- tokens-config is managed externally (Vault, etc.)
- System tuning is handled by your configuration management (Ansible, etc.)

**Example**:
```bash
./install.sh --apply --component system-tuning --mode skip
```

**Clearing a skip**:
```bash
# Remove skip flags from state store
source bootstrap/state-store.sh
state_del "component.system-tuning.skip"
state_del "component.system-tuning.skip_reason"
```

---

## Mode Selection Logic

The installer selects mode through this cascade:

1. **User override**: `--mode MODE` forces a specific mode globally
2. **Profile default**: `PROFILE_DEFAULT_MODE_COMPONENT` from the resolved profile
3. **Status override**: detect status can change the mode:
   - `ours-healthy` → always `reuse` (don't reinstall what's working)
   - `ours-broken` → `replace` (reinstall our broken install)
   - `foreign` + profile says `install` → `wrap` (don't clobber foreign tools)
   - `partial` → `replace` (complete the partial install)
4. **State override**: if state store has `component.X.skip=true` → `skip`

## Migrating an Existing Node

### Scenario: Node has cgc installed manually, no chub, old hooks

```bash
# 1. See what's there
./install.sh --detect

# 2. See the plan
./install.sh --plan

# Expected plan output:
# cgc      | foreign       | wrap    | add bloom layer
# chub     | missing       | install | clone + setup
# workflow | missing       | install | clone + setup
# hooks    | foreign       | wrap    | add bloom hooks alongside

# 3. Apply (review plan first with --dry-run)
./install.sh --apply --dry-run
./install.sh --apply
```

### Scenario: Replacing an existing stack with our canonical versions

```bash
./install.sh --apply --mode replace --yes
```

This backs up everything and installs fresh. Backups are in `~/.local/bin/*.bloom-backup.*` and `~/TOOL.bloom-backup.*`.

### Scenario: Adding bloom to a fully-configured node without changing anything

```bash
./install.sh --apply --mode reuse
```

This just registers existing installs in the state store and verifies their health.
