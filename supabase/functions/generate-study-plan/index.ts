// generate-study-plan — creates or re-creates a learner's plan.
//
//   mode "create" (user JWT): plan for the caller (feature ai_study_plan).
//   mode "jobs"   (cron / pg_net): process plan_replan_jobs, e.g. after the
//                 exam date changed or the user changed their daily time.
//
// Scheduling is deterministic (scheduler.ts); the LLM only writes short
// personalised tips, cached semantically by learner profile.
import { HttpError, json, readJson, serve } from '../_shared/http.ts';
import { admin, bdToday, requireCron, requireUser } from '../_shared/supabase.ts';
import { chatJson } from '../_shared/openai.ts';
import { cached } from '../_shared/semantic_cache.ts';
import { PLAN_TIPS_SCHEMA, PLAN_TIPS_SYSTEM, withLanguage } from '../_shared/prompts.ts';
import { buildPlan, daysBetween } from './scheduler.ts';

const DEFAULT_TIPS: Record<string, string[]> = {
  bn: [
    'প্রতিদিন একই সময়ে পড়তে বসুন — অভ্যাসই সাফল্যের চাবি।',
    'দৈনিক সাম্প্রতিক নোট পড়া কখনো বাদ দেবেন না।',
    'ভুল করা প্রশ্নগুলো সপ্তাহে অন্তত একবার রিভিশন দিন।',
    'মডেল টেস্টে সময় ধরে উত্তর দিন, অনিশ্চিত হলে এড়িয়ে যান।',
    'গণিত ও ইংরেজিতে প্রতিদিন অল্প হলেও অনুশীলন করুন।',
  ],
  en: [
    'Study at the same time every day — consistency wins.',
    'Never skip the daily current-affairs notes.',
    'Revise your wrong answers at least once a week.',
    'Time yourself in model tests and skip questions you are unsure about.',
    'Practise a little Math and English every single day.',
  ],
};

async function planFor(userId: string, reason: string, localeOverride?: string) {
  const { data: profile } = await admin
    .from('profiles')
    .select('id, daily_study_minutes, target_schedule_id, locale')
    .eq('id', userId)
    .single();
  if (!profile) throw new HttpError(404, 'profile_not_found');
  const locale = (localeOverride ?? profile.locale) === 'en' ? 'en' : 'bn';

  let scheduleId = profile.target_schedule_id as number | null;
  if (!scheduleId) {
    const { data: cfg } = await admin.from('app_config').select('value').eq('key', 'default_schedule_id')
      .maybeSingle();
    scheduleId = Number(cfg?.value ?? 0) || null;
  }
  const { data: schedule } = scheduleId
    ? await admin.from('exam_schedules').select('id, expected_date').eq('id', scheduleId).maybeSingle()
    : { data: null };
  const today = bdToday();
  const examDate = (schedule?.expected_date as string | undefined) ??
    new Date(Date.now() + 180 * 86400_000).toISOString().slice(0, 10);
  if (daysBetween(today, examDate) < 3) throw new HttpError(400, 'exam_too_close');

  const [{ data: subjects }, { data: topics }, { data: mastery }, { data: levels }, { data: interview }] =
    await Promise.all([
      admin.from('subjects').select('id, code, name_bn, name_en, bcs_marks'),
      admin.from('topics').select('id, subject_id, name_bn, name_en, weight, is_general'),
      admin.from('user_topic_mastery').select('topic_id, mastery').eq('user_id', userId),
      admin.from('user_subject_levels').select('subject_id, level, score_pct').eq('user_id', userId),
      admin.from('onboarding_interviews').select('answers, ai_profile').eq('user_id', userId).maybeSingle(),
    ]);

  const { days, summary } = buildPlan({
    startDate: today,
    examDate,
    dailyMinutes: profile.daily_study_minutes ?? 120,
    subjects: subjects ?? [],
    topics: (topics ?? []).map((t) => ({ ...t, weight: Number(t.weight) })),
    mastery: new Map((mastery ?? []).map((m) => [m.topic_id, Number(m.mastery)])),
  });

  // Personalised tips (semantic-cached by profile shape).
  const subjectName = new Map((subjects ?? []).map((s) => [s.id, locale === 'en' ? s.name_en : s.name_bn]));
  const levelText = (levels ?? []).map((l) => `${subjectName.get(l.subject_id)}: ${l.level}`).join(', ');
  const weak = Array.isArray((interview?.answers as Record<string, unknown> | null)?.weak_subjects)
    ? ((interview!.answers as Record<string, unknown>).weak_subjects as string[]).join(', ')
    : '';
  const profileKey =
    `levels: ${levelText || 'unknown'}\ndays_left_bucket: ${Math.round(days.length / 30)}\n` +
    `daily_minutes_bucket: ${Math.round((profile.daily_study_minutes ?? 120) / 30) * 30}\nweak: ${weak}`;
  let tips = DEFAULT_TIPS[locale];
  try {
    const { value } = await cached<{ tips: string[] }>(
      {
        namespace: `plan_tips:${locale}`,
        key: profileKey,
        ttlHours: 24 * 14,
        threshold: 0.96,
        fn: 'generate-study-plan',
        userId,
      },
      () =>
        chatJson({
          fn: 'generate-study-plan',
          system: withLanguage(PLAN_TIPS_SYSTEM, locale),
          user: profileKey +
            (interview?.ai_profile ? `\nprofile: ${JSON.stringify(interview.ai_profile)}` : ''),
          schemaName: 'plan_tips',
          schema: PLAN_TIPS_SCHEMA,
          userId,
          effort: 'none',
          maxTokens: 700,
        }),
    );
    if (value.tips?.length) tips = value.tips.slice(0, 5);
  } catch (e) {
    console.error('tips failed, using defaults', e);
  }

  // Supersede the current plan (its past days stay as history).
  const { data: current } = await admin.from('study_plans').select('id, version').eq('user_id', userId).eq(
    'status',
    'active',
  ).maybeSingle();
  if (current) await admin.from('study_plans').update({ status: 'superseded' }).eq('id', current.id);

  const { data: plan, error } = await admin.from('study_plans').insert({
    user_id: userId,
    schedule_id: schedule?.id ?? null,
    exam_date: examDate,
    start_date: today,
    daily_minutes: profile.daily_study_minutes ?? 120,
    status: 'active',
    version: (current?.version ?? 0) + 1,
    summary: { ...summary, reason },
    ai_tips: tips,
    generated_by: 'scheduler-v1',
  }).select('id, exam_date, start_date, version').single();
  if (error) throw error;

  const rows = days.map((d) => ({ ...d, plan_id: plan.id, user_id: userId }));
  for (let i = 0; i < rows.length; i += 100) {
    const { error: e } = await admin.from('study_plan_days').insert(rows.slice(i, i + 100));
    if (e) throw e;
  }
  return { plan_id: plan.id, version: plan.version, exam_date: plan.exam_date, days: rows.length };
}

serve(async (req) => {
  const body = await readJson<{ mode?: string; locale?: string; reason?: string }>(req);
  if (body.mode === 'jobs') {
    requireCron(req);
    const { data: jobs } = await admin
      .from('plan_replan_jobs')
      .select('id, user_id, reason')
      .is('processed_at', null)
      .order('created_at')
      .limit(25);
    const byUser = new Map<string, { ids: number[]; reason: string }>();
    for (const j of jobs ?? []) {
      const entry = byUser.get(j.user_id) ?? { ids: [] as number[], reason: j.reason as string };
      entry.ids.push(j.id);
      byUser.set(j.user_id, entry);
    }
    const results = [];
    for (const [userId, { ids, reason }] of byUser) {
      let error: string | null = null;
      try {
        results.push(await planFor(userId, reason));
      } catch (e) {
        error = String((e as Error).message ?? e).slice(0, 300);
      }
      await admin.from('plan_replan_jobs').update({ processed_at: new Date().toISOString(), error }).in(
        'id',
        ids,
      );
    }
    return json({ processed: byUser.size, results });
  }

  const { id: userId, client } = await requireUser(req);
  const { error: featureError } = await client.rpc('require_feature', { p_feature: 'ai_study_plan' });
  if (featureError) throw featureError;
  const { error: limitError } = await client.rpc('enforce_rate_limit', {
    p_action: 'plan_create',
    p_max: 6,
    p_window_seconds: 0,
  });
  if (limitError) throw limitError;
  return json(await planFor(userId, body.reason ?? 'create', body.locale));
});
