import { useQuery } from '@tanstack/react-query';
import { toApiError } from './errors';
import { supabase } from './supabase';
import type { ExamType, Source, Subject, Topic } from './types';

const LONG = 10 * 60 * 1000;

async function select<T>(table: string, columns: string, order: string): Promise<T[]> {
  const { data, error } = await supabase.from(table).select(columns).order(order).limit(2000);
  if (error) throw toApiError(error);
  return (data ?? []) as T[];
}

/** Reference data (readable by any signed-in user via RLS), cached for 10 minutes. */
export function useSubjects() {
  return useQuery({
    queryKey: ['catalog', 'subjects'],
    queryFn: () => select<Subject>('subjects', 'id, code, name_bn, name_en, bcs_marks, sort', 'sort'),
    staleTime: LONG,
  });
}

export function useTopics() {
  return useQuery({
    queryKey: ['catalog', 'topics'],
    queryFn: () => select<Topic>('topics', 'id, subject_id, code, name_bn, name_en, is_general, sort', 'sort'),
    staleTime: LONG,
  });
}

export function useSources() {
  return useQuery({
    queryKey: ['catalog', 'sources'],
    queryFn: () => select<Source>('sources', 'id, kind, name, year, publisher, url, exam_type', 'name'),
    staleTime: LONG,
  });
}

export function useExamTypes() {
  return useQuery({
    queryKey: ['catalog', 'exam_types'],
    queryFn: () => select<ExamType>('exam_types', 'code, name_bn, name_en, sort', 'sort'),
    staleTime: LONG,
  });
}

export function subjectName(subjects: Subject[] | undefined, id: number | null | undefined): string {
  if (id === null || id === undefined) return '—';
  const s = subjects?.find((x) => x.id === id);
  return s ? s.name_en : `#${id}`;
}

export function topicName(topics: Topic[] | undefined, id: number | null | undefined): string {
  if (id === null || id === undefined) return '—';
  const t = topics?.find((x) => x.id === id);
  return t ? t.name_en : `#${id}`;
}
