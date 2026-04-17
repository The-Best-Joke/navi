---
description: LLM-assisted semantic audit of the wiki — surfaces contradictions, stale claims, drift, and coverage gaps. Read-only.
---

You are executing the **semantic audit** operation on the Navi documentation wiki. This is the model-driven complement to `docs/scripts/wiki-lint.sh`, which only catches structural issues (missing files, broken links, front-matter). This command catches things that need a reader, not a grep.

Your goal is to produce a prioritized list of doc debt. You do **not** fix it. This command is read-only — the follow-up, if the user wants one, is `/wiki-update`.

## Steps

1. **Load the catalog.** Read `docs/wiki-index.md` for the full list of indexed wiki entries. Then read each entry — skim for claims and specifics, not verbatim memorization. Also read `.claude/commands/` — slash commands are not wiki entries but they contain repo-specific routing rules and examples that can go stale when wiki structure changes.

2. **Gather recent behavior.** In parallel:
   - `git log --since="90 days ago" --pretty=format:"%h %s" -- api/app/`
   - `git log --since="90 days ago" -- docs/wiki-log.md` (what was explicitly logged)
   - `git log --since="90 days ago" --diff-filter=AD --name-only -- api/` (added/deleted files — often schema-level changes)

3. **Audit across four axes.** For each entry, and across entries:

   - **Contradictions** — two entries making conflicting claims. Cross-reference pairs: `TUI.md` ↔ `PROJECT_ARCHITECTURE.md`, `PROJECT_ARCHITECTURE.md` ↔ `USER_UNDERSTANDING_SCHEMA.md`.
   - **Stale claims** — the entry describes plans or state that no longer match reality ("Phase X pending" after it shipped; a deprecated env var described as current).
   - **Drift from code** — the entry names specific files, classes, env vars, endpoints, or flags that have been renamed or removed. Spot-check with Grep on each concrete identifier.
   - **Coverage gaps** — material behavior in recent commits that no wiki entry mentions. Look for new services, providers, DB migrations, env vars, hooks, or slash commands.

4. **Prioritize findings** into three buckets:

   - **Critical** — incorrect information an AI agent reading the docs would act on wrongly. Fix before the next substantive session.
   - **Important** — stale or missing information that doesn't actively mislead but will soon. Fix before the next release.
   - **Nice-to-have** — minor drift or aesthetic inconsistencies.

5. **Produce a report** in the chat. Structure:

   ```
   ## Wiki Semantic Audit — <YYYY-MM-DD>

   ### Critical
   - [entry.md] <finding>. Evidence: <file:line or commit hash>. Suggested action: <one line>.

   ### Important
   - [entry.md] <finding>. Evidence: <...>. Suggested action: <...>.

   ### Nice-to-have
   - [entry.md] <finding>.

   ### Clean
   - <entries that passed with no findings>
   ```

6. **Stop.** Do not run `/wiki-update`. Do not edit files. Do not append to `docs/wiki-log.md`. The follow-up is the user's call.

## Do NOT

- Rewrite entries inline with "here's the fix". The point is surfacing, not resolving.
- Speculate without evidence. Every finding needs a concrete identifier, file path, or commit hash.
- Flag stylistic preferences unless they create ambiguity.
- Re-flag issues already present in `docs/wiki-log.md` as `drift` entries — those are acknowledged.
- Audit `node_modules/`, `vendor/`, `.git/`, or per-tool wrappers (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`).
- Audit `.claude/settings.json` or non-command files under `.claude/` — only `.claude/commands/*.md` are in scope.

## When to run

- Before a major release or deployment
- After a large refactor that touched multiple subsystems
- Quarterly as scheduled doc-debt paydown
- When an agent starts acting on stale info mid-session

Not a hook trigger — expensive by design and judgment-based, so it runs on demand.
