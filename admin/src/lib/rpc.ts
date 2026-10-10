import { toApiError } from './errors';
import { supabase } from './supabase';

/**
 * Calls a Postgres function through PostgREST. Authorization happens inside
 * the function (is_admin() / is_staff()); this is only transport + typing.
 */
export async function rpc<T>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) throw toApiError(error);
  return data as T;
}

/** Drops undefined / empty-string values so SQL defaults apply. */
export function clean(args: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(args)) {
    if (v === undefined || v === '') continue;
    out[k] = v;
  }
  return out;
}

/** Runs async jobs over chunks sequentially (bulk import / export). */
export async function inChunks<T, R>(items: T[], size: number, job: (chunk: T[], index: number) => Promise<R>): Promise<R[]> {
  const results: R[] = [];
  for (let i = 0; i < items.length; i += size) {
    results.push(await job(items.slice(i, i + size), i / size));
  }
  return results;
}
