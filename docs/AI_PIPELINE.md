# AI pipeline (current affairs, explanations, study plans)

All AI runs in **Supabase Edge Functions** (`supabase/functions/`). The OpenAI key
lives only in Edge Function secrets. Model choice is configuration: `OPENAI_MODEL`
(default `gpt-5.4-mini`) and `OPENAI_EMBED_MODEL` (`text-embedding-3-small`).

## Daily schedule (Asia/Dhaka)

| Time | Job | Function |
|------|-----|----------|
| every 3 h | Pull RSS feeds | `ingest-news` |
| 05:20 | Morning notes | `generate-daily-notes` `{mode:"morning"}` |
| 05:50 | Daily exam | `generate-daily-exam` |
| 06:30\* | Morning routine notifications | `dispatch-notifications` (every 15 min; idempotent per day) |
| 15:30 | Afternoon top-up of notes | `generate-daily-notes` `{mode:"append"}` |
| every 30 min | Re-plan jobs (exam date changed…) | `generate-study-plan` `{mode:"jobs"}` |
| hourly / 00:05 | Housekeeping / nightly rollover | SQL functions |

\* `app_config.morning_routine_time` (editable without a release).

pg_cron calls the functions through `pg_net` with a shared `x-cron-secret`
header. The project URL and the secret live in **Vault**, not in migrations.

## News → facts → notes → exam

```
RSS (14 outlets) ─▶ ingest-news
   • canonical URL → SHA-256
   • persisted Bloom filter (pipeline_state, ~1% FP) skips seen URLs without
     a DB round-trip; "maybe" hits are confirmed with one batched query
   • failing feeds back off exponentially (2^n hours, max 24 h)
        │
        ▼ news_articles (title, short summary, link — never full text)
generate-daily-notes
   1. embed title+summary (pgvector)
   2. leader clustering (cos ≥ 0.80) → one cluster per story across outlets
   3. TRIAGE: one cheap titles-only LLM call over every story; the model must
      draft the MCQ it would ask — no plausible MCQ, no selection
   4. EXTRACT (parallel chunks, strict JSON schema): bilingual title/summary,
      self-contained facts (with entity + time-sensitivity), probable Q&A
   5. FACT RECONCILIATION against the permanent `facts` store:
        cos ≥ 0.94                → duplicate (last_confirmed_date bumped)
        0.86 ≤ cos < 0.94         → LLM judge: duplicate | supersedes | different
        supersedes                → old fact marked superseded → trigger
                                    archives every question built on it
   6. semantic de-dup of the day's notes (English embeddings, cos > 0.82)
   7. insert daily_notes (today only via RLS, kept forever) + notify users
        │
        ▼
generate-daily-exam
   • MCQs only from today's facts (falls back to the last 3 days)
   • structural validation (4 distinct options, index in range)
   • semantic de-dup against the WHOLE bank (match_questions, cos ≥ 0.92)
   • questions stored permanently with fact_id, source_ref
     ("সাম্প্রতিক · ৪ অক্টোবর ২০২৬ · Dhaka Tribune") and source_url
```

The question bank therefore **grows every day**. When a fact changes (a new office
holder, record or figure), questions built on the old fact are archived
automatically, so learners never practise outdated answers.

## Caching layers for LLM calls

`_shared/semantic_cache.ts` (backed by `ai_semantic_cache`):

1. **Exact:** `(namespace, sha256(key))` through a unique index.
2. **Semantic:** HNSW nearest neighbour on the key's embedding, above a
   per-namespace threshold.
3. **Negative:** "no answer" results are cached with a short TTL (cache-penetration protection).

| Namespace | Key | Threshold | TTL |
|-----------|-----|-----------|-----|
| `explain:<locale>` | question + options + answer | 0.975 | 90 d |
| `interview_followups:<locale>` | learner profile (no free text) | 0.97 | 30 d |
| `plan_tips:<locale>` | levels + time buckets + weak subjects | 0.96 | 14 d |

Bangla AI explanations are also stored per question (`ai_explanations`).
`ai_usage_log` records every call and cache hit (see the admin dashboard).

## Study planner

`generate-study-plan/scheduler.ts` is a **pure, unit-tested function** (`deno test`):

* Phases: foundation (≈50%), then practice (≈35%), then final revision (≈15%).
* Every 7th day is a **free weak-topic exam day**. The practice phase has one model
  test a week. The final phase alternates model tests and revision days.
* Topic allocation uses a **max-heap**. Priority = (subject marks / 200) ×
  (topic weight share) × (1 − mastery)^1.5. After each block the priority decays
  ×0.55, so heavy and weak topics come back more often without starving the others.
* **Spaced repetition:** every studied topic gets 15-minute revisions after +3,
  +7 and +16 days.
* The LLM only writes personalised tips, and those are cached.

Users see their plan **only partially**: RLS allows plan days up to today + 2, and
`get_plan_overview()` exposes aggregates and milestones for the rest.
When BPSC moves an exam date, an admin edits `exam_schedules`. A trigger then
queues re-plan jobs and notifies every affected learner.

## Running a stage by hand

```bash
CRON=$(grep '^cron_secret=' key.txt | cut -d= -f2-)
curl -X POST "$SUPABASE_URL/functions/v1/generate-daily-notes" \
     -H "x-cron-secret: $CRON" -H 'Content-Type: application/json' -d '{"mode":"manual"}'
```

Staff can also trigger stages from **Admin → Pipeline** in the app (`admin_run_pipeline`).
