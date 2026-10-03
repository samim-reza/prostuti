// Minimal, dependency-free OpenAI client for Chat Completions (structured JSON
// output) and embeddings, with retries + usage logging.
import { admin } from './supabase.ts';

const API = 'https://api.openai.com/v1';
const KEY = () => Deno.env.get('OPENAI_API_KEY') ?? '';
export const CHAT_MODEL = () => Deno.env.get('OPENAI_MODEL') ?? 'gpt-5.4-mini';
export const EMBED_MODEL = () => Deno.env.get('OPENAI_EMBED_MODEL') ?? 'text-embedding-3-small';

async function post(path: string, body: unknown, attempt = 0): Promise<any> {
  const res = await fetch(`${API}${path}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${KEY()}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(90_000),
  });
  if (res.ok) return res.json();
  // Exponential backoff with jitter on rate limits and transient errors.
  if ((res.status === 429 || res.status >= 500) && attempt < 3) {
    const wait = 2 ** attempt * 800 + Math.random() * 400;
    await new Promise((r) => setTimeout(r, wait));
    return post(path, body, attempt + 1);
  }
  throw new Error(`OpenAI ${path} ${res.status}: ${(await res.text()).slice(0, 400)}`);
}

export interface ChatJsonOptions {
  fn: string; // calling function, for usage logs
  system: string;
  user: string;
  schemaName: string;
  schema: Record<string, unknown>;
  userId?: string | null;
  effort?: 'none' | 'low' | 'medium';
  maxTokens?: number;
}

/** Chat completion constrained to a strict JSON schema. */
export async function chatJson<T>(o: ChatJsonOptions): Promise<T> {
  const started = Date.now();
  const data = await post('/chat/completions', {
    model: CHAT_MODEL(),
    reasoning_effort: o.effort ?? 'low',
    max_completion_tokens: o.maxTokens ?? 6000,
    messages: [
      { role: 'system', content: o.system },
      { role: 'user', content: o.user },
    ],
    response_format: {
      type: 'json_schema',
      json_schema: { name: o.schemaName, strict: true, schema: o.schema },
    },
  });
  void logUsage(o.fn, CHAT_MODEL(), data.usage, Date.now() - started, o.userId ?? null, null);
  const content = data.choices?.[0]?.message?.content;
  if (!content) throw new Error('empty completion');
  return JSON.parse(content) as T;
}

/** Embeds texts in batches of 96 (one request per batch). */
export async function embed(texts: string[], fn = 'embed'): Promise<number[][]> {
  const out: number[][] = [];
  for (let i = 0; i < texts.length; i += 96) {
    const batch = texts.slice(i, i + 96).map((t) => t.slice(0, 6000) || ' ');
    const started = Date.now();
    const data = await post('/embeddings', { model: EMBED_MODEL(), input: batch });
    void logUsage(fn, EMBED_MODEL(), data.usage, Date.now() - started, null, null);
    for (const d of data.data) out.push(d.embedding as number[]);
  }
  return out;
}

export async function moderate(
  text: string,
): Promise<{ flagged: boolean; categories: Record<string, boolean>; maxScore: number }> {
  const data = await post('/moderations', { model: 'omni-moderation-latest', input: text.slice(0, 8000) });
  const r = data.results?.[0] ?? {};
  const scores = Object.values(r.category_scores ?? {}) as number[];
  return {
    flagged: !!r.flagged,
    categories: r.categories ?? {},
    maxScore: scores.length ? Math.max(...scores) : 0,
  };
}

export async function logUsage(
  fn: string,
  model: string,
  usage: any,
  latencyMs: number,
  userId: string | null,
  cache: 'exact' | 'semantic' | 'negative' | null,
) {
  try {
    await admin.from('ai_usage_log').insert({
      function_name: fn,
      model,
      prompt_tokens: usage?.prompt_tokens ?? null,
      completion_tokens: usage?.completion_tokens ?? null,
      latency_ms: latencyMs,
      user_id: userId,
      cache,
    });
  } catch (_) {
    // never fail a request because of logging
  }
}

/** pgvector literal from a JS number array. */
export const toVector = (v: number[]) => `[${v.map((x) => x.toFixed(6)).join(',')}]`;
