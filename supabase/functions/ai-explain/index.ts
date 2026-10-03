// ai-explain — explains a question's answer in the user's language.
//
// Guards: signed-in user, feature `ai_explain` (free users get a daily quota,
// enforced in Postgres), and the user must already have seen the answer
// (practised / revealed / submitted an exam with it) — no answer leaks.
// Caching: exact (question + locale) and semantic (similar question text)
// via the shared pgvector cache, plus ai_explanations for the Bangla default.
import { HttpError, json, readJson, serve } from '../_shared/http.ts';
import { admin, requireUser } from '../_shared/supabase.ts';
import { chatJson } from '../_shared/openai.ts';
import { cached } from '../_shared/semantic_cache.ts';
import { EXPLAIN_SCHEMA, EXPLAIN_SYSTEM, withLanguage } from '../_shared/prompts.ts';

serve(async (req) => {
  const { id: userId, client } = await requireUser(req);
  const body = await readJson<{ question_id?: number; locale?: string }>(req);
  const questionId = Number(body.question_id);
  const locale = body.locale === 'en' ? 'en' : 'bn';
  if (!Number.isFinite(questionId)) throw new HttpError(400, 'invalid_question');

  // Entitlement / quota check runs as the user (raises PT402 / PT429).
  const { error: featureError } = await client.rpc('require_feature', { p_feature: 'ai_explain' });
  if (featureError) throw featureError;

  const { data: seen } = await admin
    .from('question_attempts')
    .select('id')
    .eq('user_id', userId)
    .eq('question_id', questionId)
    .limit(1);
  if (!seen?.length) {
    // Skipped questions of a submitted exam are reviewable too.
    const { data: session } = await admin
      .from('exam_sessions')
      .select('id')
      .eq('user_id', userId)
      .eq('status', 'submitted')
      .contains('question_ids', [questionId])
      .limit(1);
    if (!session?.length) throw new HttpError(403, 'answer_not_seen');
  }

  const { data: q } = await admin
    .from('questions')
    .select('id, stem, options, correct_index, explanation, language')
    .eq('id', questionId)
    .single();
  if (!q) throw new HttpError(404, 'question_not_found');

  if (locale === 'bn') {
    const { data: stored } = await admin.from('ai_explanations').select('explanation').eq(
      'question_id',
      questionId,
    ).maybeSingle();
    if (stored) {
      const parsed = JSON.parse(stored.explanation);
      return json({ ...parsed, cached: 'stored' });
    }
  }

  const options = (q.options as string[]).map((o, i) => `${'কখগঘঙ'[i]}) ${o}`).join('\n');
  const prompt = `প্রশ্ন: ${q.stem}\n${options}\nসঠিক উত্তর: ${(q.options as string[])[q.correct_index]}` +
    (q.explanation ? `\nসংক্ষিপ্ত ব্যাখ্যা: ${q.explanation}` : '');

  const { value, hit } = await cached<{ explanation: string; memory_tip: string }>(
    {
      namespace: `explain:${locale}`,
      key: prompt,
      ttlHours: 24 * 90,
      threshold: 0.975,
      fn: 'ai-explain',
      userId,
    },
    () =>
      chatJson({
        fn: 'ai-explain',
        system: withLanguage(EXPLAIN_SYSTEM, locale),
        user: prompt,
        schemaName: 'explanation',
        schema: EXPLAIN_SCHEMA,
        userId,
        maxTokens: 1500,
      }),
  );

  if (locale === 'bn' && !hit) {
    await admin.from('ai_explanations').upsert({
      question_id: questionId,
      explanation: JSON.stringify(value),
      model: Deno.env.get('OPENAI_MODEL'),
    });
  }
  return json({ ...value, cached: hit });
});
