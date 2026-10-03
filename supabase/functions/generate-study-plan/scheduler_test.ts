import { assert, assertEquals } from 'jsr:@std/assert@1';
import { buildPlan, daysBetween } from './scheduler.ts';

const subjects = [
  { id: 1, code: 'bangla', name_bn: 'বাংলা', name_en: 'Bangla', bcs_marks: 30 },
  { id: 8, code: 'math', name_bn: 'গণিত', name_en: 'Math', bcs_marks: 20 },
];
const topics = [
  { id: 101, subject_id: 1, name_bn: 'সমাস', name_en: 'Samas', weight: 1, is_general: false },
  { id: 102, subject_id: 1, name_bn: 'সাহিত্য', name_en: 'Literature', weight: 2.5, is_general: false },
  { id: 801, subject_id: 8, name_bn: 'পাটিগণিত', name_en: 'Arithmetic', weight: 2.5, is_general: false },
  { id: 899, subject_id: 8, name_bn: 'বিবিধ', name_en: 'Misc', weight: 0.5, is_general: true },
];

Deno.test('plan spans every day until the exam', () => {
  const out = buildPlan({
    startDate: '2026-10-04',
    examDate: '2027-01-02',
    dailyMinutes: 120,
    subjects,
    topics,
    mastery: new Map(),
  });
  assertEquals(out.days.length, daysBetween('2026-10-04', '2027-01-02'));
  assertEquals(out.days[0].day_date, '2026-10-04');
  assertEquals(out.days.at(-1)!.day_date, '2027-01-01');
});

Deno.test('every 7th day (before the final phase) is a weak-topic exam day', () => {
  const out = buildPlan({
    startDate: '2026-10-04',
    examDate: '2027-03-04',
    dailyMinutes: 120,
    subjects,
    topics,
    mastery: new Map(),
  });
  assertEquals(out.days[6].kind, 'weak_topic_exam');
  assertEquals(out.days[13].kind, 'weak_topic_exam');
});

Deno.test('weaker topics get more study blocks', () => {
  const mastery = new Map([[101, 0.95], [102, 0.1], [801, 0.1], [899, 0.5]]);
  const out = buildPlan({
    startDate: '2026-10-04',
    examDate: '2027-01-02',
    dailyMinutes: 120,
    subjects,
    topics,
    mastery,
  });
  const count = (id: number) =>
    out.days.flatMap((d) => d.items).filter((i) => i.type === 'read' && i.topic_id === id).length;
  assert(count(102) > count(101), 'literature (weak) should beat samas (strong)');
});

Deno.test('daily minutes are respected', () => {
  const out = buildPlan({
    startDate: '2026-10-04',
    examDate: '2026-12-04',
    dailyMinutes: 90,
    subjects,
    topics,
    mastery: new Map(),
  });
  for (const d of out.days.filter((d) => d.kind === 'study')) {
    assert(d.target_minutes <= 90, `day ${d.day_index}: ${d.target_minutes}`);
  }
});

Deno.test('item keys are unique within a day', () => {
  const out = buildPlan({
    startDate: '2026-10-04',
    examDate: '2027-05-14',
    dailyMinutes: 240,
    subjects,
    topics,
    mastery: new Map(),
  });
  for (const d of out.days) assertEquals(new Set(d.items.map((i) => i.key)).size, d.items.length);
});
