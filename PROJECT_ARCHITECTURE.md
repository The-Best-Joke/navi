---
title: Project Architecture — Navi
category: project-overview
last_reviewed: 2026-04-16
---

# Project Architecture — Navi

## Project Overview

WhatsApp-native AI assistant for notes, TODOs, reminders, scheduling, and social coordination. Backend-only architecture — no frontend; WhatsApp is the frontend.

Single `api/` directory — Laravel 12 (PHP 8.4) backend. Root-level husky + commitlint enforce conventional commits (`commitlint.config.mjs` — must be `.mjs`, wagoid action v6 rejects `.js`).

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
docker compose exec pgsql psql -U postgres -d naviDB
docker compose exec redis redis-cli
curl http://localhost:1933/health
```

No local PostgreSQL, Redis, or OpenViking required — all run as Docker containers. Migrations run automatically on `app` startup (`RUN_MIGRATIONS=true`). PostgreSQL on 5432, Redis on 6379, OpenViking on 1933. Use Docker CE, not Podman.

## Architecture (High-Level)

### Request Flow

1. User sends WhatsApp message (text, voice note, image, or document)
2. Meta delivers webhook payload (JSON) to `POST /api/webhook/whatsapp`
3. `WhatsAppWebhookController` validates HMAC-SHA256 signature, checks idempotency (`message_id` in Redis, 72hr TTL), extracts payload
4. App resolves or creates the user from the phone number, then dispatches `ProcessMessageJob` serialized per stable user key
5. Job routes by media type:
   - text -> MiniMax M2.5
   - audio -> Groq Whisper Large v3 Turbo -> text -> MiniMax
   - image -> GLM-4.7-Flash description -> text + file to Cloudflare R2 -> MiniMax
   - document -> OpenViking parser -> MiniMax
6. Job retrieves context from OpenViking (session history, memories, related resources via semantic search)
7. Job constructs prompt: system prompt + context + user message + tool definitions -> MiniMax M2.5
8. MiniMax responds and may include tool calls
9. Laravel services execute validated tool calls and feed results back if needed
10. Final response is sent via WhatsApp Business API

Time-sensitive actions use a provisional timezone until the user explicitly confirms it. Any reminder, event, or schedule-aware flow must trigger a timezone-confirmation check before relying on the inferred timezone for scheduling.

### Service Architecture

```text
WhatsApp (Meta) --> Laravel API ------> PostgreSQL (relational data)
                         |                    |
                         +--> Redis (queue, rate limits, idempotency)
                         |
                         +--> OpenViking :1933 (context DB, memories, semantic search)
                         |      \--> VLM: MiniMax M2.5 (via LiteLLM)
                         |
                         +--> MiniMax M2.5 (conversation + tool calling)
                         +--> Groq Whisper (audio transcription)
                         +--> GLM-4.7-Flash (image description)
                         \--> Cloudflare R2 (file storage)
```

No Node.js, no Baileys, no OpenClaw. WhatsApp integration is pure HTTP via Meta's official Business API.

### Provider Interfaces

All external services are abstracted behind `ProviderInterface` implementations:

| Interface | Primary | Fallback |
|-----------|---------|----------|
| `LlmProviderInterface` | MiniMax M2.5 | Qwen3.5 Plus, GLM-4.7 |
| `TranscriptionProviderInterface` | Groq Whisper | OpenAI Whisper |
| `ImageDescriptionProviderInterface` | GLM-4.7-Flash | Gemini 2.5 Flash-Lite |
| `WhatsAppProviderInterface` | Meta Business API | none |

### Tool Calling

Tool definitions live in `config/tools.php` and map to Laravel service methods.

```text
MiniMax decides to call create_todo(title, list, due_date)
    -> Laravel validates parameters
    -> TodoService::create() writes to PostgreSQL and OpenViking-derived context
    -> Result returned to MiniMax for response generation
```

Tool calls that affect external systems, such as email or calendar writes, require user confirmation.

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

All API keys are stored in Render environment groups in production. OAuth tokens in PostgreSQL use column-level encryption.

## Database

### PostgreSQL (relational)

Users, TODOs, reminders, events, notes, pending actions, API usage records, audit logs, delegations, coordination graph edges. Standard Eloquent models with `user_id` scoping on all tables. Notes are canonical in PostgreSQL for metadata and normalized text, while OpenViking holds the semantically retrievable resource and derived note relationships.

### OpenViking (context)

User memories, conversation sessions, knowledge resources, and semantic retrieval. Each user maps to a separate OpenViking account for data isolation.

Storage boundary:

- PostgreSQL is the canonical store for product state.
- OpenViking is a derived intelligence layer for memory, retrieval, compression, and personalization.

See `USER_UNDERSTANDING_SCHEMA.md` for long-term personalization design and `TUI.md` for the shared AI instruction layer.

## Coding Conventions

### PHP / Laravel

- Code style: PER via Laravel Pint
- Strict types in all PHP files
- Type hints required on all method parameters and return types
- Service pattern for business logic
- DTOs for complex data
- Enums for fixed value sets
- Redis queue jobs with timeout and retry policy
- Pest + PHPUnit for testing

### Git

- Conventional commits enforced by commitlint + Husky
- Branch naming: `feat/descriptive-name`, `fix/descriptive-name`

## CI/CD

GitHub Actions runs lint, tests, commitlint, and dependency audit.

## Security

- Meta webhook signature verification via HMAC-SHA256
- Redis-backed webhook idempotency by `message_id`
- Per-user job serialization
- Prompt injection protection via role separation and tool validation
- Column-level encryption for sensitive tokens
- Internal services are not publicly exposed

## Deployment

### Render Service Topology

| Service | Type | Notes |
|---|---|---|
| navi-api | Web Service (Docker) | Laravel FPM + Nginx, webhook endpoint |
| navi-worker | Background Worker (Docker) | `php artisan queue:work` + scheduler |
| navi-openviking | Web Service (Docker) | Context DB, port 1933 internal only |
| navi-db | PostgreSQL (managed) | Automatic daily backups |
| navi-redis | Redis (managed) | Queue, rate limits, idempotency cache |

## Observability

Sentry is enabled when configured. API usage is tracked in `api_usage_records` for cost monitoring.
