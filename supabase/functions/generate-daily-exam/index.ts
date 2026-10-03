// generate-daily-exam — builds today's সাম্প্রতিক exam from today's facts.
//
//   facts (today, active; falls back to the last 3 days) ─LLM (strict JSON)─▶
//   validate (4 distinct options, index in range) ─embed─▶ semantic de-dup
//   against the whole bank (pgvector, cos ≥ 0.92) ─▶ questions (kept forever,
//   linked to their fact + source article) ─▶ daily_exams row ─▶ notify.
import { json, readJson, serve } from '../_shared/http.ts';
import { admin, bdToday, requireCronOrStaff } from '../_shared/supabase.ts';
import { chatJson, embed, toVector } from '../_shared/openai.ts';
import { bnDate, bnDigits, mapLimit } from '../_shared/text.ts';
import { EXAM_SCHEMA, EXAM_SYSTEM } from '../_shared/prompts.ts';

interface GenQ {
  fact_id: number;
  topic_code: string;
  stem: string;
  options: string[];
  correct_index: number;
  explanation: string;
  difficulty: number;
}

const TARGET = 15;

serve(async (req) => {
  await requireCronOrStaff(req);
  const { force = false } = await readJson<{ force?: boolean }>(req);
  const today = bdToday();

  const { data: existing } = await admin.from('daily_exams').select('id').eq('exam_date', today)
    .maybeSingle();
  if (existing && !force) return json({ skipped: 'already_exists', exam_id: existing.id });

  let { data: facts } = await admin
    .from('facts')
    .select('id, fact, category, subject_id, source_links')
    .eq('status', 'active')
    .eq('first_seen_date', today)
    .limit(60);
  if ((facts?.length ?? 0) < 8) {
    const { data: recent } = await admin
      .from('facts')
      .select('id, fact, category, subject_id, source_links')
      .eq('status', 'active')
      .gte('first_seen_date', bdToday(-3))
      .order('first_seen_date', { ascending: false })
      .limit(60);
    facts = recent;
  }
  if (!facts?.length) return json({ skipped: 'no_facts' });

  const factById = new Map(facts.map((f) => [f.id, f]));
  const out = await chatJson<{ questions: GenQ[] }>({
    fn: 'generate-daily-exam',
    system: EXAM_SYSTEM,
    user: `${Math.min(TARGET + 5, facts.length)}টি প্রশ্ন তৈরি করো (প্রতি fact থেকে সর্বোচ্চ ১টি)।\n\n` +
      facts.map((f) => `fact_id ${f.id}: ${f.fact}`).join('\n'),
    schemaName: 'daily_exam',
    schema: EXAM_SCHEMA,
    maxTokens: 9000,
  });

  // Structural validation.
  const valid = out.questions.filter((q) =>
    factById.has(q.fact_id) &&
    q.stem?.trim().length > 5 &&
    Array.isArray(q.options) && q.options.length === 4 &&
    new Set(q.options.map((o) => o.trim())).size === 4 &&
    Number.isInteger(q.correct_index) && q.correct_index >= 0 && q.correct_index < 4
  );
  if (!valid.length) return json({ skipped: 'no_valid_questions' });

  // Semantic de-duplication against the existing bank and within the batch.
  const vecs = await embed(
    valid.map((q) => `${q.stem} ${q.options[q.correct_index]}`),
    'generate-daily-exam',
  );
  const keep: number[] = [];
  await mapLimit(valid, 6, async (_, i) => {
    const { data: near } = await admin.rpc('match_questions', {
      p_embedding: toVector(vecs[i]),
      p_threshold: 0.92,
      p_limit: 1,
    });
    if (!(Array.isArray(near) && near.length)) keep.push(i);
  });
  keep.sort((a, b) => a - b);
  const finalIdx: number[] = [];
  for (const i of keep) {
    const dup = finalIdx.some((j) => {
      let dot = 0, na = 0, nb = 0;
      for (let k = 0; k < vecs[i].length; k++) {
        dot += vecs[i][k] * vecs[j][k];
        na += vecs[i][k] ** 2;
        nb += vecs[j][k] ** 2;
      }
      return dot / Math.sqrt(na * nb) > 0.92;
    });
    if (!dup) finalIdx.push(i);
    if (finalIdx.length >= TARGET) break;
  }
  if (finalIdx.length < 5) return json({ skipped: 'too_few_unique', unique: finalIdx.length });

  const [{ data: topics }, { data: source }] = await Promise.all([
    admin.from('topics').select('id, code, subject_id'),
    admin.from('sources').select('id').eq('kind', 'ai_generated').limit(1).single(),
  ]);
  const topicByCode = new Map((topics ?? []).map((t) => [t.code, t]));
  const fallbackTopic = topicByCode.get('bd_current')!;

  const rows = finalIdx.map((i) => {
    const q = valid[i];
    const fact = factById.get(q.fact_id)!;
    const topic = topicByCode.get(q.topic_code) ?? fallbackTopic;
    const link = Array.isArray(fact.source_links) ? fact.source_links[0] : null;
    return {
      subject_id: topic.subject_id,
      topic_id: topic.id,
      stem: q.stem.trim(),
      options: q.options.map((o) => o.trim()),
      correct_index: q.correct_index,
      explanation: q.explanation,
      difficulty: Math.min(5, Math.max(1, q.difficulty || 2)),
      language: 'bn',
      source_id: source?.id ?? null,
      source_ref: `সাম্প্রতিক · ${bnDate(today)}${link?.source ? ` · ${link.source}` : ''}`,
      source_url: link?.url ?? null,
      exam_tags: ['bcs', 'bank'],
      status: 'published',
      review_status: 'unverified',
      fact_id: fact.id,
      embedding: toVector(vecs[i]),
    };
  });

  const { data: inserted, error } = await admin
    .from('questions')
    .upsert(rows, { onConflict: 'stem_hash', ignoreDuplicates: true })
    .select('id');
  if (error) throw error;
  const ids = (inserted ?? []).map((r) => r.id as number);
  if (ids.length < 5) return json({ skipped: 'insert_conflicts', inserted: ids.length });

  const duration = Math.max(8, Math.ceil(ids.length * 0.7));
  const examRow = {
    exam_date: today,
    title_bn: `দৈনিক সাম্প্রতিক পরীক্ষা · ${bnDate(today)}`,
    title_en: `Daily current-affairs exam · ${today}`,
    question_ids: ids,
    duration_minutes: duration,
    negative_mark: 0.5,
    status: 'published',
  };
  const { data: exam, error: examError } = existing
    ? await admin.from('daily_exams').update(examRow).eq('id', existing.id).select('id').single()
    : await admin.from('daily_exams').insert(examRow).select('id').single();
  if (examError) throw examError;

  let notified = 0;
  if ((await admin.rpc('claim_pipeline_run', { p_key: `exam_notify:${today}` })).data === true) {
    const { data } = await admin.rpc('broadcast_notification', {
      p_type: 'daily_exam',
      p_title: 'আজকের সাম্প্রতিক পরীক্ষা শুরু 📝',
      p_body: `${bnDigits(ids.length)}টি প্রশ্ন, ${bnDigits(duration)} মিনিট। লিডারবোর্ডে নিজের অবস্থান দেখুন!`,
      p_data: { route: '/daily-exam' },
      p_category: 'exam',
      p_active_days: 30,
      p_title_en: "Today's current-affairs exam is live 📝",
      p_body_en: `${ids.length} questions, ${duration} minutes. See where you rank on the leaderboard!`,
    });
    notified = Number(data ?? 0);
  }

  return json({
    exam_id: exam.id,
    generated: out.questions.length,
    valid: valid.length,
    unique: ids.length,
    notified,
  });
});
