// ingest-news — pulls RSS feeds from Bangladeshi and international outlets.
//
// Algorithm
//   1. Load the persisted Bloom filter of seen URL hashes (pipeline_state).
//   2. Fetch feeds concurrently (bounded), parse items, keep the last 48 h.
//   3. Hash canonical URLs; Bloom says "definitely new" → insert directly,
//      "maybe seen" → confirm with one batched SQL lookup (rare).
//   4. Insert new articles (ON CONFLICT DO NOTHING keeps it idempotent).
//   5. Track per-feed health; failing feeds back off automatically.
// Only titles, short summaries and links are stored — never full articles.
import { json, serve } from '../_shared/http.ts';
import { admin, requireCronOrStaff } from '../_shared/supabase.ts';
import { parseFeed } from '../_shared/rss.ts';
import { BloomFilter, fromHex, toHex } from '../_shared/bloom.ts';
import { canonicalUrl, mapLimit, sha256 } from '../_shared/text.ts';

const BLOOM_KEY = 'news_url_bloom_v1';
const BLOOM_CAPACITY = 200_000;
const MAX_AGE_MS = 48 * 3600_000;

serve(async (req) => {
  await requireCronOrStaff(req);

  const { data: state } = await admin.from('pipeline_state').select('value, meta').eq('key', BLOOM_KEY)
    .maybeSingle();
  const bloom = state?.value
    ? new BloomFilter(state.meta.m, state.meta.k, fromHex(state.value as unknown as string))
    : BloomFilter.create(BLOOM_CAPACITY, 0.01);

  const { data: sources } = await admin
    .from('news_sources')
    .select('id, name, rss_url, language, region, priority, fail_count, last_fetched_at')
    .eq('enabled', true);

  const now = Date.now();
  const due = (sources ?? []).filter((s) => {
    // back-off: 2^fail_count hours (max 24 h) after repeated failures
    if (!s.fail_count || !s.last_fetched_at) return true;
    const wait = Math.min(24, 2 ** s.fail_count) * 3600_000;
    return now - new Date(s.last_fetched_at).getTime() > wait;
  });

  const results = await mapLimit(due, 4, async (src) => {
    try {
      const res = await fetch(src.rss_url, {
        headers: {
          'User-Agent': 'Mozilla/5.0 (compatible; ProstutiBot/1.0; +https://prostuti.app)',
          Accept: 'application/rss+xml, application/xml, text/xml, */*',
        },
        signal: AbortSignal.timeout(15_000),
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const items = parseFeed(await res.text()).filter((i) =>
        !i.published || now - i.published.getTime() < MAX_AGE_MS
      );
      await admin.from('news_sources').update({
        last_fetched_at: new Date().toISOString(),
        fail_count: 0,
        last_error: null,
      }).eq('id', src.id);
      return { src, items };
    } catch (e) {
      await admin.from('news_sources').update({
        last_fetched_at: new Date().toISOString(),
        fail_count: (src.fail_count ?? 0) + 1,
        last_error: String((e as Error).message ?? e).slice(0, 300),
      }).eq('id', src.id);
      return { src, items: [] };
    }
  });

  // Hash + Bloom pre-filter.
  const candidates: { row: Record<string, unknown>; hash: string; maybeSeen: boolean }[] = [];
  const seenInRun = new Set<string>();
  for (const { src, items } of results) {
    for (const item of items) {
      const url = canonicalUrl(item.link);
      const hash = await sha256(url);
      if (seenInRun.has(hash)) continue;
      seenInRun.add(hash);
      candidates.push({
        hash,
        maybeSeen: bloom.mightContain(hash),
        row: {
          source_id: src.id,
          url,
          url_hash: hash,
          title: item.title,
          summary: item.summary || null,
          image_url: item.image,
          language: src.language,
          published_at: (item.published ?? new Date()).toISOString(),
          content_hash: await sha256(`${item.title}|${item.summary}`.toLowerCase()),
        },
      });
    }
  }

  // Confirm Bloom "maybe" answers with a single query.
  const maybe = candidates.filter((c) => c.maybeSeen).map((c) => c.hash);
  const existing = new Set<string>();
  for (let i = 0; i < maybe.length; i += 200) {
    const { data } = await admin.from('news_articles').select('url_hash').in(
      'url_hash',
      maybe.slice(i, i + 200),
    );
    for (const r of data ?? []) existing.add(r.url_hash);
  }
  const fresh = candidates.filter((c) => !existing.has(c.hash));

  let inserted = 0;
  for (let i = 0; i < fresh.length; i += 200) {
    const chunk = fresh.slice(i, i + 200).map((c) => c.row);
    const { data, error } = await admin.from('news_articles').upsert(chunk, {
      onConflict: 'url_hash',
      ignoreDuplicates: true,
    }).select('id');
    if (error) console.error('insert error', error.message);
    inserted += data?.length ?? 0;
  }
  for (const c of candidates) bloom.add(c.hash);

  await admin.from('pipeline_state').upsert({
    key: BLOOM_KEY,
    value: toHex(bloom.bits),
    meta: { m: bloom.m, k: bloom.k },
    updated_at: new Date().toISOString(),
  });

  return json({
    feeds: due.length,
    failed: results.filter((r) => r.items.length === 0).map((r) => r.src.name),
    candidates: candidates.length,
    bloom_maybe: maybe.length,
    bloom_false_positives: maybe.length - existing.size,
    inserted,
  });
});
