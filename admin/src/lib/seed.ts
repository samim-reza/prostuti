/**
 * Question seed format (supabase/seed/questions/README.md). The checks mirror
 * public._admin_question_error so the import preview matches what the server
 * will accept; the server validates again regardless.
 */
import type { Subject, Topic } from './types';

export interface SeedQuestion {
  subject: string;
  topic?: string | null;
  stem: string;
  options: string[];
  correct_index: number;
  explanation?: string | null;
  difficulty?: number | null;
  language?: 'bn' | 'en';
  exam_tags?: string[];
  source_kind?: string;
  source_name?: string | null;
  source_year?: number | null;
  source_ref?: string | null;
  source_url?: string | null;
}

export const VALID_KINDS = ['previous_exam', 'book', 'newspaper', 'website', 'ai_generated', 'curated'];
export const VALID_TAGS = ['bcs', 'bank', 'govt'];

const URL_RE = /^https?:\/\/[^\s/$.?#][^\s]*$/i;

export const SEED_ERRORS: Record<string, string> = {
  not_an_object: 'not an object',
  stem_length: 'stem must be 3–2000 characters',
  options_not_array: 'options must be an array',
  options_count: 'needs 2–5 options',
  option_invalid: 'every option must be non-empty text (≤ 500 chars)',
  options_not_distinct: 'options must be distinct',
  correct_index_range: 'correct_index must be a 0-based index into options',
  difficulty_range: 'difficulty must be 1–5',
  language_invalid: 'language must be "bn" or "en"',
  exam_tags_not_array: 'exam_tags must be an array',
  exam_tag_invalid: 'exam_tags may only contain bcs, bank, govt',
  explanation_length: 'explanation is longer than 4000 characters',
  source_kind_invalid: 'unknown source_kind',
  source_name_length: 'source_name is longer than 200 characters',
  source_ref_length: 'source_ref is longer than 300 characters',
  source_url_invalid: 'source_url must be an http(s) URL',
  year_invalid: 'source_year must be a 4-digit year',
  subject_unknown: 'unknown subject code',
  topic_unknown: 'unknown topic code',
  topic_subject_mismatch: 'topic belongs to another subject',
};

export function describeSeedError(code: string): string {
  return SEED_ERRORS[code] ?? code;
}

function isObj(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

/** Returns an error code (see SEED_ERRORS) or null when the item is valid. */
export function validateSeed(item: unknown, subjects: Subject[], topics: Topic[]): string | null {
  if (!isObj(item)) return 'not_an_object';
  const stem = typeof item.stem === 'string' ? item.stem.trim() : '';
  if (stem.length < 3 || stem.length > 2000) return 'stem_length';
  const opts = item.options;
  if (!Array.isArray(opts)) return 'options_not_array';
  if (opts.length < 2 || opts.length > 5) return 'options_count';
  if (opts.some((o) => typeof o !== 'string' || o.trim() === '' || o.length > 500)) return 'option_invalid';
  if (new Set(opts.map((o) => (o as string).trim())).size !== opts.length) return 'options_not_distinct';
  const ci = item.correct_index;
  if (typeof ci !== 'number' || !Number.isInteger(ci) || ci < 0 || ci >= opts.length) return 'correct_index_range';
  if (item.difficulty !== undefined && item.difficulty !== null) {
    const d = Number(item.difficulty);
    if (!Number.isInteger(d) || d < 1 || d > 5) return 'difficulty_range';
  }
  if (item.language !== undefined && item.language !== 'bn' && item.language !== 'en') return 'language_invalid';
  if (item.exam_tags !== undefined && item.exam_tags !== null) {
    if (!Array.isArray(item.exam_tags)) return 'exam_tags_not_array';
    if (item.exam_tags.some((t) => typeof t !== 'string' || !VALID_TAGS.includes(t))) return 'exam_tag_invalid';
  }
  if (typeof item.explanation === 'string' && item.explanation.length > 4000) return 'explanation_length';
  if (item.source_kind !== undefined && item.source_kind !== null && !VALID_KINDS.includes(String(item.source_kind))) {
    return 'source_kind_invalid';
  }
  if (typeof item.source_name === 'string' && item.source_name.length > 200) return 'source_name_length';
  if (typeof item.source_ref === 'string' && item.source_ref.length > 300) return 'source_ref_length';
  if (typeof item.source_url === 'string' && item.source_url.trim() !== '' && !URL_RE.test(item.source_url.trim())) {
    return 'source_url_invalid';
  }
  const year = item.year ?? item.source_year;
  if (year !== undefined && year !== null && year !== '') {
    const y = Number(year);
    if (!/^\d{4}$/.test(String(year)) || y < 1950 || y > 2100) return 'year_invalid';
  }
  const subject = subjects.find((s) => s.code === item.subject);
  if (!subject) return 'subject_unknown';
  if (typeof item.topic === 'string' && item.topic !== '') {
    const topic = topics.find((t) => t.code === item.topic);
    if (!topic) return 'topic_unknown';
    if (topic.subject_id !== subject.id) return 'topic_subject_mismatch';
  }
  return null;
}

/** Same normalisation as questions.stem_hash (whitespace-free, lower case) for in-file duplicates. */
export function stemKey(stem: string): string {
  return stem.replace(/\s+/g, '').toLowerCase();
}
