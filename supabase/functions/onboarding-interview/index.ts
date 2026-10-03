// onboarding-interview — AI follow-ups and the learner profile.
//
//   1st call  {answers}                         → {followups: [{id, q}]}
//   2nd call  {answers, followup_answers, finalize: true}
//                                               → {profile: {...}} (also stored)
// Follow-up questions for similar learner profiles are reused through the
// semantic cache (people with the same background get the same questions).
import { json, readJson, serve } from '../_shared/http.ts';
import { admin, requireUser } from '../_shared/supabase.ts';
import { chatJson } from '../_shared/openai.ts';
import { cached } from '../_shared/semantic_cache.ts';
import {
  INTERVIEW_FOLLOWUP_SCHEMA,
  INTERVIEW_FOLLOWUP_SYSTEM,
  INTERVIEW_PROFILE_SCHEMA,
  INTERVIEW_PROFILE_SYSTEM,
  withLanguage,
} from '../_shared/prompts.ts';

interface Body {
  answers?: Record<string, unknown>;
  followup_answers?: { id: string; q: string; a: string }[];
  finalize?: boolean;
  locale?: string;
}

const describe = (answers: Record<string, unknown>) =>
  Object.entries(answers)
    .filter(([k, v]) => v !== null && v !== '' && k !== 'date_of_birth')
    .map(([k, v]) => `${k}: ${Array.isArray(v) ? v.join(', ') : String(v)}`)
    .join('\n');

serve(async (req) => {
  const { id: userId, client } = await requireUser(req);
  const { answers = {}, followup_answers = [], finalize = false, locale: rawLocale } = await readJson<Body>(
    req,
  );
  const locale = rawLocale === 'en' ? 'en' : 'bn';

  const { error: limitError } = await client.rpc('enforce_rate_limit', {
    p_action: 'interview_ai',
    p_max: 12,
    p_window_seconds: 0,
  });
  if (limitError) throw limitError;

  const summary = describe(answers);

  if (!finalize) {
    // Cache key ignores free-text answers so similar profiles share follow-ups.
    const profileKey = describe(
      Object.fromEntries(
        Object.entries(answers).filter(([k]) => !['challenge', 'university', 'subject', 'name'].includes(k)),
      ),
    );
    const { value } = await cached<{ followups: { id: string; q: string }[] }>(
      {
        namespace: `interview_followups:${locale}`,
        key: profileKey,
        ttlHours: 24 * 30,
        threshold: 0.97,
        fn: 'onboarding-interview',
        userId,
      },
      () =>
        chatJson({
          fn: 'onboarding-interview',
          system: withLanguage(INTERVIEW_FOLLOWUP_SYSTEM, locale),
          user: summary,
          schemaName: 'followups',
          schema: INTERVIEW_FOLLOWUP_SCHEMA,
          userId,
          effort: 'none',
          maxTokens: 800,
        }),
    );
    return json({ followups: value.followups.slice(0, 2) });
  }

  const followText = followup_answers.map((f) => `প্রশ্ন: ${f.q}\nউত্তর: ${f.a}`).join('\n');
  const profile = await chatJson<Record<string, unknown>>({
    fn: 'onboarding-interview',
    system: withLanguage(INTERVIEW_PROFILE_SYSTEM, locale),
    user: `${summary}\n\n${followText}`,
    schemaName: 'learner_profile',
    schema: INTERVIEW_PROFILE_SCHEMA,
    userId,
    maxTokens: 1200,
  });
  const minutes = Number(profile.recommended_daily_minutes);
  profile.recommended_daily_minutes = Number.isFinite(minutes)
    ? Math.min(480, Math.max(60, Math.round(minutes / 15) * 15))
    : 120;

  await admin.from('onboarding_interviews').upsert({
    user_id: userId,
    answers,
    followups: followup_answers,
    ai_profile: profile,
    completed_at: new Date().toISOString(),
  });
  return json({ profile });
});
