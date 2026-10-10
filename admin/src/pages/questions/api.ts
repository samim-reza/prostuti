import { clean, rpc } from '../../lib/rpc';
import type { QuestionRow } from '../../lib/types';

export interface QuestionFilters {
  subject: string;
  topic: string;
  tag: string;
  status: string;
  review: string;
  kind: string;
  q: string;
}

export const EMPTY_FILTERS: QuestionFilters = { subject: '', topic: '', tag: '', status: '', review: '', kind: '', q: '' };

export function filterArgs(f: QuestionFilters): Record<string, unknown> {
  return clean({
    p_subject: f.subject ? Number(f.subject) : undefined,
    p_topic: f.topic ? Number(f.topic) : undefined,
    p_tag: f.tag,
    p_status: f.status,
    p_review: f.review,
    p_source_kind: f.kind,
    p_search: f.q.trim(),
  });
}

export const PAGE_SIZE = 30;

export function fetchQuestions(f: QuestionFilters, afterId: number | null): Promise<QuestionRow[]> {
  return rpc<QuestionRow[]>('admin_search_questions', {
    ...filterArgs(f),
    p_limit: PAGE_SIZE,
    ...(afterId ? { p_after_id: afterId } : {}),
  });
}

/** Seed-format rows (round-trip through import). Pages of 1000, keyset by id. */
export async function exportQuestions(
  f: QuestionFilters,
  onProgress: (n: number) => void,
  max = 50_000,
): Promise<Record<string, unknown>[]> {
  const out: Record<string, unknown>[] = [];
  let after: number | null = null;
  for (;;) {
    const page: Record<string, unknown>[] = await rpc<Record<string, unknown>[]>('admin_export_questions', {
      ...filterArgs(f),
      p_limit: 1000,
      ...(after ? { p_after_id: after } : {}),
    });
    out.push(...page);
    onProgress(out.length);
    if (page.length < 1000 || out.length >= max) break;
    after = Number(page[page.length - 1]!.id);
  }
  return out;
}
