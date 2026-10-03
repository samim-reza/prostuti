// HTTP helpers shared by every Edge Function.

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cron-secret',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
  });
}

/** Error with an HTTP status and a machine-readable code (mirrors the app's AppFailure codes). */
export class HttpError extends Error {
  constructor(public status: number, public code: string, public extra: Record<string, unknown> = {}) {
    super(code);
  }
}

/** Wraps a handler: CORS preflight, JSON errors, timing. */
export function serve(handler: (req: Request) => Promise<Response>) {
  Deno.serve(async (req) => {
    if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
    const started = Date.now();
    try {
      return await handler(req);
    } catch (e) {
      if (e instanceof HttpError) return json({ error: e.code, ...e.extra }, e.status);
      // Postgres errors raised by RPCs (rate limits, locked features…)
      const pg = e as { code?: string; message?: string; details?: string; hint?: string };
      if (pg?.code === 'PT429') {
        const retry = /retry_after:(\d+)/.exec(pg.hint ?? '')?.[1];
        return json({ error: 'rate_limited', retry_after: retry ? Number(retry) : null }, 429);
      }
      if (pg?.code === 'PT402') return json({ error: 'feature_locked', feature: pg.details }, 402);
      console.error('Unhandled error', e);
      return json({ error: 'server_error', message: String((e as Error)?.message ?? e) }, 500);
    } finally {
      console.log(`${new URL(req.url).pathname} took ${Date.now() - started}ms`);
    }
  });
}

export async function readJson<T = Record<string, unknown>>(req: Request): Promise<T> {
  try {
    return (await req.json()) as T;
  } catch {
    return {} as T;
  }
}
