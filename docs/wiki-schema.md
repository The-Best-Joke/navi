---
title: Wiki Schema — Navi
category: wiki-meta
last_reviewed: 2026-04-16
---

# Wiki Schema — Navi

The Navi wiki is a structured, version-controlled documentation layer maintained by human and AI contributors. Adapted from Andrej Karpathy's "LLM Wiki" gist for multi-agent, AI-assisted development.

## What is a wiki entry?

A wiki entry is any `.md` file that:
- Lives in the project repository
- Is tracked in `docs/wiki-index.md`
- Has valid YAML front-matter (see below)
- Documents a system, behavior, contract, or decision that agents must understand

**Not wiki entries** (excluded from lint checks):
- Thin bootstrap wrappers: `CLAUDE.md`, `AGENTS.md`, `GEMINI.md` at any level
- Slash command files under `.claude/commands/`

## Front-Matter

Every indexed wiki entry must begin with:

```yaml
---
title: <human-readable title>
category: <one of the categories below>
last_reviewed: YYYY-MM-DD
---
```

No optional fields. When an entry is superseded, delete it and update all cross-references — do not leave tombstones.

## Categories

| Category | Description |
|----------|-------------|
| `project-overview` | High-level system description, architecture, deployment, services |
| `agent-rules` | AI agent instructions, invariants, implementation guardrails |
| `memory-schema` | OpenViking / user understanding schema and policies |
| `backend` | Laravel API implementation rules, conventions, gotchas |
| `wiki-meta` | Wiki infrastructure (schema, index, log) |

## Cross-Reference Conventions

- Use relative paths from the linking file's directory
- Lint resolves all `[text](target)` links and fails on missing targets
- Anchors (`#section`) are stripped before resolution
- External URLs (`http://`, `https://`) and root-absolute paths are not checked

## The Three Operations

**Ingest** — update wiki entries after code or design changes (`/wiki-update`)
**Query** — read wiki entries at session start (via `TUI.md` and the index)
**Lint** — verify structural integrity continuously (via hooks)

## The Self-Reinforcement Loop

```
Agent makes a change
      |
      v
PostToolUse hook fires wiki-lint.sh after every .md write
      |
   lint errors? --> block turn --> agent must fix the wiki
      |
      v (clean)
Stop hook fires wiki-behavior-reminder.sh
      |
   behavior changed, no .md touched? --> block stop --> agent must document
      |
      v (documented)
Session ends with the wiki consistent
```

## Log Entry Format

Entries in `docs/wiki-log.md` follow this format:

```
## YYYY-MM-DD

- <agent>: <type>(<scope>): <description>
```

- `<agent>`: `claude`, `codex`, `gemini`, or `human`
- `<type>`: `add`, `update`, `remove`, `noop`, `decision`, `doc`, `feat`, `fix`, `refactor`, `chore(wiki)`
- `<scope>`: short label matching a wiki category or file basename
- `<description>`: one sentence explaining what changed and why

`noop` entries are required when behavior code changes without documentation impact — to prove the omission was deliberate.

## Multi-Agent Scope

Hooks are enforced inside Claude Code sessions. Codex and Gemini read the wiki at startup but do not enforce the loop. The `<agent>` field in log entries preserves attribution across tools.
