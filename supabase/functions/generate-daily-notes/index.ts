// generate-daily-notes — turns the last day's news into exam-ready notes.
//
//   articles (unprocessed, ≤30 h) ──embed──▶ leader clustering (same story
//   across outlets) ──rank──▶ top clusters ──LLM (structured JSON, parallel
//   chunks)──▶ notes + facts ──fact de-dup/supersede (pgvector + LLM judge)──▶
//   daily_notes (today) + facts (permanent) ──▶ notify users (morning run)
//
// Modes: "morning" (05:20 BD), "append" (15:30 BD top-up, skips stories
// already covered today), "manual" (admin button).
import { json, readJson, serve } from '../_shared/http.ts';
import { admin, bdToday, requireCronOrStaff } from '../_shared/supabase.ts';
import { chatJson, embed, toVector } from '../_shared/openai.ts';
import { bnDate, cosine, leaderCluster, mapLimit } from '../_shared/text.ts';
import {
  NOTES_SCHEMA,
  NOTES_SYSTEM,
  SUPERSEDE_SCHEMA,
  SUPERSEDE_SYSTEM,
  TRIAGE_SCHEMA,
  TRIAGE_SYSTEM,
} from '../_shared/prompts.ts';

interface Article {
  id: number;
  title: string;
  summary: string | null;
  url: string;
  published_at: string;
  source_id: number;
  vec: number[];
}
interface NoteOut {
  cluster: number;
  relevant: boolean;
  category: string;
  subject_code: string;
  title: string;
  title_en: string;
  summary: string;
  summary_en: string;
  importance: number;
  facts: { fact: string; fact_en: string; entity: string; is_time_sensitive: boolean }[];
  probable_questions: { q: string; a: string; q_en: string; a_en: string }[];
}

const MAX_CLUSTERS = 32;

const CHUNK = 9;

serve(async (req) => {
  await requireCronOrStaff(req);
  const { mode = 'manual' } = await readJson<{ mode?: string }>(req);
  const today = bdToday();

  const { data: sources } = await admin.from('news_sources').select('id, name, priority, region');
  const sourceById = new Map((sources ?? []).map((s) => [s.id, s]));

  const since = new Date(Date.now() - 30 * 3600_000).toISOString();
  const { data: rows } = await admin
    .from('news_articles')
    .select('id, title, summary, url, published_at, source_id')
    .is('processed_at', null)
    .gte('fetched_at', since)
    .order('published_at', { ascending: false })
    .limit(600);
  if (!rows?.length) return json({ notes: 0, reason: 'no_new_articles' });

  // 1) Embed (title + summary) and persist the vectors.
  const vectors = await embed(rows.map((r) => `${r.title}\n${r.summary ?? ''}`), 'generate-daily-notes');
  const articles: Article[] = rows.map((r, i) => ({ ...r, vec: vectors[i] }));
  await mapLimit(articles, 8, async (a) => {
    await admin.from('news_articles').update({ embedding: toVector(a.vec) }).eq('id', a.id);
  });

  // 2) Cluster the same story across newspapers.
  // 0.80 merges the same story across Bangla and English outlets.
  let clusters = leaderCluster(articles, (a) => a.vec, 0.8);

  // In append mode, drop stories already covered by today's notes.
  if (mode === 'append') {
    const { data: existing } = await admin.from('daily_notes').select('embedding').eq('note_date', today);
    const existingVecs = (existing ?? [])
      .map((e) =>
        (typeof e.embedding === 'string' ? JSON.parse(e.embedding) : e.embedding) as number[] | null
      )
      .filter((v): v is number[] => Array.isArray(v));
    clusters = clusters.filter((c) => !existingVecs.some((v) => cosine(v, c[0].vec) > 0.86));
  }

  // 3) Triage: one cheap, titles-only LLM pass over every story picks the
  //    exam-relevant ones (far better than ranking by coverage alone).
  const rankScore = (c: Article[]) => {
    const outlets = new Set(c.map((a) => a.source_id)).size;
    const prio = Math.max(...c.map((a) => sourceById.get(a.source_id)?.priority ?? 5));
    return outlets * 2 + prio / 3;
  };
  const pool = clusters.sort((a, b) => rankScore(b) - rankScore(a)).slice(0, 260);
  let top: Article[][];
  try {
    const triage = await chatJson<{ selected: { cluster: number; mcq: string; importance: number }[] }>({
      fn: 'generate-daily-notes',
      system: TRIAGE_SYSTEM,
      user: pool.map((c, i) => `cluster ${i}: [${sourceById.get(c[0].source_id)?.name ?? ''}] ${c[0].title}`)
        .join('\n'),
      schemaName: 'triage',
      schema: TRIAGE_SCHEMA,
      effort: 'low',
      maxTokens: 6000,
    });
    top = triage.selected
      .filter((s) => pool[s.cluster] && s.importance >= 3)
      .sort((a, b) => b.importance - a.importance)
      .slice(0, MAX_CLUSTERS)
      .map((s) => pool[s.cluster]);
  } catch (e) {
    console.error('triage failed, falling back to coverage ranking', e);
    top = pool.slice(0, MAX_CLUSTERS);
  }

  // 4) LLM extraction in parallel chunks.
  const chunks: Article[][][] = [];
  for (let i = 0; i < top.length; i += CHUNK) chunks.push(top.slice(i, i + CHUNK));
  const outputs = await mapLimit(chunks, 3, async (chunk, ci) => {
    const text = chunk.map((cluster, j) => {
      const idx = ci * CHUNK + j;
      const lines = cluster.slice(0, 4).map((a) =>
        `- [${sourceById.get(a.source_id)?.name ?? ''}] ${a.title}. ${(a.summary ?? '').slice(0, 400)}`
      );
      return `### cluster ${idx}\n${lines.join('\n')}`;
    }).join('\n\n');
    try {
      const out = await chatJson<{ notes: NoteOut[] }>({
        fn: 'generate-daily-notes',
        system: NOTES_SYSTEM,
        user: `তারিখ: ${bnDate(today)}\n\n${text}`,
        schemaName: 'daily_notes',
        schema: NOTES_SCHEMA,
        maxTokens: 9000,
      });
      return out.notes;
    } catch (e) {
      console.error('chunk failed', ci, e);
      return [] as NoteOut[];
    }
  });
  const candidates = outputs.flat()
    .filter((n) => n.relevant && n.importance >= 2 && n.facts.length > 0 && top[n.cluster])
    .sort((a, b) => b.importance - a.importance);

  // Semantic de-duplication of notes produced in this run (different clusters
  // can still describe the same development): keep the more important one.
  const candidateVecs = candidates.length
    ? await embed(
      candidates.map((n) =>
        `${n.title_en || n.title}
${n.summary_en || n.summary}`
      ),
      'generate-daily-notes',
    )
    : [];
  const notes: NoteOut[] = [];
  const noteVecs: number[][] = [];
  candidates.forEach((n, i) => {
    if (notes.length >= 18) return;
    if (noteVecs.some((v) => cosine(v, candidateVecs[i]) > 0.82)) return;
    notes.push(n);
    noteVecs.push(candidateVecs[i]);
  });

  // 5) Facts: embed, then duplicate / supersede / new.
  const { data: subjects } = await admin.from('subjects').select('id, code');
  const subjectId = new Map((subjects ?? []).map((s) => [s.code, s.id]));
  const factInputs = notes.flatMap((n) => n.facts.map((f) => ({ note: n, f })));
  const factVecs = factInputs.length
    ? await embed(factInputs.map((x) => x.f.fact_en || x.f.fact), 'generate-daily-notes')
    : [];

  type Ambiguous = { idx: number; oldId: number; oldFact: string };
  const ambiguous: Ambiguous[] = [];
  const decisions = new Map<number, { kind: 'duplicate' | 'new' | 'supersedes'; oldId?: number }>();
  await mapLimit(factInputs, 6, async (_x, i) => {
    const { data: near } = await admin.rpc('match_facts', {
      p_embedding: toVector(factVecs[i]),
      p_threshold: 0.86,
      p_limit: 1,
    });
    const best = Array.isArray(near) ? near[0] : null;
    if (!best) decisions.set(i, { kind: 'new' });
    else if (best.similarity >= 0.94) decisions.set(i, { kind: 'duplicate', oldId: best.id });
    else ambiguous.push({ idx: i, oldId: best.id, oldFact: best.fact });
  });
  if (ambiguous.length) {
    try {
      const judged = await chatJson<{ decisions: { pair: number; verdict: string }[] }>({
        fn: 'generate-daily-notes',
        system: SUPERSEDE_SYSTEM,
        user: ambiguous.map((a, p) => `pair ${p}\nold: ${a.oldFact}\nnew: ${factInputs[a.idx].f.fact}`).join(
          '\n\n',
        ),
        schemaName: 'supersede',
        schema: SUPERSEDE_SCHEMA,
        effort: 'none',
      });
      for (const d of judged.decisions) {
        const a = ambiguous[d.pair];
        if (!a) continue;
        decisions.set(
          a.idx,
          d.verdict === 'duplicate'
            ? { kind: 'duplicate', oldId: a.oldId }
            : d.verdict === 'supersedes'
            ? { kind: 'supersedes', oldId: a.oldId }
            : { kind: 'new' },
        );
      }
    } catch (_) {
      for (const a of ambiguous) decisions.set(a.idx, { kind: 'new' });
    }
  }

  const sourceLinks = (cluster: Article[]) =>
    cluster.slice(0, 4).map((a) => ({
      title: a.title,
      url: a.url,
      source: sourceById.get(a.source_id)?.name ?? '',
    }));

  const factIdsByNote = new Map<NoteOut, number[]>();
  let superseded = 0, duplicates = 0, created = 0;
  for (let i = 0; i < factInputs.length; i++) {
    const { note, f } = factInputs[i];
    const d = decisions.get(i) ?? { kind: 'new' as const };
    const cluster = top[note.cluster];
    if (d.kind === 'duplicate' && d.oldId) {
      duplicates++;
      await admin.from('facts').update({ last_confirmed_date: today }).eq('id', d.oldId);
      factIdsByNote.set(note, [...(factIdsByNote.get(note) ?? []), d.oldId]);
      continue;
    }
    const { data: inserted } = await admin.from('facts').insert({
      fact: f.fact,
      fact_en: f.fact_en,
      category: note.category,
      subject_id: subjectId.get(note.subject_code) ?? null,
      entity: f.entity,
      is_time_sensitive: f.is_time_sensitive,
      first_seen_date: today,
      last_confirmed_date: today,
      source_links: sourceLinks(cluster),
      source_article_ids: cluster.map((a) => a.id),
      embedding: toVector(factVecs[i]),
    }).select('id').single();
    if (!inserted) continue;
    created++;
    if (d.kind === 'supersedes' && d.oldId) {
      superseded++;
      // trigger facts_after_status_change archives questions built on the old fact
      await admin.from('facts').update({
        status: 'superseded',
        superseded_by: inserted.id,
        superseded_at: new Date().toISOString(),
      }).eq('id', d.oldId);
    }
    factIdsByNote.set(note, [...(factIdsByNote.get(note) ?? []), inserted.id]);
  }

  // 6) Notes for today.
  const noteRows = notes.map((n, i) => ({
    note_date: today,
    category: n.category,
    title: n.title,
    title_en: n.title_en,
    summary: n.summary,
    summary_en: n.summary_en,
    key_facts: n.facts.map((f) => ({ fact: f.fact, tag: f.entity })),
    key_facts_en: n.facts.map((f) => ({ fact: f.fact_en })), // entity names are Bangla; no tag in English
    probable_questions: n.probable_questions.map((q) => ({ q: q.q, a: q.a })),
    probable_questions_en: n.probable_questions.map((q) => ({ q: q.q_en, a: q.a_en })),
    importance: Math.min(5, Math.max(1, Math.round(n.importance))),
    source_links: sourceLinks(top[n.cluster]),
    source_article_ids: top[n.cluster].map((a) => a.id),
    fact_ids: factIdsByNote.get(n) ?? [],
    embedding: toVector(noteVecs[i]),
    model: Deno.env.get('OPENAI_MODEL') ?? 'gpt-5.4-mini',
  }));
  if (noteRows.length) {
    const { error } = await admin.from('daily_notes').insert(noteRows);
    if (error) throw error;
  }

  // 7) Mark every fetched article as processed (relevant or not).
  const ids = articles.map((a) => a.id);
  for (let i = 0; i < ids.length; i += 200) {
    await admin.from('news_articles').update({ processed_at: new Date().toISOString() }).in(
      'id',
      ids.slice(i, i + 200),
    );
  }

  // 8) Tell users (first run of the day only).
  let notified = 0;
  if (
    noteRows.length &&
    (await admin.rpc('claim_pipeline_run', { p_key: `notes_notify:${today}` })).data === true
  ) {
    const { data } = await admin.rpc('broadcast_notification', {
      p_type: 'daily_notes',
      p_title: 'আজকের সাম্প্রতিক নোট প্রস্তুত 📰',
      p_body: `${bnDate(today)} — ${noteRows.length}টি গুরুত্বপূর্ণ নোট। শুধু আজকের জন্য!`,
      p_data: { route: '/notes' },
      p_category: 'daily_notes',
      p_active_days: 30,
      p_title_en: "Today's current-affairs notes are ready 📰",
      p_body_en: `${noteRows.length} important notes for today. Available today only!`,
    });
    notified = Number(data ?? 0);
  }

  return json({
    mode,
    articles: articles.length,
    clusters: clusters.length,
    used: top.length,
    notes: noteRows.length,
    facts: { created, duplicates, superseded },
    notified,
  });
});
