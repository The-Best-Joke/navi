# CLAUDE.md — Navi

## Project Overview

WhatsApp-native AI assistant for notes, TODOs, reminders, scheduling, and social coordination. Backend-only architecture — no frontend (WhatsApp *is* the frontend).

Single `api/` directory — Laravel 12 (PHP 8.4) backend. Root-level husky + commitlint enforce conventional commits (`commitlint.config.mjs` — must be `.mjs`, wagoid action v6 rejects `.js`).

Full project roadmap, tech stack rationale, and design constraints documented in `TODO`.

## Quick Commands

### Backend (api/)
```bash
cd api
composer install
php artisan test                 # Run tests (Pest + PHPUnit)
./vendor/bin/pint                # Fix code style (PER)
./vendor/bin/pint --test         # Check code style without modifying
php artisan serve                # Dev server (:8000)
php artisan queue:work           # Background job worker
php artisan schedule:run         # Run scheduled tasks (reminders, commits, synthesis)
```

### Docker (full stack)
```bash
cd api
docker compose up -d             # Start all services (app, worker, pgsql, redis, openviking)
docker compose down              # Stop all services
docker compose build             # Rebuild images (after Dockerfile changes)
docker compose exec app php artisan test
docker compose exec pgsql psql -U postgres -d naviDB              # DB shell
docker compose exec redis redis-cli                                # Redis shell
curl http://localhost:1933/health                                  # OpenViking health check
```

No local PostgreSQL, Redis, or OpenViking required — all run as Docker containers. Migrations run automatically on `app` startup (`RUN_MIGRATIONS=true`). PostgreSQL on 5432, Redis on 6379, OpenViking on 1933. **Use Docker CE** (not Podman — rootless mode has UID/SELinux issues on Fedora).

## Architecture (High-Level)

### Request Flow
1. User sends WhatsApp message (text, voice note, image, or document)
2. Meta delivers webhook payload (JSON) to `POST /api/webhook/whatsapp`
3. `WhatsAppWebhookController` validates HMAC-SHA256 signature, checks idempotency (`message_id` in Redis, 72hr TTL), extracts payload
4. Dispatches `ProcessMessageJob` to Redis queue (serialized per `user_id` — `WithoutOverlapping` middleware)
5. Job resolves user (auto-creates on first message from unknown phone number), routes by media type:
   - **Text** → direct to MiniMax M2.5
   - **Audio** → Groq Whisper Large v3 Turbo (STT) → text → MiniMax
   - **Image** → GLM-4.7-Flash (description) → text + file to Cloudflare R2 → MiniMax
   - **Document** → OpenViking parser (PDF/DOCX/HTML) → MiniMax
6. Job retrieves context from OpenViking (session history, memories, related resources via semantic search)
7. Job constructs prompt: system prompt + context + user message + tool definitions → MiniMax M2.5
8. MiniMax responds (may include tool calls — TODO creation, reminder setting, calendar operations, etc.)
9. Tool calls executed by Laravel services, results fed back to MiniMax if needed
10. Final response sent via WhatsApp Business API (`POST https://graph.facebook.com/v22.0/{phone_number_id}/messages`)

### Service Architecture
```
WhatsApp (Meta) ──webhook──► Laravel API ──────► PostgreSQL (relational data)
                                │                       │
                                ├──► Redis (queue, rate limits, idempotency)
                                │
                                ├──► OpenViking :1933 (context DB, memories, semantic search)
                                │       └── VLM: MiniMax M2.5 (via LiteLLM)
                                │
                                ├──► MiniMax M2.5 (primary LLM — conversation + tool calling)
                                ├──► Groq Whisper (audio transcription)
                                ├──► GLM-4.7-Flash (image description)
                                └──► Cloudflare R2 (file storage)
```

No Node.js, no Baileys, no OpenClaw. WhatsApp integration is pure HTTP via Meta's official Business API.

### Provider Interfaces

All external services are abstracted behind `ProviderInterface` implementations for swappability:

| Interface | Primary | Fallback |
|-----------|---------|----------|
| `LlmProviderInterface` | MiniMax M2.5 | Qwen3.5 Plus, GLM-4.7 |
| `TranscriptionProviderInterface` | Groq Whisper | OpenAI Whisper |
| `ImageDescriptionProviderInterface` | GLM-4.7-Flash | Gemini 2.5 Flash-Lite |
| `WhatsAppProviderInterface` | Meta Business API | (none — Meta is the platform) |

### Tool Calling

MiniMax M2.5 handles all tool calling natively. Tool definitions live in `config/tools.php` — loaded into every MiniMax API call's `tools` parameter. Each tool maps to a Laravel service method:

```
MiniMax decides to call create_todo(title, list, due_date)
    → Laravel validates parameters
    → TodoService::create() writes to PostgreSQL + OpenViking
    → Result returned to MiniMax for response generation
```

Tool calls that affect external systems (send email, create calendar event) always require user confirmation via WhatsApp interactive buttons before execution.

## External Services

| Service | Purpose | Auth | Env vars |
|---------|---------|------|----------|
| Meta WhatsApp Business | Messaging platform | App Secret + Access Token | `WHATSAPP_APP_SECRET`, `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_VERIFY_TOKEN` |
| MiniMax M2.5 | Primary LLM | API Key | `MINIMAX_API_KEY`, `MINIMAX_BASE_URL` |
| Groq | Audio transcription | API Key | `GROQ_API_KEY` |
| Z.AI (GLM) | Image description | API Key | `GLM_API_KEY` |
| OpenViking | Context database | API Key (local) | `OPENVIKING_BASE_URL`, `OPENVIKING_API_KEY` |
| Cloudflare R2 | File storage | Access Key + Secret | `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`, `R2_ENDPOINT` |
| Google Calendar | Calendar sync | OAuth2 | `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REDIRECT_URI` |
| Resend | Transactional email | API Key | `RESEND_API_KEY` |
| Sentry | Error monitoring | DSN | `SENTRY_LARAVEL_DSN` |

All API keys stored in Render environment groups in production. Column-level encryption (`casts: 'encrypted'`) for OAuth tokens in PostgreSQL.

## Database

### PostgreSQL (relational)
Users, TODOs, reminders, events, notes metadata, API usage records, audit logs, delegations, coordination graph edges. Standard Eloquent models with `user_id` scoping on all tables.

### OpenViking (context)
User memories (8 categories: profile, preferences, entities, events, cases, patterns, tools, skills), conversation sessions, knowledge resources, social coordination graph via Relations API. Each user maps to a separate OpenViking account for data isolation.

**Key constraint:** OpenViking does not auto-commit sessions. Laravel owns commit orchestration via `SessionCommitService` (hybrid policy: message count threshold OR time window). See `TODO` § "OpenViking Internals & Design Constraints" for full details on commit mechanics, dedup behavior, and gaps.

## Coding Conventions

### PHP / Laravel
- **Code style**: PER via Laravel Pint (`pint.json` → `{ "preset": "per" }`)
- **Strict types**: `declare(strict_types=1);` in all PHP files
- **Type hints**: required on all method parameters and return types
- **Architecture**: Service pattern (business logic in `app/Services/`), DTOs for complex data, Enums for fixed value sets
- **Jobs**: Redis queue, 900s timeout, static exponential backoff `[2, 4, 8, 16, 32]`
- **Testing**: Pest (BDD-style), SQLite in-memory for tests, Feature/ and Unit/ directories
- **Naming**: PascalCase classes, camelCase methods, snake_case DB columns, plural snake_case tables

### Git
- **Commits**: Conventional commits enforced by commitlint + Husky
- **Types**: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`
- **Scopes**: `api`, `docker`, `docs`, `whatsapp`, `openviking`, `llm`, `stt`, `tools`
- **Subject**: imperative mood, lowercase, no period, max 72 chars
- **Branch naming**: `feat/descriptive-name`, `fix/descriptive-name`

## CI/CD

GitHub Actions (`.github/workflows/ci.yml`) on push to `main` and PRs.

| Job | Depends on | Runs |
|-----|-----------|------|
| `backend-lint` | — | `./vendor/bin/pint --test` |
| `backend-test` | `backend-lint` | `php artisan test` (SQLite in-memory) |
| `commitlint` | — | Conventional commit validation (PR only) |
| `dependency-audit` | — | `composer audit` (advisory, non-blocking) |

No Docker needed in CI — tests use SQLite + array cache + sync queue.

## Security

### Webhook Verification
All incoming Meta webhooks validated via HMAC-SHA256 using `WHATSAPP_APP_SECRET`. Invalid signatures rejected before any processing.

### Rate Limiting
| Scope | Limit |
|-------|-------|
| Messages (paid tier) | 30/user/min |
| Messages (free tier) | 5/user/min |
| LLM cost (per user) | `MONTHLY_COST_LIMIT_CENTS` — blocks processing when exceeded |
| WhatsApp send | 80 messages/second (Meta Business API tier limit) |

### Data Protection
- Webhook idempotency: `message_id` dedup in Redis (72hr TTL)
- Per-user job serialization: `WithoutOverlapping` middleware on `user_id`
- Prompt injection: system/user role separation, tool call parameter validation before execution
- OAuth tokens: column-level encryption in PostgreSQL (`casts: 'encrypted'`)
- File storage: encrypted at rest (Cloudflare R2 default)
- Internal services (OpenViking, PostgreSQL, Redis): Docker internal network only, never exposed

### Audit Logging
Security events logged to `audit_logs` table (event type + user ID only, never message content). Sentry integration for error monitoring.

## Deployment

### Render Service Topology
| Service | Type | Notes |
|---|---|---|
| navi-api | Web Service (Docker) | Laravel FPM + Nginx, webhook endpoint |
| navi-worker | Background Worker (Docker) | `php artisan queue:work` + scheduler |
| navi-openviking | Web Service (Docker) | Context DB, port 1933 (internal only) |
| navi-db | PostgreSQL (managed) | Automatic daily backups |
| navi-redis | Redis (managed) | Queue, rate limits, idempotency cache |

All backend services share one Docker image (multi-stage: base → dev → production). Shared Render env group for secrets across api/worker/openviking. Render terminates TLS at LB.

### Backups
- **PostgreSQL**: Render managed, automatic daily backups. RPO: 24 hours.
- **OpenViking**: Daily `.ovpack` export to Cloudflare R2 via scheduled job. Render persistent disk for Docker volume.
- **Cloudflare R2**: Managed durability (11 nines).

## Observability (Sentry)

Backend reports to Sentry. No-ops when DSN unset (local dev, CI). `BeforeSend` redacts `password`, `api_key`, `token`, `secret`, `phone_number`. All LLM/STT/image API calls tracked in `api_usage_records` with `operation_type` for cost monitoring.
