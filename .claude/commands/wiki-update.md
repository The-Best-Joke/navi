---
description: Review this session's changes and update the wiki (entries + log) per docs/wiki-schema.md.
---

You are executing the **wiki ingest** operation defined in `docs/wiki-schema.md`. Goal: before this session ends, bring the wiki up to date with whatever durable knowledge the session produced.

## Steps

1. **Survey changes.** Run `git status --porcelain -uall` and `git diff` to see what this session changed. If there are staged commits not yet pushed, also check `git log origin/main..HEAD`.

2. **Classify each change** into one of:
   - **Behavior-affecting** — introduces new conventions, gotchas, decisions, rules, schemas, endpoints, env vars, or user-visible features. Requires a wiki entry update AND a log entry.
   - **Doc-only** — edits a wiki entry directly. Requires a log entry (it captures the *why*).
   - **Transient / refactor / formatting** — no durable knowledge change. Requires a one-line `noop` log entry only.

3. **Update the relevant wiki entry** for each behavior-affecting change. Route by category:
   - Backend changes (Laravel, services, tools, DB schema) → `api/TUI.md` (rules, conventions, gotchas) or `PROJECT_ARCHITECTURE.md` (system overview, request flow, endpoints, env vars)
   - Architecture or request flow → `PROJECT_ARCHITECTURE.md`
   - OpenViking / user memory / personalization → `USER_UNDERSTANDING_SCHEMA.md`
   - Shared agent instructions, invariants, guardrails → `TUI.md`
   - Project-wide or deployment → `PROJECT_ARCHITECTURE.md`

   Keep updates **short, precise, and in the existing tone**. Add a sentence or a table row — do not rewrite sections. If you find yourself drafting a paragraph, check whether the existing section already covers it.

4. **Append log entries** to `docs/wiki-log.md` under today's `## YYYY-MM-DD` header (create if missing). Format:

   ```
   - claude: <type>(<scope>): <one-line description>
   ```

   Valid types: `add`, `update`, `remove`, `decision`, `doc`, `feat`, `fix`, `refactor`, `chore(wiki)`, `noop`.
   Scopes: `project-overview`, `agent-rules`, `memory-schema`, `backend`, `wiki-meta`, `infra`.

   One entry per material change. Batch trivial noops.

5. **Lint.** Run `bash docs/scripts/wiki-lint.sh` and address any errors. Warnings can be left for follow-up if they predate this session.

6. **Bump `last_reviewed`** on any wiki entry you modified. Use today's date (UTC).

## Do NOT

- Create new wiki entries for ephemeral or speculative content. If in doubt, log it and wait for the pattern to recur.
- Use hedging language in entries (`may`, `might`, `could`). Entries are durable facts; if you can't state it flatly, don't write it yet.
- Summarize what you just did in the chat after updating. The log is the record.
- Edit older log entries. Correct them with a follow-up entry instead.

## Escape hatch

If the entire session was routine (bug fixes, refactors, formatting) with no durable knowledge to preserve, a single log entry suffices:

```
- claude: chore(wiki): noop — <brief summary of what the session did>
```

This satisfies the Stop hook and is the right answer when nothing about the codebase's rules, conventions, or architecture changed.
