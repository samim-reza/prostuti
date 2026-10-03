// Two-tier LLM response cache backed by Postgres + pgvector.
//
//   1. exact:    (namespace, sha256(key))           — O(1) unique index
//   2. semantic: cosine(embedding(key)) ≥ threshold — HNSW nearest neighbour
//   3. miss:     compute → store (negative results get a short TTL so
//                repeated "no answer" prompts don't keep hitting the LLM)
import { admin } from './supabase.ts';
import { embed, logUsage, toVector } from './openai.ts';
import { sha256 } from './text.ts';

export interface CacheOptions<T> {
  namespace: string;
  key: string; // canonical text describing the request
  ttlHours: number;
  negativeTtlHours?: number;
  threshold?: number; // semantic similarity threshold (0..1); omit to disable semantic lookups
  isNegative?: (value: T) => boolean;
  fn: string;
  userId?: string | null;
}

export async function cached<T>(
  o: CacheOptions<T>,
  compute: () => Promise<T>,
): Promise<{ value: T; hit: 'exact' | 'semantic' | null }> {
  const hash = await sha256(o.key);
  const now = new Date().toISOString();

  const { data: exact } = await admin
    .from('ai_semantic_cache')
    .select('id, response, hits')
    .eq('namespace', o.namespace)
    .eq('prompt_hash', hash)
    .gt('expires_at', now)
    .maybeSingle();
  if (exact) {
    void admin.from('ai_semantic_cache').update({ hits: exact.hits + 1, last_hit_at: now }).eq(
      'id',
      exact.id,
    );
    void logUsage(o.fn, 'cache', null, 0, o.userId ?? null, 'exact');
    return { value: exact.response as T, hit: 'exact' };
  }

  let vector: number[] | null = null;
  if (o.threshold) {
    [vector] = await embed([o.key], `${o.fn}:cache`);
    const { data: near } = await admin.rpc('semantic_cache_match', {
      p_namespace: o.namespace,
      p_embedding: toVector(vector),
      p_threshold: o.threshold,
    });
    const hit = Array.isArray(near) ? near[0] : null;
    if (hit) {
      void logUsage(o.fn, 'cache', null, 0, o.userId ?? null, 'semantic');
      return { value: hit.response as T, hit: 'semantic' };
    }
  }

  const value = await compute();
  const negative = o.isNegative?.(value) ?? false;
  const ttl = negative ? (o.negativeTtlHours ?? 1) : o.ttlHours;
  await admin.from('ai_semantic_cache').upsert(
    {
      namespace: o.namespace,
      prompt_hash: hash,
      embedding: vector ? toVector(vector) : null,
      response: value as unknown as Record<string, unknown>,
      is_negative: negative,
      expires_at: new Date(Date.now() + ttl * 3600_000).toISOString(),
    },
    { onConflict: 'namespace,prompt_hash' },
  );
  return { value, hit: null };
}
