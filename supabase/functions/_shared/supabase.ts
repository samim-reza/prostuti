import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { HttpError } from './http.ts';

const url = Deno.env.get('SUPABASE_URL')!;
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;

/** Service-role client: bypasses RLS. Only for trusted server-side work. */
export const admin: SupabaseClient = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

/** Client acting as the calling user (RLS + auth.uid() apply). */
export function userClient(req: Request): SupabaseClient {
  const authorization = req.headers.get('Authorization') ?? '';
  return createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** Resolves the calling user or throws 401. */
export async function requireUser(req: Request): Promise<{ id: string; client: SupabaseClient }> {
  const client = userClient(req);
  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!token) throw new HttpError(401, 'not_authenticated');
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) throw new HttpError(401, 'not_authenticated');
  return { id: data.user.id, client };
}

/** Cron / pg_net callers must present the shared secret (constant-time compare). */
export function requireCron(req: Request) {
  const expected = Deno.env.get('CRON_SECRET') ?? '';
  const got = req.headers.get('x-cron-secret') ?? '';
  if (!expected || got.length !== expected.length) throw new HttpError(401, 'invalid_cron_secret');
  let diff = 0;
  for (let i = 0; i < got.length; i++) diff |= got.charCodeAt(i) ^ expected.charCodeAt(i);
  if (diff !== 0) throw new HttpError(401, 'invalid_cron_secret');
}

/** Either a cron call or a staff user (admin "run pipeline" button). */
export async function requireCronOrStaff(req: Request) {
  if (req.headers.get('x-cron-secret')) return requireCron(req);
  const { id } = await requireUser(req);
  const { data } = await admin.from('profiles').select('role').eq('id', id).single();
  if (!data || !['admin', 'moderator'].includes(data.role)) throw new HttpError(403, 'forbidden');
}

/** Bangladesh calendar date (UTC+6) as YYYY-MM-DD. */
export function bdToday(offsetDays = 0): string {
  const d = new Date(Date.now() + 6 * 3600_000 + offsetDays * 86400_000);
  return d.toISOString().slice(0, 10);
}

/** Current Bangladesh wall-clock time as minutes since midnight. */
export function bdMinutesNow(): number {
  const d = new Date(Date.now() + 6 * 3600_000);
  return d.getUTCHours() * 60 + d.getUTCMinutes();
}
