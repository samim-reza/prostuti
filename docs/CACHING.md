# Caching, offline-first & performance

Prostuti must feel instant on budget Android phones and keep working with
mobile data off. These are the techniques and where each one lives.

## Client cache (`app/lib/core/cache/`)

```
widget ─▶ provider ─▶ repository ─▶ CachedFetcher ─▶ L1 LruCache (memory, 256 entries, O(1))
                                                   └▶ L2 Hive box (disk, JSON + TTL)
                                                   └▶ network (Supabase)
```

| Technique | Where | Why |
|-----------|-------|-----|
| TTL read-through cache | `CachedFetcher.get` | repeat reads cost no network |
| Stale-while-revalidate | `CachedFetcher.watch`, `PagedNotifier.readCachedFirstPage` | instant first paint, then fresh data |
| Single-flight (request coalescing) | `CachedFetcher._singleFlight` | ten widgets asking at once send one request (no stampede) |
| Negative caching | `isEmpty` → `negativeTtl` | "no notes yet" or "no plan" doesn't hammer the API (cache penetration) |
| Offline serving | `ConnectivityService` + `CachedFetcher` | while offline, cached data (even stale) is returned immediately |
| Bloom filter | `core/cache/bloom_filter.dart`, `supabase/functions/_shared/bloom.ts` | O(k) "definitely not seen" checks for realtime and RSS de-duplication |
| Day-scoped TTL | daily notes cache until Bangladesh midnight | notes vanish exactly when the server hides them |

Typical policies: catalog (subjects, add-ons) 24 h · profile 5 min · notes until
BD midnight · leaderboard today 1 min / past days 12 h · feed first page short TTL.

## Offline-first (`app/lib/core/offline/`)

* **Reads:** every screen renders its last cached data offline, and a global
  `OfflineBanner` explains that it is showing saved data.
* **Writes:** `OfflineQueue` is a persistent FIFO outbox in Hive.
  `run(type, payload, id:)` executes immediately when online. Otherwise it
  queues the write and replays it when connectivity returns, with exponential
  backoff (2^n s, max 5 min). Handlers are idempotent: client-generated UUIDs
  for posts, comments and messages, plus idempotent RPCs (`react_to_post`,
  `complete_plan_item`, `submit_exam`, `sync_practice_attempts`).
* **Offline practice packs:** `get_offline_pack` downloads a subject's
  questions with answers. Practice is graded locally and synced through
  `sync_practice_attempts`, which re-grades on the server and is idempotent
  by `client_id`.
* **Exams in progress:** answers are persisted on every tap, and submission
  is queued if offline.
* Downloaded note PDFs and bookmarked notes are stored on the device.

## Database performance

* **Keyset pagination** on every list (`(created_at, id) < cursor`), with no
  OFFSET, so page 1000 costs the same as page 1. All lists are backed by
  composite indexes.
* **Trigger-maintained counters:** `reaction_count`, `reaction_summary`,
  `comment_count`, `reply_count`, `friends_count`, `posts_count`.
* **Set-based fan-out:** notification broadcasts are one `INSERT … SELECT`, not
  N round-trips.
* Single-round-trip RPCs for composite screens: `get_feed` returns author and my
  reaction; `get_today_routine`, `get_today_notes`, `get_subjects_overview`,
  `get_readiness`.
* **pgvector HNSW** indexes for semantic search and de-duplication. Trigram GIN
  indexes for user and question search.
* `UNLOGGED` rate-limit counters (fast, crash-safe to lose).

## Rate limiting

Server-side, using a fixed window per user and action
(`enforce_rate_limit` → HTTP 429 with `retry_after`):

| Action | Limit |
|--------|-------|
| posts | 15 / hour |
| comments | 60 / hour |
| messages | 40 / minute |
| reactions | 120 / minute |
| friend requests | 40 / day |
| exam starts | 40 / hour |
| reports | 30 / day |
| practice answers | 300 / hour |
| AI interview | 12 / day |
| plan creation | 6 / day |
| free-tier quotas | model tests 1/day, AI explanations 3/day, weak-topic exams 1/day |

Client-side, `Debouncer` (search), `Throttler` (reactions, typing indicators)
and `TokenBucket` give instant feedback before the server refuses.

## Rendering

* `ListView.builder` / slivers everywhere; `PagedListView` prefetches the next
  page about 600 px before the end.
* `AppNetworkImage` / `UserAvatar` decode images at display size
  (`memCacheWidth`), cached on disk by `cached_network_image`.
* Uploads are compressed to WebP (≤ 1280 px, quality 78) before leaving the phone.
* JSON larger than 32 KB is decoded on a background isolate.
* Riverpod's automatic retry is limited to network errors.
