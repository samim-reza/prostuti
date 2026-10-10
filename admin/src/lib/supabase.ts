import { createClient } from '@supabase/supabase-js';
import { env } from './env';

/** One client for the whole console: anon key + the signed-in staff member's JWT. */
export const supabase = createClient(
  env.error ? 'https://invalid.supabase.co' : env.supabaseUrl,
  env.error ? 'invalid' : env.supabaseAnonKey,
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: false,
      storageKey: 'prostuti-admin-auth',
    },
    global: { headers: { 'x-client-info': 'prostuti-admin' } },
  },
);

/** Public URL of a file in a public Storage bucket (avatars, post-media). */
export function publicStorageUrl(bucket: string, path: string): string {
  if (/^https?:\/\//i.test(path)) return path;
  return `${env.supabaseUrl}/storage/v1/object/public/${bucket}/${path.split('/').map(encodeURIComponent).join('/')}`;
}
