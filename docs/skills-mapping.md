# Skills Mapping

## Global skills (installed by bootstrap)

Bootstrap installs these to ~/.claude/skills/ via workflow component:
- using-superpowers
- verification-before-completion
- codex
- obsidian-markdown
- documentation-review
- doc-indexer
- skill-audit

Canonical source: claude-codex-workflow repo (github.com/maxfraieho/claude-codex-workflow)

## Project-level skills (.claude/skills/ in this repo)

- codex: delegation workflow reference
- verification-before-completion: evidence gate for bootstrap scripts

## Model

GLOBAL_ONLY: using-superpowers, obsidian-markdown, documentation-review, doc-indexer, skill-audit
PROJECT_REQUIRED: codex, verification-before-completion
BOOTSTRAP_MANAGED: all global skills (workflow component installs them)
