/**
 * Runtime configuration. Both values are public by design: the anon /
 * publishable key only works together with Row Level Security, and every
 * admin rule lives in Postgres. A service-role or secret key must never be
 * shipped to a browser, so the console refuses to start with one.
 */
const url = (import.meta.env.VITE_SUPABASE_URL ?? '').trim();
const anonKey = (import.meta.env.VITE_SUPABASE_ANON_KEY ?? '').trim();

function jwtRole(key: string): string | null {
  const part = key.split('.')[1];
  if (!part) return null;
  try {
    const json = atob(part.replace(/-/g, '+').replace(/_/g, '/'));
    const payload = JSON.parse(json) as { role?: unknown };
    return typeof payload.role === 'string' ? payload.role : null;
  } catch {
    return null;
  }
}

function configError(): string | null {
  if (!url || !anonKey) {
    return 'VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY are not set. Copy admin/.env.example to admin/.env.local (or set them in Vercel) and rebuild.';
  }
  const base = url.replace(/\/$/, '');
  // https everywhere; plain http only for a local Supabase stack (supabase start).
  if (!/^https:\/\/[^\s/]+$/.test(base) && !/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(base)) {
    return 'VITE_SUPABASE_URL must look like https://<project-ref>.supabase.co';
  }
  if (anonKey.startsWith('sb_secret_') || jwtRole(anonKey) === 'service_role') {
    return 'VITE_SUPABASE_ANON_KEY is a secret/service-role key. Use the anon (publishable) key; the service-role key must never reach a browser.';
  }
  return null;
}

export const env = {
  supabaseUrl: url.replace(/\/$/, ''),
  supabaseAnonKey: anonKey,
  error: configError(),
} as const;
