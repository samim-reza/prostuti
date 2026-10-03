// Deterministic study-plan scheduler (pure function — unit tested).
//
// 1. Phases: foundation (≈50%) → practice (≈35%) → final revision (≈15%).
// 2. Day kinds: every 7th day is a free "weak-topic exam" day; one model test
//    per week in the practice phase; the final phase alternates model tests
//    and revision days.
// 3. Topic allocation with a max-heap priority queue:
//      priority = (subject marks / 200) × (topic weight / Σ weights in subject)
//                 × (1 − mastery)^1.5
//    The top topic gets a study block (read + practice); its priority then
//    decays ×0.55 so other topics get their turn, i.e. weaker and heavier
//    topics come back more often.
// 4. Spaced repetition: each studied topic is scheduled for 15-minute
//    revisions 3, 7 and 16 days later (moved to the next study day if needed).

export interface Subject {
  id: number;
  code: string;
  name_bn: string;
  name_en: string;
  bcs_marks: number;
}
export interface Topic {
  id: number;
  subject_id: number;
  name_bn: string;
  name_en: string;
  weight: number;
  is_general: boolean;
}
export interface PlanItem {
  key: string;
  type: 'read' | 'practice' | 'exam' | 'revise';
  title_bn: string;
  title_en: string;
  minutes: number;
  subject_id?: number;
  topic_id?: number;
  count?: number;
  exam_kind?: 'weak_topic' | 'model_test' | 'topic';
  size?: number;
  route?: string;
}
export interface PlanDay {
  day_date: string;
  day_index: number;
  kind: 'study' | 'revision' | 'weak_topic_exam' | 'model_test';
  title_bn: string;
  title_en: string;
  items: PlanItem[];
  target_minutes: number;
  total_items: number;
}
export interface PlanInput {
  startDate: string; // YYYY-MM-DD (Bangladesh)
  examDate: string;
  dailyMinutes: number;
  subjects: Subject[];
  topics: Topic[];
  mastery: Map<number, number>; // topic_id → 0..1
}
export interface PlanOutput {
  days: PlanDay[];
  summary: Record<string, unknown>;
}

class MaxHeap<T> {
  private a: { p: number; v: T }[] = [];
  get size() {
    return this.a.length;
  }
  push(v: T, p: number) {
    const a = this.a;
    a.push({ p, v });
    let i = a.length - 1;
    while (i > 0) {
      const parent = (i - 1) >> 1;
      if (a[parent].p >= a[i].p) break;
      [a[parent], a[i]] = [a[i], a[parent]];
      i = parent;
    }
  }
  pop(): { p: number; v: T } | undefined {
    const a = this.a;
    if (!a.length) return undefined;
    const top = a[0];
    const last = a.pop()!;
    if (a.length) {
      a[0] = last;
      let i = 0;
      for (;;) {
        const l = 2 * i + 1, r = l + 1;
        let m = i;
        if (l < a.length && a[l].p > a[m].p) m = l;
        if (r < a.length && a[r].p > a[m].p) m = r;
        if (m === i) break;
        [a[m], a[i]] = [a[i], a[m]];
        i = m;
      }
    }
    return top;
  }
}

const DAY = 86400_000;
export const addDays = (iso: string, n: number) =>
  new Date(Date.parse(`${iso}T00:00:00Z`) + n * DAY).toISOString().slice(0, 10);
export const daysBetween = (a: string, b: string) =>
  Math.round((Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / DAY);
const bn = (n: number) => String(n).replace(/[0-9]/g, (d) => '০১২৩৪৫৬৭৮৯'[Number(d)]);

export function buildPlan(input: PlanInput): PlanOutput {
  const total = Math.min(365, Math.max(3, daysBetween(input.startDate, input.examDate)));
  const minutes = Math.min(480, Math.max(30, Math.round(input.dailyMinutes)));
  const foundationEnd = Math.floor(total * (total < 21 ? 0.4 : 0.5));
  const practiceEnd = foundationEnd + Math.floor(total * (total < 21 ? 0.4 : 0.35));

  const subjectById = new Map(input.subjects.map((s) => [s.id, s]));
  const weightSum = new Map<number, number>();
  for (const t of input.topics) {
    weightSum.set(t.subject_id, (weightSum.get(t.subject_id) ?? 0) + Number(t.weight));
  }

  const heap = new MaxHeap<Topic>();
  for (const t of input.topics) {
    const s = subjectById.get(t.subject_id);
    if (!s || s.bcs_marks <= 0) continue;
    const mastery = input.mastery.get(t.id) ?? 0.15;
    const p = (s.bcs_marks / 200) * (Number(t.weight) / (weightSum.get(t.subject_id) || 1)) *
        Math.pow(1 - mastery, 1.5) +
      (t.is_general ? 0 : 0.0005);
    heap.push(t, p);
  }

  const kinds: PlanDay['kind'][] = [];
  for (let d = 0; d < total; d++) {
    const dayNo = d + 1;
    if (d >= practiceEnd) kinds.push((d - practiceEnd) % 2 === 0 ? 'model_test' : 'revision');
    else if (dayNo % 7 === 0) kinds.push('weak_topic_exam');
    else if (d >= foundationEnd && dayNo % 7 === 4) kinds.push('model_test');
    else kinds.push('study');
  }

  const revisions: Topic[][] = Array.from({ length: total }, () => []);
  const scheduleRevision = (t: Topic, day: number) => {
    let d = day;
    while (d < total && kinds[d] !== 'study' && kinds[d] !== 'revision') d++;
    if (d < total && revisions[d].length < 2 && !revisions[d].includes(t)) revisions[d].push(t);
  };

  const days: PlanDay[] = [];
  let modelTests = 0, weakDays = 0;
  for (let d = 0; d < total; d++) {
    const date = addDays(input.startDate, d);
    const kind = kinds[d];
    const items: PlanItem[] = [];
    const key = (n: number) => `d${d + 1}-${n}`;
    const caMinutes = minutes >= 60 ? 15 : 10;
    items.push({
      key: key(items.length + 1),
      type: 'read',
      minutes: caMinutes,
      route: '/notes',
      title_bn: 'আজকের সাম্প্রতিক নোট পড়ুন',
      title_en: "Read today's current-affairs notes",
    });

    let title_bn = '', title_en = '';
    if (kind === 'study') {
      let budget = minutes - caMinutes;
      for (const t of revisions[d]) {
        const s = subjectById.get(t.subject_id)!;
        items.push({
          key: key(items.length + 1),
          type: 'revise',
          minutes: 15,
          subject_id: s.id,
          topic_id: t.id,
          title_bn: `রিভিশন: ${t.name_bn}`,
          title_en: `Revise: ${t.name_en}`,
        });
        budget -= 15;
      }
      const studied: Topic[] = [];
      while (budget >= 25 && heap.size) {
        const top = heap.pop()!;
        const t = top.v;
        const s = subjectById.get(t.subject_id)!;
        const block = Math.min(45, budget);
        const read = Math.round(block * 0.55), practice = block - read;
        const count = Math.max(5, Math.round(practice / 1.2));
        items.push({
          key: key(items.length + 1),
          type: 'read',
          minutes: read,
          subject_id: s.id,
          topic_id: t.id,
          title_bn: `${s.name_bn}: ${t.name_bn} — পড়া`,
          title_en: `${s.name_en}: ${t.name_en} — study`,
        });
        items.push({
          key: key(items.length + 1),
          type: 'practice',
          minutes: practice,
          subject_id: s.id,
          topic_id: t.id,
          count,
          title_bn: `${t.name_bn} — ${bn(count)}টি প্রশ্ন অনুশীলন`,
          title_en: `${t.name_en} — practise ${count} questions`,
        });
        budget -= block;
        studied.push(t);
        heap.push(t, top.p * 0.55);
        for (const gap of [3, 7, 16]) scheduleRevision(t, d + gap);
      }
      const first = studied[0];
      title_bn = first ? `${subjectById.get(first.subject_id)!.name_bn}: ${first.name_bn}` : 'পড়া ও অনুশীলন';
      title_en = first
        ? `${subjectById.get(first.subject_id)!.name_en}: ${first.name_en}`
        : 'Study & practice';
      if (studied.length > 1) {
        title_bn += ` ও আরও ${bn(studied.length - 1)}টি`;
        title_en += ` + ${studied.length - 1} more`;
      }
    } else if (kind === 'weak_topic_exam') {
      weakDays++;
      title_bn = 'দুর্বল টপিক পরীক্ষার দিন';
      title_en = 'Weak-topic exam day';
      items.push({
        key: key(items.length + 1),
        type: 'exam',
        exam_kind: 'weak_topic',
        count: 20,
        minutes: 15,
        title_bn: 'দুর্বল টপিক থেকে ২০ প্রশ্নের পরীক্ষা',
        title_en: '20-question exam on your weak topics',
      });
      items.push({
        key: key(items.length + 1),
        type: 'revise',
        minutes: Math.max(15, Math.min(40, minutes - caMinutes - 15)),
        route: '/wrong-answers',
        title_bn: 'ভুলের খাতা রিভিশন',
        title_en: 'Revise your wrong answers',
      });
    } else if (kind === 'model_test') {
      modelTests++;
      const size = d >= practiceEnd && minutes >= 150 ? 200 : 100;
      title_bn = `মডেল টেস্ট দিবস (${bn(size)} নম্বর)`;
      title_en = `Model test day (${size} marks)`;
      items.push({
        key: key(items.length + 1),
        type: 'exam',
        exam_kind: 'model_test',
        size,
        minutes: Math.round(size * 0.6),
        title_bn: `${bn(size)} নম্বরের পূর্ণাঙ্গ মডেল টেস্ট`,
        title_en: `Full ${size}-mark model test`,
      });
      items.push({
        key: key(items.length + 1),
        type: 'revise',
        minutes: 20,
        route: '/exams/history',
        title_bn: 'ফলাফল বিশ্লেষণ ও ভুল প্রশ্ন দেখা',
        title_en: 'Analyse results and review mistakes',
      });
    } else {
      title_bn = 'রিভিশন দিবস';
      title_en = 'Revision day';
      const revTopics = revisions[d].length ? revisions[d] : [];
      for (const t of revTopics) {
        items.push({
          key: key(items.length + 1),
          type: 'revise',
          minutes: 20,
          subject_id: t.subject_id,
          topic_id: t.id,
          title_bn: `রিভিশন: ${t.name_bn}`,
          title_en: `Revise: ${t.name_en}`,
        });
      }
      items.push({
        key: key(items.length + 1),
        type: 'exam',
        exam_kind: 'weak_topic',
        count: 25,
        minutes: 20,
        title_bn: 'দুর্বল টপিক থেকে ২৫ প্রশ্নের পরীক্ষা',
        title_en: '25-question weak-topic exam',
      });
      items.push({
        key: key(items.length + 1),
        type: 'revise',
        minutes: 20,
        route: '/wrong-answers',
        title_bn: 'ভুলের খাতা রিভিশন',
        title_en: 'Revise your wrong answers',
      });
    }

    days.push({
      day_date: date,
      day_index: d + 1,
      kind,
      title_bn,
      title_en,
      items,
      target_minutes: items.reduce((a, i) => a + i.minutes, 0),
      total_items: items.length,
    });
  }

  const phase = (
    key: string,
    nameBn: string,
    nameEn: string,
    from: number,
    to: number,
    focusBn: string,
    focusEn: string,
  ) => ({
    key,
    name_bn: nameBn,
    name_en: nameEn,
    start_date: addDays(input.startDate, from),
    end_date: addDays(input.startDate, Math.max(from, to - 1)),
    focus_bn: focusBn,
    focus_en: focusEn,
  });
  const firstModel = kinds.indexOf('model_test');
  const summary = {
    total_days: total,
    weekly_hours: Math.round((minutes * 7) / 60),
    daily_minutes: minutes,
    model_tests: modelTests,
    weak_topic_days: weakDays,
    phases: [
      phase(
        'foundation',
        'ভিত্তি গঠন',
        'Foundation',
        0,
        foundationEnd,
        'সিলেবাসের সব টপিক একবার শেষ করা, দুর্বল টপিকে বেশি সময়',
        'Cover every topic once, more time on weak ones',
      ),
      phase(
        'practice',
        'অনুশীলন ও মডেল টেস্ট',
        'Practice & model tests',
        foundationEnd,
        practiceEnd,
        'নিয়মিত অনুশীলন, সাপ্তাহিক মডেল টেস্ট ও রিভিশন',
        'Regular practice, weekly model tests and revision',
      ),
      phase(
        'final',
        'চূড়ান্ত রিভিশন',
        'Final revision',
        practiceEnd,
        total,
        'পূর্ণাঙ্গ মডেল টেস্ট ও দুর্বল জায়গা ঠিক করা',
        'Full model tests and fixing weak spots',
      ),
    ],
    milestones: [
      {
        date: addDays(input.startDate, Math.max(0, foundationEnd - 1)),
        title_bn: 'সিলেবাস একবার শেষ',
        title_en: 'Syllabus covered once',
      },
      ...(firstModel >= 0
        ? [{
          date: addDays(input.startDate, firstModel),
          title_bn: 'প্রথম মডেল টেস্ট',
          title_en: 'First model test',
        }]
        : []),
      {
        date: addDays(input.startDate, practiceEnd),
        title_bn: 'চূড়ান্ত রিভিশন শুরু',
        title_en: 'Final revision begins',
      },
      { date: input.examDate, title_bn: 'পরীক্ষার দিন 🎯', title_en: 'Exam day 🎯' },
    ],
  };
  return { days, summary };
}
