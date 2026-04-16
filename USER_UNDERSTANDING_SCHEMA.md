# User Understanding Schema — Navi

## Purpose

This document defines Navi's long-term user-understanding model.

It exists to answer one question cleanly:

How should Navi remember the user over time in a way that materially improves reminders, TODOs, scheduling, note retrieval, drafting, and future coordination features?

This schema is a **derived intelligence layer**, not the source of truth for operational product state.

- **PostgreSQL** stores canonical application data.
- **OpenViking** stores structured user understanding for memory, retrieval, compression, and personalization.

## Design Principles

1. Store understanding, not raw product state.
2. Prefer small, atomic memory items over giant profile blobs.
3. Separate explicit user statements from inferred patterns.
4. Track freshness and confidence for every durable memory.
5. Only store things that improve product capabilities.

## Storage Boundary

### PostgreSQL

Use PostgreSQL for anything operational, exact, and application-critical:

- users
- todos
- reminders
- events
- pending actions and drafts
- OAuth tokens
- delivery state
- billing and quota state
- audit logs
- permissions and settings

### OpenViking

Use OpenViking for context the model should understand efficiently:

- durable preferences
- behavioral patterns
- active life commitments
- important entities and relationships
- compressed conversation history
- semantically retrievable knowledge resources
- qualitative social context

### Mirrored Data

Some information should exist in both systems, but never with equal authority.

- PostgreSQL stores the canonical record.
- OpenViking stores a derived contextual projection.

If the systems disagree, PostgreSQL wins.

Examples:

- A TODO lives canonically in PostgreSQL; OpenViking may store a higher-level memory like "user is preparing for a move."
- An event lives canonically in PostgreSQL; OpenViking may store a contextual memory like "user has recurring dental appointments and prefers evening reminders."

## Top-Level Understanding Buckets

### 1. Identity

Stable grounding facts about the user.

Fields:

- `preferred_name`
- `timezone`
- `language`
- `home_region`
- `work_context`
- `life_context`

Examples:

- "Prefers to be called Alex"
- "Timezone is America/Bogota"
- "Works in retail"
- "Lives in Madrid"

### 2. Interaction Preferences

How Navi should behave during conversation.

Fields:

- `response_length_preference`
- `tone_preference`
- `proactivity_preference`
- `confirmation_preference`
- `followup_preference`

Examples:

- "Prefers short, direct responses"
- "Likes confirmation before calendar changes"
- "Does not want too many follow-up prompts"

### 3. Domain Preferences

Capability-specific preferences.

Fields:

- `todo_style`
- `reminder_style`
- `schedule_style`
- `note_style`
- `email_style`
- `coordination_style`

Examples:

- "Prefers TODOs grouped by context rather than priority"
- "Prefers reminders the night before and 30 minutes before"
- "Likes calendar schedules with buffer time"
- "Prefers emails to sound concise and formal"

### 4. Active Commitments

What the user is actively dealing with.

Fields:

- `project_name`
- `commitment_type`
- `time_horizon`
- `importance`
- `related_entities`

Examples:

- "Planning a move this month"
- "Preparing for a dentist appointment next Tuesday"
- "Managing a family trip in June"
- "Working on a product launch this quarter"

### 5. Behavioral Patterns

Observed habits, not merely stated preferences.

Fields:

- `pattern_summary`
- `trigger_context`
- `observed_behavior`
- `reliability`
- `impact`

Examples:

- "Often snoozes morning reminders to 9am"
- "Usually sends planning messages late at night"
- "Tends to postpone medical appointments"
- "Frequently asks for summaries after voice notes"

### 6. Entities

Important people, places, organizations, and recurring references.

Fields:

- `entity_name`
- `entity_type`
- `relationship_to_user`
- `relevance_domains`
- `notes`

Examples:

- "Maria: friend, often coordinates weekend plans"
- "Dr. Salazar: dentist"
- "Downtown gym: recurring location"
- "Acme Corp: employer"

### 7. Relationship Patterns

How the user coordinates with others.

Fields:

- `person`
- `pattern_type`
- `coordination_context`
- `reliability_signal`
- `communication_style`

Examples:

- "Maria usually responds quickly about travel plans"
- "Luis is reliable for work coverage but slow to reply"
- "Family planning usually happens on Sundays"

### 8. Constraints

Real-world limits Navi should respect.

Fields:

- `constraint_type`
- `constraint_summary`
- `time_scope`
- `hardness`
- `affected_domains`

Examples:

- "No meetings before 10am"
- "Unavailable during school pickup from 3pm to 4pm"
- "Avoid reminders during sleep hours"
- "Budget-sensitive this month"

### 9. Goals

Repeated desired outcomes.

Fields:

- `goal_summary`
- `goal_domain`
- `time_horizon`
- `motivation`
- `progress_signal`

Examples:

- "Trying to stay on top of appointments"
- "Wants to be more organized with work tasks"
- "Trying to remember follow-ups"
- "Wants cleaner weekly planning"

### 10. Knowledge Resources

User-owned durable knowledge worth retrieving semantically.

Fields:

- `resource_title`
- `resource_type`
- `summary`
- `topics`
- `related_entities`

Examples:

- meeting notes
- trip plans
- grocery systems
- project summaries
- voice-note summaries

## Memory Item Shape

Every durable understanding item should carry the same conceptual metadata:

```json
{
  "bucket": "domain_preferences",
  "summary": "Prefers reminders the night before important events.",
  "details": "User explicitly said they want reminders the evening before appointments and another one 30 minutes before.",
  "source_type": "explicit",
  "confidence": 0.96,
  "first_seen_at": "2026-04-15T20:00:00Z",
  "last_seen_at": "2026-05-01T14:10:00Z",
  "last_confirmed_at": "2026-05-01T14:10:00Z",
  "status": "active",
  "domains": ["reminders", "calendar"],
  "related_entities": ["dentist"],
  "tags": ["reminder_preference", "timing"]
}
```

Minimum fields:

- `bucket`
- `summary`
- `source_type`
- `confidence`
- `last_seen_at`
- `status`
- `domains`

Recommended enums:

- `source_type`: `explicit`, `inferred`, `derived`
- `status`: `active`, `stale`, `superseded`, `revoked`

## Extraction Rules

Write to this schema when:

- the user explicitly states a durable preference or fact
- a meaningful pattern repeats enough to justify inference
- a note or conversation yields context with future value

Do not write:

- one-off chatter
- transient moods
- raw product state
- low-signal observations with no expected future value

Suggested thresholds:

- explicit durable statement: 1 occurrence
- inferred pattern: 3 to 5 occurrences depending on impact

## Freshness Rules

Not all memories age at the same rate.

- `identity`: low churn
- `interaction_preferences`: medium churn
- `domain_preferences`: medium churn
- `active_commitments`: high churn
- `behavioral_patterns`: medium churn
- `constraints`: medium to high churn
- `goals`: medium churn

Suggested staleness windows:

- active commitments: 30 to 60 days
- behavioral patterns: 60 to 90 days
- preferences: 120 to 180 days
- constraints: by type and impact

## Capability Mapping

### Reminders

Use:

- timezone
- reminder style
- constraints
- behavioral patterns
- active commitments

### TODOs

Use:

- todo style
- goals
- active commitments
- behavioral patterns

### Scheduling

Use:

- timezone
- schedule style
- constraints
- entities
- relationship patterns

### Notes

Use:

- knowledge resources
- entities
- active commitments
- semantic topics

### Email

Use:

- email style
- entities
- relationship patterns
- work context

### Future Delegation and Coordination

Use:

- relationship patterns
- constraints
- entities
- commitment context

## Good vs Bad Memories

Good examples:

- "User prefers brief reminders with exact times."
- "User usually schedules personal errands on Saturdays."
- "Maria is a frequent collaborator for travel planning."
- "User is currently preparing for a move in May."
- "User dislikes phone calls and prefers text-based coordination."
- "User often postpones reminders set before 8am."
- "User prefers formal tone for work emails."

Bad examples:

- "User said hello."
- "User asked what time it is."
- "User mentioned pizza once."
- "TODO #492 exists."
- "User seemed annoyed on Tuesday."

## Recommended Rollout

### Phase 1

Start with:

- `identity`
- `interaction_preferences`
- `domain_preferences`
- `active_commitments`
- `entities`
- `knowledge_resources`

### Phase 2

Add:

- `behavioral_patterns`
- `relationship_patterns`
- `constraints`
- `goals`

### Phase 3

Add automation for:

- confidence updates
- staleness decay
- merge/supersede logic
- selective re-confirmation of high-impact memories

## Final Rule

Do not try to model a perfect digital psyche.

Only store understanding that makes Navi better at:

- reminding
- planning
- retrieving
- drafting
- coordinating

If a memory does not improve one of those, it probably does not belong here.
