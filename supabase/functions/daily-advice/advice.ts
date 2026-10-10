// Pure building blocks of the daily advice (unit tested in advice_test.ts):
//
//   signals (SQL daily_advice_signals) ─▶ normalizeSignals
//        ├─▶ signature()   bucketed, deterministic cache key
//        ├─▶ buildPrompt() the LLM sees ONLY the bucketed view (+ topic
//        │                 names), so a cached answer fits every learner with
//        │                 the same signature; exact numbers come back as
//        │                 {placeholders} filled per learner by fillPlaceholders
//        ├─▶ sanitizeTips() model output → 3–5 safe tips, routes from the
//        │                 allowlist only
//        └─▶ fallbackTips() rule-based tips when there is no AI / AI fails
import { bnDigits } from '../_shared/text.ts';

export type Locale = 'bn' | 'en';

export interface WeakTopic {
  topic_id: number;
  name_bn: string;
  name_en: string;
  subject_bn: string;
  subject_en: string;
  mastery: number; // 0..100
  attempts: number;
  is_prior: boolean; // estimated from the placement test, not practised yet
}

export interface TodayDay {
  day_id: number;
  kind: string;
  status: string;
  completed_items: number;
  total_items: number;
  notes_done: boolean | null;
}

export interface Signals {
  date: string;
  has_data: boolean;
  weak_topics: WeakTopic[];
  exams_7d: number;
  accuracy_7d: number | null;
  accuracy_prev_7d: number | null;
  practice_7d: number;
  wrong_7d: number;
  routine_days: number;
  routine_pct: number | null; // items done / items planned, last 7 days (no plan → null)
  streak: number;
  days_left: number | null;
  has_plan: boolean;
  today: TodayDay | null;
  notes_available: boolean;
  daily_exam_available: boolean;
  daily_exam_done: boolean;
  daily_exam_unlocked: boolean;
}

export interface Tip {
  title: string;
  body: string;
  action_route?: string;
}

export interface RawTip {
  title?: unknown;
  body?: unknown;
  action?: unknown;
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------
const num = (v: unknown, fallback = 0): number => {
  const n = typeof v === 'number' ? v : typeof v === 'string' ? Number(v) : NaN;
  return Number.isFinite(n) ? n : fallback;
};
const nullableNum = (v: unknown): number | null => {
  if (v === null || v === undefined) return null;
  const n = num(v, NaN);
  return Number.isNaN(n) ? null : n;
};
const str = (v: unknown) => (typeof v === 'string' ? v : '');
const obj = (v: unknown): Record<string, unknown> =>
  v && typeof v === 'object' && !Array.isArray(v) ? v as Record<string, unknown> : {};

/** Tolerant parse of the `daily_advice_signals` JSON (missing fields → safe defaults). */
export function normalizeSignals(raw: unknown): Signals {
  const r = obj(raw);
  const routine = obj(r.routine_7d);
  const total = num(routine.total_items);
  const today = r.today ? obj(r.today) : null;
  return {
    date: str(r.date),
    has_data: r.has_data === true,
    weak_topics: (Array.isArray(r.weak_topics) ? r.weak_topics : []).map(obj).map((w) => ({
      topic_id: num(w.topic_id),
      name_bn: str(w.name_bn) || str(w.name_en),
      name_en: str(w.name_en) || str(w.name_bn),
      subject_bn: str(w.subject_bn),
      subject_en: str(w.subject_en),
      mastery: Math.round(num(w.mastery)),
      attempts: num(w.attempts),
      is_prior: w.is_prior === true,
    })).filter((w) => w.topic_id > 0).slice(0, 3),
    exams_7d: num(r.exams_7d),
    accuracy_7d: nullableNum(r.accuracy_7d),
    accuracy_prev_7d: nullableNum(r.accuracy_prev_7d),
    practice_7d: num(r.practice_7d),
    wrong_7d: num(r.wrong_7d),
    routine_days: num(routine.days),
    routine_pct: total > 0 ? Math.round((100 * num(routine.completed_items)) / total) : null,
    streak: num(r.streak),
    days_left: nullableNum(r.days_left),
    has_plan: r.has_plan === true,
    today: today
      ? {
        day_id: num(today.day_id),
        kind: str(today.kind),
        status: str(today.status),
        completed_items: num(today.completed_items),
        total_items: num(today.total_items),
        notes_done: typeof today.notes_done === 'boolean' ? today.notes_done : null,
      }
      : null,
    notes_available: r.notes_available === true,
    daily_exam_available: r.daily_exam_available === true,
    daily_exam_done: r.daily_exam_done === true,
    daily_exam_unlocked: r.daily_exam_unlocked === true,
  };
}

// ---------------------------------------------------------------------------
// Buckets & signature
// ---------------------------------------------------------------------------
/** Index of the bucket `v` falls in: the number of `edges` it reaches. */
export const bucket = (v: number, edges: number[]): number => edges.filter((e) => v >= e).length;

export const EDGES = {
  mastery: [20, 40, 60, 80],
  exams: [1, 2, 4, 7],
  accuracy: [10, 20, 30, 40, 50, 60, 70, 80, 90],
  practice: [1, 20, 100],
  wrong: [1, 10, 50],
  routine: [25, 50, 75, 100],
  streak: [1, 3, 7, 14, 30],
  daysLeft: [8, 31, 61, 121],
} as const;

const b = (v: number | null, edges: readonly number[]) => (v === null ? 'x' : String(bucket(v, [...edges])));

/** Accuracy compared with the week before: up / down / flat / unknown. */
export function trend(s: Signals): 'u' | 'd' | 'f' | 'x' {
  if (s.accuracy_7d === null || s.accuracy_prev_7d === null) return 'x';
  const diff = s.accuracy_7d - s.accuracy_prev_7d;
  return diff >= 5 ? 'u' : diff <= -5 ? 'd' : 'f';
}

/** Today's routine state: none (no plan day) / rest / pending / partial / done. */
export function todayState(s: Signals): string {
  if (!s.today) return 'none';
  if (s.today.kind === 'rest') return 'rest';
  if (s.today.total_items > 0 && s.today.completed_items >= s.today.total_items) return 'done';
  return s.today.completed_items > 0 ? 'partial' : 'pending';
}

/** 1 read · 0 not yet · ? unknown (no routine to tell) · x no notes today. */
export function notesState(s: Signals): string {
  if (!s.notes_available) return 'x';
  return s.today?.notes_done === true ? '1' : s.today?.notes_done === false ? '0' : '?';
}

/** 1 taken · 0 not yet · x not available or locked for this learner. */
export function dailyExamState(s: Signals): string {
  if (!s.daily_exam_available || !s.daily_exam_unlocked) return 'x';
  return s.daily_exam_done ? '1' : '0';
}

/**
 * Compact, deterministic description of the learner's situation. Learners
 * with the same signature get the same advice (cache key), so it holds only
 * buckets and topic ids — never exact counts.
 */
export function signature(s: Signals, locale: Locale): string {
  const weak = s.weak_topics.map((w) => `${w.topic_id}${w.is_prior ? 'p' : ''}`).join(',');
  const mastery = s.weak_topics.map((w) => b(w.mastery, EDGES.mastery)).join(',');
  return [
    'v2', // bump when the prompt changes: cached advice is keyed by this
    locale,
    `w:${weak}`,
    `m:${mastery}`,
    `e:${b(s.exams_7d, EDGES.exams)}`,
    `a:${b(s.accuracy_7d, EDGES.accuracy)}`,
    `t:${trend(s)}`,
    `p:${b(s.practice_7d, EDGES.practice)}`,
    `x:${b(s.wrong_7d, EDGES.wrong)}`,
    `r:${b(s.routine_pct, EDGES.routine)}`,
    `s:${b(s.streak, EDGES.streak)}`,
    `d:${b(s.days_left === null ? null : Math.max(0, s.days_left), EDGES.daysLeft)}`,
    `pl:${s.has_plan ? 1 : 0}`,
    `td:${todayState(s)}`,
    `n:${notesState(s)}`,
    `de:${dailyExamState(s)}`,
  ].join('|');
}

/** Human range of a bucket, e.g. 2–3, 60–69, 30+. */
export function rangeText(v: number, edges: readonly number[]): string {
  const i = bucket(v, [...edges]);
  const lower = i === 0 ? 0 : edges[i - 1];
  if (i >= edges.length) return `${lower}+`;
  const upper = edges[i] - 1;
  return lower === upper ? String(lower) : `${lower}–${upper}`;
}

// ---------------------------------------------------------------------------
// Actions → routes (allowlist)
// ---------------------------------------------------------------------------
export const ACTIONS = [
  'none',
  'notes',
  'daily_exam',
  'wrong_answers',
  'exams',
  'model_tests',
  'question_bank',
  'plan',
  'progress',
  'practice_weak1',
  'practice_weak2',
  'practice_weak3',
] as const;
export type Action = (typeof ACTIONS)[number];

const STATIC_ROUTES: Record<string, string> = {
  notes: '/notes',
  daily_exam: '/daily-exam',
  wrong_answers: '/wrong-answers',
  exams: '/exams',
  model_tests: '/exams/model-tests',
  question_bank: '/question-bank',
  plan: '/plan',
  progress: '/progress',
};
const STATIC_ROUTE_SET = new Set(Object.values(STATIC_ROUTES));
const PRACTICE_TOPIC = /^\/practice\?topic=\d{1,9}$/;

/** True for app routes the advice may link to (the app re-checks this list). */
export const isAllowedRoute = (route: string): boolean =>
  STATIC_ROUTE_SET.has(route) || PRACTICE_TOPIC.test(route);

/**
 * Route for a model-chosen action, or null when it does not apply to this
 * learner (no plan, locked daily exam, missing weak topic, unknown action).
 */
export function actionRoute(action: unknown, s: Signals): string | null {
  if (typeof action !== 'string') return null;
  const practice = /^practice_weak([1-3])$/.exec(action);
  if (practice) {
    const topic = s.weak_topics[Number(practice[1]) - 1];
    return topic ? `/practice?topic=${topic.topic_id}` : null;
  }
  if (action === 'plan' && !s.has_plan) return null;
  if (action === 'daily_exam' && dailyExamState(s) === 'x') return null;
  const route = STATIC_ROUTES[action];
  return route && isAllowedRoute(route) ? route : null;
}

// ---------------------------------------------------------------------------
// Placeholders
// ---------------------------------------------------------------------------
/** Exact per-learner values the model may reference as {name}. */
export function placeholderValues(s: Signals): Record<string, number | null> {
  return {
    streak: s.streak,
    days_left: s.days_left === null ? null : Math.max(0, s.days_left),
    accuracy: s.accuracy_7d,
    accuracy_prev: s.accuracy_prev_7d,
    exams_week: s.exams_7d,
    practice_week: s.practice_7d,
    wrong_week: s.wrong_7d,
    routine_pct: s.routine_pct,
    today_left: s.today && s.today.kind !== 'rest'
      ? Math.max(0, s.today.total_items - s.today.completed_items)
      : null,
    weak1_pct: s.weak_topics[0]?.mastery ?? null,
    weak2_pct: s.weak_topics[1]?.mastery ?? null,
    weak3_pct: s.weak_topics[2]?.mastery ?? null,
  };
}

const localNum = (n: number, locale: Locale) => (locale === 'bn' ? bnDigits(n) : String(n));

/** Fills {placeholders}; returns null if one is unknown or has no value (tip is dropped). */
export function fillPlaceholders(
  text: string,
  values: Record<string, number | null>,
  locale: Locale,
): string | null {
  let ok = true;
  const out = text.replace(/\{([a-z0-9_]+)\}/gi, (_, name: string) => {
    const v = values[name.toLowerCase()];
    if (v === null || v === undefined) {
      ok = false;
      return '';
    }
    return localNum(v, locale);
  });
  return ok ? out : null;
}

// ---------------------------------------------------------------------------
// Prompt
// ---------------------------------------------------------------------------
export const ADVICE_SYSTEM =
  `You are "Prostuti AI", a warm but practical mentor for Bangladeshi government job exams (BCS preliminary, bank, primary teacher).
You get one learner's study signals. Write 3 to 5 short, concrete tips for TODAY in the requested language (LANGUAGE).
Rules:
- Ground every tip in the signals: name their real weak topics and refer to their real situation. Never invent topics, facts or numbers.
- Signal numbers are ranges. To mention an exact number, write the matching placeholder from the list (e.g. {streak}, {accuracy}); never write the ranges.
- Make each tip doable today with a concrete amount, e.g. "আজ পাটিগণিতের ২০টি প্রশ্ন অনুশীলন করুন" / "Practise 20 Arithmetic questions today".
- title: at most 6 words. body: one or two sentences, at most 30 words. No emojis, no greetings, no generic platitudes.
- Order by importance: unfinished tasks of today, the weakest topics, exam practice and accuracy, consistency and streak, the exam countdown.
- action: the app screen that helps with the tip, from the allowed list only; "none" when no screen fits. Use practice_weakN only for a tip about weak topic N.
- Mastery is how well the learner knows a topic (higher is better); a weak topic has LOW mastery. Never call a weakness "low" or "high".
- In Bangla use standard, natural চলিত ভাষা and Bangla digits. Write everything in Bangla: "পরীক্ষা", "মডেল টেস্ট", "অনুশীলন", "উত্তর"; keep English only for terms learners study in English, such as Vocabulary or Synonym.`;

export const ADVICE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['tips'],
  properties: {
    tips: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['title', 'body', 'action'],
        properties: {
          title: { type: 'string' },
          body: { type: 'string' },
          action: { type: 'string', enum: [...ACTIONS] },
        },
      },
    },
  },
};

/**
 * The model's view of the learner: only what the signature encodes (buckets,
 * topic names, locale), so a cached answer is valid for everyone sharing it.
 */
export function buildPrompt(s: Signals, locale: Locale): string {
  const name = (
    w: WeakTopic,
  ) => (locale === 'en' ? `${w.name_en} (${w.subject_en})` : `${w.name_bn} (${w.subject_bn})`);
  const lines: string[] = ['Learner snapshot (numbers are ranges):'];
  if (s.weak_topics.length) {
    lines.push('Weakest topics:');
    s.weak_topics.forEach((w, i) =>
      lines.push(
        `  ${i + 1}. ${name(w)} — mastery ${rangeText(w.mastery, EDGES.mastery)}%` +
          `${w.is_prior ? ' (estimated from the placement test, not practised yet)' : ''}` +
          ` [placeholder {weak${i + 1}_pct}, action practice_weak${i + 1}]`,
      )
    );
  } else {
    lines.push('Weakest topics: unknown (no practice yet)');
  }
  const acc = s.accuracy_7d === null
    ? 'answered no exam or practice questions'
    : `accuracy ${rangeText(s.accuracy_7d, EDGES.accuracy)}%`;
  const t = trend(s);
  const trendText = t === 'u'
    ? ', improving vs the week before'
    : t === 'd'
    ? ', worse than the week before'
    : t === 'f'
    ? ', about the same as the week before'
    : '';
  lines.push(`Exams in the last 7 days: ${rangeText(s.exams_7d, EDGES.exams)} (${acc}${trendText})`);
  lines.push(`Practice questions in the last 7 days: ${rangeText(s.practice_7d, EDGES.practice)}`);
  lines.push(`Wrong answers in the last 7 days: ${rangeText(s.wrong_7d, EDGES.wrong)}`);
  if (!s.has_plan) lines.push('Study plan: none yet');
  else {
    lines.push(
      `Routine completed in the last 7 days: ${
        s.routine_pct === null ? 'no routine days yet' : `${rangeText(s.routine_pct, EDGES.routine)}%`
      }`,
    );
  }
  lines.push(`Study streak: ${rangeText(s.streak, EDGES.streak)} days`);
  if (s.days_left !== null) {
    lines.push(`Days until the target exam: ${rangeText(Math.max(0, s.days_left), EDGES.daysLeft)}`);
  }
  const td = todayState(s);
  lines.push(
    `Today's routine: ${
      {
        none: 'none',
        rest: 'rest day',
        pending: 'not started',
        partial: 'partly done',
        done: 'all done',
      }[td] ?? td
    }`,
  );
  const n = notesState(s);
  lines.push(
    `Today's current-affairs notes: ${
      { x: 'not published yet', '1': 'read', '0': 'not read yet', '?': 'unknown whether read' }[n]
    }`,
  );
  const de = dailyExamState(s);
  if (de !== 'x') lines.push(`Today's daily current-affairs exam: ${de === '1' ? 'taken' : 'not taken yet'}`);

  const values = placeholderValues(s);
  const usable = Object.keys(values).filter((k) => values[k] !== null).map((k) => `{${k}}`);
  lines.push(`Placeholders you may use: ${usable.join(' ')}`);
  const actions = ACTIONS.filter((a) => a === 'none' || actionRoute(a, s) !== null);
  lines.push(`Allowed actions: ${actions.join(', ')}`);
  return lines.join('\n');
}

// ---------------------------------------------------------------------------
// Output sanitising
// ---------------------------------------------------------------------------
const clip = (text: string, max: number) => {
  const t = text.replace(/\s+/g, ' ').trim();
  return t.length <= max ? t : `${t.slice(0, max - 1).trimEnd()}…`;
};

export const MIN_TIPS = 3;
export const MAX_TIPS = 5;

/** Model output → 3–5 clean tips; tops up from the rule-based tips if needed. */
export function sanitizeTips(raw: unknown, s: Signals, locale: Locale): Tip[] {
  const values = placeholderValues(s);
  const out: Tip[] = [];
  const seen = new Set<string>();
  for (const item of Array.isArray(raw) ? raw as RawTip[] : []) {
    if (out.length >= MAX_TIPS) break;
    const title = fillPlaceholders(str(item?.title), values, locale);
    const body = fillPlaceholders(str(item?.body), values, locale);
    if (!title?.trim() || !body?.trim()) continue;
    const tip: Tip = { title: clip(title, 60), body: clip(body, 220) };
    const route = actionRoute(item?.action, s);
    if (route) tip.action_route = route;
    const key = tip.title.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(tip);
  }
  if (out.length < MIN_TIPS) {
    for (const tip of fallbackTips(s, locale)) {
      if (out.length >= MIN_TIPS) break;
      // Avoid two tips sending the learner to the same screen.
      if (tip.action_route && out.some((t) => t.action_route === tip.action_route)) continue;
      out.push(tip);
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Rule-based fallback (no AI key, AI error, or topping up a short answer)
// ---------------------------------------------------------------------------
type Rule = { bn: [string, string]; en: [string, string]; route?: string | null };

/** Deterministic tips from the same signals, most important first. */
export function fallbackTips(s: Signals, locale: Locale): Tip[] {
  const n = (v: number) => localNum(v, locale);
  const rules: Rule[] = [];
  const [w1, w2] = s.weak_topics;
  const wname = (w: WeakTopic) => (locale === 'en' ? w.name_en : w.name_bn);

  const td = todayState(s);
  if (td === 'pending' || td === 'partial') {
    const left = Math.max(0, s.today!.total_items - s.today!.completed_items);
    rules.push({
      bn: ['আজকের রুটিন শেষ করুন', `আজকের রুটিনের আরও ${n(left)}টি কাজ বাকি — শেষ করে ধারাবাহিকতা ধরে রাখুন।`],
      en: [
        "Finish today's routine",
        `${n(left)} task${left === 1 ? '' : 's'} left in today's routine — finish them to stay on track.`,
      ],
      route: '/plan',
    });
  }
  if (w1) {
    rules.push({
      bn: [
        `দুর্বল টপিক: ${wname(w1)}`,
        `আজ ${wname(w1)}-এর ২০টি প্রশ্ন অনুশীলন করুন — এখন আপনার দক্ষতা ${n(w1.mastery)}%।`,
      ],
      en: [
        `Weak spot: ${wname(w1)}`,
        `Practise 20 questions on ${wname(w1)} today — your mastery is ${n(w1.mastery)}% right now.`,
      ],
      route: `/practice?topic=${w1.topic_id}`,
    });
  }
  if (notesState(s) === '0' || notesState(s) === '?') {
    rules.push({
      bn: ['আজকের সাম্প্রতিক নোট', 'আজকের সাম্প্রতিক নোট পড়ে নিন — প্রতিদিন ১৫ মিনিটই যথেষ্ট।'],
      en: ["Today's current affairs", "Read today's current-affairs notes — 15 minutes a day is enough."],
      route: '/notes',
    });
  }
  if (dailyExamState(s) === '0') {
    rules.push({
      bn: ['দৈনিক পরীক্ষা দিন', 'আজকের সাম্প্রতিক নোট থেকে দৈনিক পরীক্ষাটি দিয়ে নিজেকে যাচাই করুন।'],
      en: ['Take the daily exam', "Test yourself with today's current-affairs exam."],
      route: '/daily-exam',
    });
  }
  if (s.accuracy_7d !== null && s.accuracy_7d < 60 && s.wrong_7d > 0) {
    rules.push({
      bn: [
        'ভুলগুলো রিভিশন দিন',
        `গত ৭ দিনে সঠিকতার হার ${n(s.accuracy_7d)}% — ভুল করা ${n(s.wrong_7d)}টি প্রশ্ন আবার দেখুন।`,
      ],
      en: [
        'Review your mistakes',
        `Your accuracy over the last 7 days is ${n(s.accuracy_7d)}% — go through your ${
          n(s.wrong_7d)
        } wrong answers.`,
      ],
      route: '/wrong-answers',
    });
  }
  if (s.exams_7d < 2) {
    rules.push({
      bn: [
        'আজ একটি পরীক্ষা দিন',
        s.exams_7d === 0
          ? 'এই সপ্তাহে এখনো কোনো পরীক্ষা দেননি — আজ অন্তত একটি ছোট মডেল টেস্ট দিন।'
          : `এই সপ্তাহে মাত্র ${n(s.exams_7d)}টি পরীক্ষা দিয়েছেন — আজ আরেকটি ছোট মডেল টেস্ট দিন।`,
      ],
      en: [
        'Take a test today',
        s.exams_7d === 0
          ? 'No exams yet this week — take at least one short model test today.'
          : `Only ${n(s.exams_7d)} exam this week so far — take another short model test today.`,
      ],
      route: '/exams',
    });
  }
  if (trend(s) === 'u') {
    rules.push({
      bn: [
        'আপনি এগোচ্ছেন',
        `সঠিকতার হার ${n(s.accuracy_prev_7d!)}% থেকে বেড়ে ${n(s.accuracy_7d!)}% হয়েছে — এই গতি ধরে রাখুন।`,
      ],
      en: [
        "You're improving",
        `Accuracy went up from ${n(s.accuracy_prev_7d!)}% to ${n(s.accuracy_7d!)}% — keep it going.`,
      ],
      route: '/progress',
    });
  }
  if (s.has_plan && s.routine_pct !== null && s.routine_pct < 50) {
    rules.push({
      bn: [
        'ধারাবাহিকতা বাড়ান',
        `গত সপ্তাহের রুটিনের ${n(s.routine_pct)}% শেষ হয়েছে — প্রতিদিন অন্তত প্রথম দুটি কাজ শেষ করার লক্ষ্য নিন।`,
      ],
      en: [
        'Build consistency',
        `You finished ${
          n(s.routine_pct)
        }% of last week's routine — aim to complete at least the first two tasks every day.`,
      ],
      route: '/plan',
    });
  }
  if (s.days_left !== null && s.days_left >= 0 && s.days_left <= 30) {
    rules.push({
      bn: ['শেষ মুহূর্তের প্রস্তুতি', `পরীক্ষার আর ${n(s.days_left)} দিন বাকি — একদিন পরপর পূর্ণাঙ্গ মডেল টেস্ট দিন।`],
      en: ['Final stretch', `${n(s.days_left)} days to the exam — take a full model test every other day.`],
      route: '/exams/model-tests',
    });
  }
  if (s.streak >= 3) {
    rules.push({
      bn: [`${n(s.streak)} দিনের ধারা`, 'টানা পড়ার ধারা চলছে — আজও অন্তত একটি কাজ শেষ করে ধারাটি ধরে রাখুন।'],
      en: [
        `${n(s.streak)}-day streak`,
        'Your streak is alive — finish at least one task today to keep it going.',
      ],
    });
  } else if (s.streak === 0) {
    rules.push({
      bn: ['আজ থেকে শুরু করুন', 'আজ একটি কাজ শেষ করে নতুন পড়ার ধারা শুরু করুন — ছোট ছোট পদক্ষেপই বড় ফল আনে।'],
      en: ['Start a streak today', 'Finish one task today to start a new streak — small steps add up.'],
    });
  }
  if (w2) {
    rules.push({
      bn: [`এরপর: ${wname(w2)}`, `${wname(w2)}-এ দক্ষতা ${n(w2.mastery)}% — আজ ১০টি প্রশ্ন দিয়ে শুরু করুন।`],
      en: [
        `Next up: ${wname(w2)}`,
        `Mastery in ${wname(w2)} is ${n(w2.mastery)}% — start with 10 questions today.`,
      ],
      route: `/practice?topic=${w2.topic_id}`,
    });
  }
  if (!s.has_plan) {
    rules.push({
      bn: ['স্টাডি প্ল্যান তৈরি করুন', 'আপনার লেভেল ও সময় অনুযায়ী দিনভিত্তিক রুটিন বানিয়ে নিন।'],
      en: ['Create a study plan', 'Get a day-by-day routine built around your level and the time left.'],
      route: '/plan',
    });
  }
  // Always-useful fillers so there are at least three tips.
  rules.push(
    {
      bn: ['ভুলের খাতা দেখুন', 'সপ্তাহে অন্তত একবার ভুল করা প্রশ্নগুলো রিভিশন দিন।'],
      en: ['Revisit wrong answers', 'Revise the questions you got wrong at least once a week.'],
      route: '/wrong-answers',
    },
    {
      bn: ['প্রশ্নব্যাংক অনুশীলন', 'প্রতিদিন গণিত ও ইংরেজিতে অল্প হলেও অনুশীলন করুন।'],
      en: ['Daily practice', 'Practise a little Math and English every single day.'],
      route: '/question-bank',
    },
  );

  const out: Tip[] = [];
  const routes = new Set<string>();
  for (const r of rules) {
    if (out.length >= 4) break;
    const route = r.route && isAllowedRoute(r.route) ? r.route : null;
    if (route && routes.has(route)) continue;
    if (route) routes.add(route);
    const [title, body] = locale === 'en' ? r.en : r.bn;
    out.push(route ? { title, body, action_route: route } : { title, body });
  }
  return out;
}

/** The subset of signals stored with the advice (shown/debugged later). */
export function compactStats(s: Signals) {
  return {
    has_data: s.has_data,
    weak_topics: s.weak_topics.map((w) => ({
      topic_id: w.topic_id,
      name_bn: w.name_bn,
      name_en: w.name_en,
      mastery: w.mastery,
    })),
    exams_7d: s.exams_7d,
    accuracy_7d: s.accuracy_7d,
    practice_7d: s.practice_7d,
    wrong_7d: s.wrong_7d,
    routine_pct: s.routine_pct,
    streak: s.streak,
    days_left: s.days_left,
    today: todayState(s),
  };
}
