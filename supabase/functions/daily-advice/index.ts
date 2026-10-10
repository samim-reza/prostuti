// daily-advice — "প্রস্তুতি এআই-এর পরামর্শ": 3–5 fresh tips per Bangladesh
// day, built from the learner's own data (weak topics, last-7-day exams and
// routine, streak, days left, today's routine / notes / daily exam).
//
//   POST { locale?: 'bn' | 'en', refresh?: boolean }   (user JWT)
//
// 1. Today's stored row is returned as is (the app normally reads it through
//    the get_daily_advice RPC and only calls this function when it is null).
// 2. Otherwise the signals are computed (SQL daily_advice_signals) and turned
//    into a bucketed signature. refresh=true with an unchanged signature
//    returns the stored row without spending a refresh.
// 3. Tips come from the shared LLM cache keyed by (day, signature) — learners
//    in the same situation share one completion — else from the model, and
//    from deterministic rules when there is no AI or it fails.
// Limits (per BD day): 5 computations, of which 3 may be refreshes.
import { json, readJson, serve } from '../_shared/http.ts';
import { admin, bdToday, requireUser } from '../_shared/supabase.ts';
import { chatJson } from '../_shared/openai.ts';
import { cached } from '../_shared/semantic_cache.ts';
import { withLanguage } from '../_shared/prompts.ts';
import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import {
  ADVICE_SCHEMA,
  ADVICE_SYSTEM,
  buildPrompt,
  compactStats,
  fallbackTips,
  type Locale,
  normalizeSignals,
  type RawTip,
  sanitizeTips,
  signature,
  type Tip,
} from './advice.ts';

const MAX_PER_DAY = 5;
const MAX_REFRESHES_PER_DAY = 3;
const COLUMNS = 'advice_date, locale, tips, stats, created_at';

/** Shared fixed-window limiter, as the caller (window 0 = one BD day). */
async function limit(client: SupabaseClient, action: string, max: number) {
  const { error } = await client.rpc('enforce_rate_limit', {
    p_action: action,
    p_max: max,
    p_window_seconds: 0,
  });
  if (error) throw error;
}

serve(async (req) => {
  const { id: userId, client } = await requireUser(req);
  const body = await readJson<{ locale?: string; refresh?: boolean }>(req);
  const locale: Locale = body.locale === 'en' ? 'en' : 'bn';
  const refresh = body.refresh === true;
  const today = bdToday();

  const { data: stored } = await admin
    .from('ai_daily_advice')
    .select(COLUMNS)
    .eq('user_id', userId)
    .eq('advice_date', today)
    .eq('locale', locale)
    .maybeSingle();
  if (stored && !refresh) return json({ ...stored, cached: 'stored' });

  await limit(client, 'daily_advice', MAX_PER_DAY);

  const { data: raw, error: signalsError } = await admin.rpc('daily_advice_signals', { p_user: userId });
  if (signalsError) throw signalsError;
  const signals = normalizeSignals(raw);
  // Nothing to base advice on yet: the app hides the card. Not stored, so
  // the first practice/exam of the day can still produce advice.
  if (!signals.has_data) {
    return json({ advice_date: today, locale, tips: [], stats: { has_data: false }, created_at: null });
  }

  const sig = signature(signals, locale);
  const previous = (stored?.stats ?? {}) as Record<string, unknown>;
  if (stored && previous.signature === sig && previous.source !== 'fallback') {
    return json({ ...stored, cached: 'unchanged' });
  }
  if (stored) await limit(client, 'daily_advice_refresh', MAX_REFRESHES_PER_DAY);

  let tips: Tip[];
  let source: 'ai' | 'cache' | 'fallback';
  if (!Deno.env.get('OPENAI_API_KEY')) {
    tips = fallbackTips(signals, locale);
    source = 'fallback';
  } else {
    try {
      const { value, hit } = await cached<{ tips: RawTip[] }>(
        {
          namespace: `daily_advice:${locale}`,
          key: `${today}|${sig}`,
          ttlHours: 26,
          // An empty answer is not reused for long (rules fill in meanwhile).
          isNegative: (v) => !Array.isArray(v?.tips) || v.tips.length === 0,
          negativeTtlHours: 1,
          fn: 'daily-advice',
          userId,
        },
        () =>
          chatJson({
            fn: 'daily-advice',
            system: withLanguage(ADVICE_SYSTEM, locale),
            user: buildPrompt(signals, locale),
            schemaName: 'daily_advice',
            schema: ADVICE_SCHEMA,
            userId,
            effort: 'low',
            maxTokens: 2500,
          }),
      );
      tips = sanitizeTips(value.tips, signals, locale);
      source = hit ? 'cache' : 'ai';
    } catch (e) {
      console.error('daily advice: AI failed, using rules', e);
      tips = fallbackTips(signals, locale);
      source = 'fallback';
    }
  }

  const row = {
    user_id: userId,
    advice_date: today,
    locale,
    tips,
    stats: { ...compactStats(signals), signature: sig, source },
    created_at: new Date().toISOString(),
  };
  const { error: saveError } = await admin
    .from('ai_daily_advice')
    .upsert(row, { onConflict: 'user_id,advice_date,locale' });
  // The learner still gets today's advice; the next open simply recomputes.
  if (saveError) console.error('daily advice: save failed', saveError);

  const { user_id: _, ...out } = row;
  return json({ ...out, cached: source === 'cache' ? 'exact' : null });
});
