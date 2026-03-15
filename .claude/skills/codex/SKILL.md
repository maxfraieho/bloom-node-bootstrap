---
name: codex
description: Use when delegating implementation tasks to Codex CLI. Codex = primary implementer for bulk code/docs work. Invoke this skill when about to write bulk file edits, batch operations, or multi-file changes that should be delegated instead of done manually.
---

# Codex Workflow Skill

## Principle

Claude = architect, planner, reviewer.
Codex = primary implementer.

Full workflow: see `~/.claude/skills/claude-codex-workflow.md`
Gate policy: see `~/.claude/skills/codex-usage-policy.md`

## When to delegate to Codex

Triggers (any one = delegate):
- T1: Batch of files with identical/templated change (N≥3)
- T2: Creating multiple new files in a new directory (N≥2)
- T3: Multiple isolated components modified in same task (≥2)
- T4: Any subtask with no shared state with concurrent work
- T5: File-editing phase that precedes a test/integration loop

## Gate (fill before starting any task)

```
Triggers fired: [T1/T2/T3/T4/T5 — or NONE]
Codex-eligible: [list subtasks — or NONE]
Codex-dispatched: [list subtasks — or PENDING]
Local-only: [list subtasks with reason]
Claimed exemptions: [named bottleneck per exemption — or NONE]
Gate status: PASS / BLOCK
```

## Invocation

```bash
codex exec --dangerously-bypass-approvals-and-sandbox "<prompt>"
```

## Known limitations

- SIGSEGV (exit 139) when Unicode characters appear in shell arg string
- Workaround: write a Python script with unicode strings as Python literals, then `codex exec "python3 /tmp/script.py"`
- If Codex crashes: document failure explicitly, use script-fallback executor, mark in report

## Fallback pattern

```
[Codex SIGSEGV documented]
→ Write /tmp/task_script.py with all unicode as Python string literals
→ codex exec "python3 /tmp/task_script.py"
→ If still fails: Claude direct execution (mark as "script fallback, no Codex")
```
