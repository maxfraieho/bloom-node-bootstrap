# Workflow ctx-routing Integration Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Integrate claude-codex-skill's profile-aware ctx routing into bloom-node-bootstrap so `ctx context` works correctly after install on any machine, including Acer Aspire (x86-legacy-lowram / generic-safe).

**Architecture:**
- `claude-codex-workflow` repo gains a `hooks/` directory with portable hook scripts
- Hook path discovery uses `command -v ctx` + fallback chain instead of hardcoded paths
- bloom `workflow` component detects manifest/artifacts presence and writes `CTX_PROFILE` env based on machine profile
- All 6 bloom profiles declare `PROFILE_CTX_PROFILE` (rpi or default)

**Integration points:**
1. `claude-codex-skill/hooks/` — new directory, portable hooks
2. `bloom-node-bootstrap/components/workflow/detect.sh` — +manifest detection
3. `bloom-node-bootstrap/components/workflow/install.sh` — +CTX_PROFILE env write
4. `bloom-node-bootstrap/components/workflow/verify.sh` — +ctx functional check
5. `bloom-node-bootstrap/profiles/*.sh` (×6) — +PROFILE_CTX_PROFILE

---

### Task 1: Create hooks/ directory in claude-codex-skill

**Files:** Create `claude-codex-skill/hooks/unified-skill-hook.sh` (portable)
**Key change:** Replace hardcoded `/home/vokov/claude-codex-skill/bin/ctx` with dynamic discovery

### Task 2: Copy remaining hooks to claude-codex-skill/hooks/

**Files:** ctx-workflow-policy.sh, post-execution-verification.sh, pre-execution-validation.sh, context-drift-detection.sh

### Task 3: Update workflow/detect.sh

**Files:** Modify `components/workflow/detect.sh`
**Add:** WORKFLOW_HAS_MANIFEST, WORKFLOW_HAS_ARTIFACTS detection

### Task 4: Update workflow/install.sh

**Files:** Modify `components/workflow/install.sh`
**Add:** `_wf_write_ctx_env()` — writes CTX_PROFILE to ~/.bloom/env.sh based on PROFILE_CTX_PROFILE

### Task 5: Update workflow/verify.sh

**Files:** Modify `components/workflow/verify.sh`
**Add:** ctx command functional check, manifest.json presence check

### Task 6: Update all 6 profiles

**Files:** `profiles/{rpi-lowram,arm-sbc,x86-legacy-lowram,cloud-micro,x86-alpine-minimal,generic-safe}.sh`
**Add:** PROFILE_CTX_PROFILE + export

### Task 7: Verify pipeline

Run: detect → plan → apply --dry-run → verify → doctor
Confirm: ctx skills, ctx context work after install
