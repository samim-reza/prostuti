import { assert, assertEquals, assertNotEquals } from 'jsr:@std/assert@1';
import {
  actionRoute,
  ACTIONS,
  ADVICE_SCHEMA,
  bucket,
  buildPrompt,
  EDGES,
  fallbackTips,
  fillPlaceholders,
  isAllowedRoute,
  MAX_TIPS,
  MIN_TIPS,
  normalizeSignals,
  placeholderValues,
  rangeText,
  sanitizeTips,
  type Signals,
  signature,
} from './advice.ts';

const raw = {
  date: '2026-10-11',
  locale: 'bn',
  has_data: true,
  weak_topics: [
    {
      topic_id: 801,
      name_bn: 'পাটিগণিত',
      name_en: 'Arithmetic',
      subject_bn: 'গণিত',
      subject_en: 'Math',
      mastery: 23,
      attempts: 12,
      is_prior: false,
    },
    {
      topic_id: 303,
      name_bn: 'মহান মুক্তিযুদ্ধ',
      name_en: 'Liberation War 1971',
      subject_bn: 'বাংলাদেশ বিষয়াবলি',
      subject_en: 'Bangladesh Affairs',
      mastery: 41,
      attempts: 4,
      is_prior: true,
    },
  ],
  exams_7d: 3,
  accuracy_7d: 64,
  accuracy_prev_7d: 52,
  practice_7d: 45,
  wrong_7d: 18,
  routine_7d: { days: 7, done_days: 2, completed_items: 12, total_items: 40 },
  streak: 4,
  longest_streak: 9,
  days_left: 45,
  has_plan: true,
  today: {
    day_id: 8,
    kind: 'study',
    status: 'partial',
    completed_items: 2,
    total_items: 6,
    notes_done: false,
  },
  notes_available: true,
  daily_exam_available: true,
  daily_exam_done: false,
  daily_exam_unlocked: true,
};

const signals = (patch: Partial<Signals> = {}): Signals => ({ ...normalizeSignals(raw), ...patch });

Deno.test('normalizeSignals parses SQL output and derives the routine percentage', () => {
  const s = normalizeSignals(raw);
  assertEquals(s.weak_topics.length, 2);
  assertEquals(s.routine_pct, 30);
  assertEquals(s.today?.notes_done, false);
  assertEquals(s.accuracy_7d, 64);
});

Deno.test('normalizeSignals tolerates null / missing fields', () => {
  const s = normalizeSignals(null);
  assertEquals(s.has_data, false);
  assertEquals(s.weak_topics, []);
  assertEquals(s.routine_pct, null);
  assertEquals(s.accuracy_7d, null);
  assertEquals(s.days_left, null);
  assertEquals(s.today, null);
  const t = normalizeSignals({
    has_data: true,
    routine_7d: { total_items: 0 },
    accuracy_7d: null,
    days_left: '12',
  });
  assertEquals(t.routine_pct, null);
  assertEquals(t.days_left, 12);
});

Deno.test('bucket and rangeText agree on the edges', () => {
  assertEquals(bucket(0, [...EDGES.exams]), 0);
  assertEquals(bucket(1, [...EDGES.exams]), 1);
  assertEquals(bucket(3, [...EDGES.exams]), 2);
  assertEquals(bucket(50, [...EDGES.exams]), 4);
  assertEquals(rangeText(0, EDGES.exams), '0');
  assertEquals(rangeText(1, EDGES.exams), '1');
  assertEquals(rangeText(3, EDGES.exams), '2–3');
  assertEquals(rangeText(9, EDGES.exams), '7+');
  assertEquals(rangeText(64, EDGES.accuracy), '60–69');
  assertEquals(rangeText(100, EDGES.routine), '100+');
});

Deno.test('signature is deterministic and ignores small changes inside a bucket', () => {
  const a = signature(signals(), 'bn');
  assertEquals(a, signature(signals(), 'bn'));
  assertEquals(
    a,
    'v2|bn|w:801,303p|m:1,2|e:2|a:6|t:u|p:2|x:2|r:1|s:2|d:2|pl:1|td:partial|n:0|de:0',
  );
  // 64% → 67% accuracy, 45 → 60 practice questions: same buckets.
  assertEquals(a, signature(signals({ accuracy_7d: 67, practice_7d: 60 }), 'bn'));
});

Deno.test('signature changes with locale, weak topics, buckets and today state', () => {
  const base = signature(signals(), 'bn');
  assertNotEquals(base, signature(signals(), 'en'));
  assertNotEquals(base, signature(signals({ accuracy_7d: 71 }), 'bn'));
  assertNotEquals(base, signature(signals({ weak_topics: signals().weak_topics.slice(1) }), 'bn'));
  const done = signals();
  done.today = { ...done.today!, completed_items: 6 };
  assert(signature(done, 'bn').includes('td:done'));
  // Exact numbers never leak into the key.
  assert(!base.includes('64') && !base.includes('45'));
});

Deno.test('route allowlist accepts app routes only', () => {
  for (
    const r of [
      '/notes',
      '/daily-exam',
      '/wrong-answers',
      '/exams',
      '/question-bank',
      '/plan',
      '/practice?topic=801',
    ]
  ) {
    assert(isAllowedRoute(r), r);
  }
  for (
    const r of [
      'https://evil.example',
      '/admin',
      '/settings',
      '/practice?topic=1&x=2',
      '/practice?topic=abc',
      '//notes',
      '/notes ',
      '',
    ]
  ) {
    assert(!isAllowedRoute(r), r);
  }
});

Deno.test('actionRoute maps actions and drops ones that do not apply', () => {
  const s = signals();
  assertEquals(actionRoute('notes', s), '/notes');
  assertEquals(actionRoute('practice_weak1', s), '/practice?topic=801');
  assertEquals(actionRoute('practice_weak3', s), null); // only two weak topics
  assertEquals(actionRoute('none', s), null);
  assertEquals(actionRoute('admin', s), null);
  assertEquals(actionRoute(42, s), null);
  assertEquals(actionRoute('plan', signals({ has_plan: false })), null);
  assertEquals(actionRoute('daily_exam', signals({ daily_exam_unlocked: false })), null);
  // Every action the schema allows resolves to an allowlisted route or null.
  for (const a of ACTIONS) {
    const r = actionRoute(a, s);
    assert(r === null || isAllowedRoute(r), a);
  }
  assertEquals(ADVICE_SCHEMA.properties.tips.items.properties.action.enum.length, ACTIONS.length);
});

Deno.test('fillPlaceholders uses exact values, Bangla digits, and rejects unknown ones', () => {
  const v = placeholderValues(signals());
  assertEquals(fillPlaceholders('{streak} দিনের ধারা', v, 'bn'), '৪ দিনের ধারা');
  assertEquals(fillPlaceholders('Accuracy {accuracy}%', v, 'en'), 'Accuracy 64%');
  assertEquals(fillPlaceholders('{today_left} left', v, 'en'), '4 left');
  assertEquals(fillPlaceholders('{weak3_pct}%', v, 'en'), null); // no third weak topic
  assertEquals(fillPlaceholders('{password}', v, 'en'), null);
  assertEquals(fillPlaceholders('no placeholders', v, 'en'), 'no placeholders');
});

Deno.test('sanitizeTips cleans model output, maps routes and tops up to the minimum', () => {
  const s = signals();
  const tips = sanitizeTips(
    [
      {
        title: 'পাটিগণিত',
        body: 'আজ পাটিগণিতের ২০টি প্রশ্ন অনুশীলন করুন — দক্ষতা {weak1_pct}%।',
        action: 'practice_weak1',
      },
      { title: 'পাটিগণিত', body: 'duplicate title', action: 'notes' },
      { title: 'Bad', body: 'uses {unknown}', action: 'notes' },
      { title: '', body: 'no title', action: 'notes' },
    ],
    s,
    'bn',
  );
  assertEquals(tips.length, MIN_TIPS);
  assertEquals(tips[0].body, 'আজ পাটিগণিতের ২০টি প্রশ্ন অনুশীলন করুন — দক্ষতা ২৩%।');
  assertEquals(tips[0].action_route, '/practice?topic=801');
  for (const t of tips) {
    assert(t.title && t.body);
    assert(!t.action_route || isAllowedRoute(t.action_route));
  }
  // No two tips point at the same screen after topping up.
  const routes = tips.map((t) => t.action_route).filter(Boolean);
  assertEquals(new Set(routes).size, routes.length);
});

Deno.test('sanitizeTips caps the count and the length', () => {
  const many = Array.from(
    { length: 8 },
    (_, i) => ({ title: `Tip ${i}`, body: 'x'.repeat(400), action: 'none' }),
  );
  const tips = sanitizeTips(many, signals(), 'en');
  assertEquals(tips.length, MAX_TIPS);
  assert(tips.every((t) => t.body.length <= 220 && !t.action_route));
  assertEquals(sanitizeTips('not an array', signals(), 'en').length, MIN_TIPS);
});

Deno.test('fallback rules: unfinished routine and weakest topic come first', () => {
  const tips = fallbackTips(signals(), 'bn');
  assert(tips.length >= MIN_TIPS && tips.length <= MAX_TIPS);
  assertEquals(tips[0].action_route, '/plan');
  assert(tips[0].body.includes('৪টি')); // 6 − 2 tasks left, Bangla digits
  assertEquals(tips[1].action_route, '/practice?topic=801');
  assert(tips[1].body.includes('পাটিগণিত') && tips[1].body.includes('২৩%'));
  assertEquals(tips[2].action_route, '/notes');
});

Deno.test('fallback rules react to the signals', () => {
  const struggling = signals({
    accuracy_7d: 40,
    accuracy_prev_7d: 45,
    exams_7d: 0,
    notes_available: false,
    daily_exam_available: false,
    today: null,
  });
  const routes = fallbackTips(struggling, 'en').map((t) => t.action_route);
  assert(routes.includes('/wrong-answers'));
  assert(routes.includes('/exams'));
  assert(!routes.includes('/notes'));
  assert(!routes.includes('/daily-exam'));

  const fresh = normalizeSignals({ has_data: true, streak: 0 });
  const tips = fallbackTips(fresh, 'en');
  assert(tips.length >= MIN_TIPS);
  assert(tips.some((t) => t.action_route === '/plan')); // no plan yet → create one
  assert(tips.every((t) => !t.action_route || isAllowedRoute(t.action_route)));
});

Deno.test('prompt contains only bucketed numbers, the topic names and usable placeholders', () => {
  const p = buildPrompt(signals(), 'bn');
  assert(p.includes('পাটিগণিত (গণিত)'));
  assert(p.includes('accuracy 60–69%'));
  assert(p.includes('{weak1_pct}'));
  assert(!p.includes('{weak3_pct}'));
  assert(!p.includes('64'));
  assert(p.includes('practice_weak1') && !p.includes('practice_weak3'));
  const en = buildPrompt(signals({ daily_exam_unlocked: false }), 'en');
  assert(en.includes('Arithmetic (Math)'));
  assert(!en.includes('daily current-affairs exam'));
  assert(!en.split('Allowed actions:')[1].includes('daily_exam'));
});
