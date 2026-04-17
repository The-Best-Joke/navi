---
title: TUI Instructions — Navi
category: agent-rules
last_reviewed: 2026-04-16
---

# TUI Instructions — Navi

Canonical shared instructions for all AI coding TUIs working in this repository.

Tool-specific entrypoints:

- `AGENTS.md`
- `CLAUDE.md`
- `GEMINI.md`

Those files must stay thin and point here.

Reference documents:

- `PROJECT_ARCHITECTURE.md`
- `TODO`
- `USER_UNDERSTANDING_SCHEMA.md`

## Repo Rules

1. Treat `TUI.md` as the single source of truth for shared AI-agent instructions.
2. Treat `PROJECT_ARCHITECTURE.md` as the descriptive system reference.
3. Keep `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` identical thin bootstrap files.
4. Do not duplicate large blocks of shared guidance across bootstrap files.

## Architectural Invariants

1. PostgreSQL is the canonical store for operational product state.
2. OpenViking is a derived intelligence layer for memory, retrieval, compression, and personalization.
3. `pending_actions` must exist as first-class structured state.
4. Do not rely on raw conversation history alone to resolve replies like "yes", "send it", or "move it to tomorrow".
5. OpenViking projections must be rebuildable from canonical app data plus retained note/conversation resources.
6. If PostgreSQL and OpenViking disagree, PostgreSQL wins.
7. Group chat functionality is not a safe v1 assumption.

## Implementation Guardrails

1. Preserve the canonical-vs-derived boundary.
2. Prefer explicit app state over LLM-only inference for workflows.
3. Do not introduce duplicated state without naming the source of truth.
4. Put exact, auditable, status-bearing entities in PostgreSQL.
5. Put durable user understanding in OpenViking only when it improves reminders, planning, retrieval, drafting, or coordination.
6. Do not mirror low-level operational state into OpenViking mechanically.

Good mirror:

- "User is preparing for a move this month and has multiple related errands."

Bad mirror:

- "TODO #481 is open with priority high."

## Expected Canonical Schemas

The following are expected to be canonical operational tables in PostgreSQL:

- `pending_actions`
- `todos`
- `reminders`
- `events`
- `notes`

## Documentation Update Rules

If you change any of the following, update the corresponding docs in the same change:

- architecture or request flow: `PROJECT_ARCHITECTURE.md`
- roadmap or design decisions: `TODO`
- long-term memory and personalization model: `USER_UNDERSTANDING_SCHEMA.md`
- shared agent-facing instructions: `TUI.md`
- bootstrap pointers: `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`

## Coding Defaults

- Use strict typing in PHP files: `declare(strict_types=1);`
- Keep business logic in services
- Use DTOs for complex data and enums for fixed sets
- Follow Laravel Pint with the PER preset
- Use conventional commits
