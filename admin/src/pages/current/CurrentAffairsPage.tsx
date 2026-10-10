import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { CalendarDays, CheckCircle2, ChevronDown, ExternalLink, EyeOff, Pencil, Send, Trash2 } from 'lucide-react';
import { useState } from 'react';
import { useSearchParams } from 'react-router';
import { ReviewBadge, StatusBadge } from '../../components/badges';
import { useConfirm, useToast } from '../../components/feedback';
import { Badge, Button, Card, cx, EmptyState, ErrorState, Input, LoadMore, PageHeader, Spinner, TabLinks } from '../../components/ui';
import { bdToday, fmtDate, fmtDateTime, fmtNumber, fmtPercent, fmtWeekday } from '../../lib/format';
import { usePageTitle } from '../../lib/hooks';
import { useKeyset } from '../../lib/keyset';
import { rpc } from '../../lib/rpc';
import type { DailyExam, NoteDay, NoteRow } from '../../lib/types';
import { NoteEditor } from './NoteEditor';
import { CA_TABS } from './tabs';

const DAYS_PAGE = 30;

export default function CurrentAffairsPage() {
  usePageTitle('Current affairs');
  const [params, setParams] = useSearchParams();
  const days = useKeyset<NoteDay, string>({
    key: ['note-days'],
    pageSize: DAYS_PAGE,
    fetchPage: (before) => rpc<NoteDay[]>('admin_list_note_days', { p_before: before, p_limit: DAYS_PAGE }),
    cursorOf: (last) => last.date,
  });
  const date = params.get('date') ?? days.items[0]?.date ?? bdToday();
  const tab = params.get('view') === 'exam' ? 'exam' : 'notes';
  const setDate = (d: string) => setParams({ date: d, ...(tab === 'exam' ? { view: 'exam' } : {}) }, { replace: true });

  return (
    <div>
      <PageHeader
        title="Current affairs"
        description="Daily notes (visible to learners only on their own day, kept forever) and the daily exam built from them."
      />
      <TabLinks tabs={CA_TABS} />
      <div className="grid gap-5 lg:grid-cols-[16rem_minmax(0,1fr)]">
        <Card pad={false} className="h-fit">
          <div className="border-b border-line p-3">
            <label className="flex items-center gap-2 text-sm">
              <CalendarDays className="size-4 text-muted" aria-hidden />
              <span className="sr-only">Jump to date</span>
              <Input type="date" value={date} max={bdToday()} onChange={(e) => e.target.value && setDate(e.target.value)} />
            </label>
          </div>
          {days.error ? <ErrorState compact error={days.error} onRetry={() => void days.refetch()} /> : null}
          {days.isLoading ? (
            <Spinner />
          ) : (
            <ul className="max-h-[60dvh] overflow-y-auto py-1" aria-label="Days with notes">
              {days.items.map((d) => (
                <li key={d.date}>
                  <button
                    type="button"
                    onClick={() => setDate(d.date)}
                    aria-current={d.date === date ? 'date' : undefined}
                    className={cx(
                      'flex w-full items-center justify-between gap-2 px-3 py-2 text-left text-sm',
                      d.date === date ? 'bg-brand-soft text-brand-strong dark:text-brand' : 'hover:bg-surface-2',
                    )}
                  >
                    <span>
                      <span className="block font-medium">{fmtWeekday(d.date)}</span>
                      <span className="text-xs text-muted">{d.date === bdToday() ? 'today' : d.date.slice(0, 4)}</span>
                    </span>
                    <span className="flex items-center gap-1 text-xs">
                      <Badge tone={d.published ? 'success' : 'neutral'}>{d.published} notes</Badge>
                      {d.daily_exam ? <Badge tone="info">exam</Badge> : null}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          )}
          <LoadMore hasMore={!!days.hasNextPage} loading={days.isFetchingNextPage} onClick={() => void days.fetchNextPage()} />
        </Card>

        <div className="min-w-0 space-y-4">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <h2 className="text-lg font-semibold">{fmtDate(date)}</h2>
            <div role="tablist" aria-label="Content" className="inline-flex rounded-lg border border-line-strong bg-surface p-0.5">
              {(['notes', 'exam'] as const).map((v) => (
                <button
                  key={v}
                  role="tab"
                  type="button"
                  aria-selected={tab === v}
                  onClick={() => setParams(v === 'exam' ? { date, view: 'exam' } : { date }, { replace: true })}
                  className={cx(
                    'rounded-md px-3 py-1 text-sm font-medium',
                    tab === v ? 'bg-brand-soft text-brand-strong dark:text-brand' : 'text-muted hover:text-fg',
                  )}
                >
                  {v === 'notes' ? 'Notes' : 'Daily exam'}
                </button>
              ))}
            </div>
          </div>
          {tab === 'notes' ? <NotesForDay date={date} /> : <ExamForDay date={date} />}
        </div>
      </div>
    </div>
  );
}

function NotesForDay({ date }: { date: string }) {
  const qc = useQueryClient();
  const toast = useToast();
  const confirm = useConfirm();
  const [editing, setEditing] = useState<NoteRow | null>(null);
  const [expanded, setExpanded] = useState<Set<number>>(new Set());
  const notes = useQuery({ queryKey: ['notes', date], queryFn: () => rpc<NoteRow[]>('admin_list_notes', { p_date: date }) });

  const refresh = () => {
    void qc.invalidateQueries({ queryKey: ['notes', date] });
    void qc.invalidateQueries({ queryKey: ['note-days'] });
    void qc.invalidateQueries({ queryKey: ['dashboard'] });
  };
  const setStatus = useMutation({
    mutationFn: (a: { id: number; status: NoteRow['status'] }) => rpc('admin_update_note', { p_id: a.id, p_patch: { status: a.status } }),
    onSuccess: (_r, a) => {
      toast.success(a.status === 'published' ? 'Note published.' : 'Note unpublished.');
      refresh();
    },
    onError: (e) => toast.error(e),
  });
  const del = useMutation({
    mutationFn: (id: number) => rpc('admin_delete_note', { p_id: id }),
    onSuccess: () => {
      toast.success('Note deleted.');
      refresh();
    },
    onError: (e) => toast.error(e),
  });

  if (notes.error) return <ErrorState error={notes.error} onRetry={() => void notes.refetch()} />;
  if (notes.isLoading) return <Spinner />;
  const rows = notes.data ?? [];
  if (!rows.length)
    return (
      <Card>
        <EmptyState title="No notes for this day">
          The morning pipeline writes notes at 05:20 and tops them up at 15:30 (Bangladesh time).
        </EmptyState>
      </Card>
    );

  return (
    <>
      <ul className="space-y-3">
        {rows.map((n) => {
          const open = expanded.has(n.id);
          return (
            <li key={n.id} className="card overflow-hidden">
              <div className="flex flex-wrap items-start gap-3 p-4">
                <button
                  type="button"
                  aria-expanded={open}
                  onClick={() => {
                    const next = new Set(expanded);
                    if (open) next.delete(n.id);
                    else next.add(n.id);
                    setExpanded(next);
                  }}
                  className="flex min-w-0 flex-1 items-start gap-2 text-left"
                >
                  <ChevronDown className={cx('mt-1 size-4 shrink-0 text-muted transition-transform', open && 'rotate-180')} aria-hidden />
                  <span className="min-w-0">
                    <span className="block font-semibold text-fg" lang="bn">
                      {n.title}
                    </span>
                    {n.title_en ? (
                      <span className="block text-sm text-muted">{n.title_en}</span>
                    ) : (
                      <span className="block text-xs text-warning">No English title</span>
                    )}
                    <span className="mt-1.5 flex flex-wrap gap-1">
                      <Badge tone={n.status === 'published' ? 'success' : n.status === 'draft' ? 'info' : 'neutral'}>{n.status}</Badge>
                      <Badge>{n.category.replace('_', ' ')}</Badge>
                      <Badge>importance {n.importance}</Badge>
                      <Badge>{n.fact_count} facts</Badge>
                    </span>
                  </span>
                </button>
                <div className="flex flex-wrap gap-1.5">
                  <Button size="sm" icon={<Pencil className="size-3.5" />} onClick={() => setEditing(n)}>
                    Edit
                  </Button>
                  {n.status === 'published' ? (
                    <Button
                      size="sm"
                      icon={<EyeOff className="size-3.5" />}
                      loading={setStatus.isPending && setStatus.variables?.id === n.id}
                      onClick={() => setStatus.mutate({ id: n.id, status: 'archived' })}
                    >
                      Unpublish
                    </Button>
                  ) : (
                    <Button
                      size="sm"
                      icon={<Send className="size-3.5" />}
                      loading={setStatus.isPending && setStatus.variables?.id === n.id}
                      onClick={() => setStatus.mutate({ id: n.id, status: 'published' })}
                    >
                      Publish
                    </Button>
                  )}
                  <Button
                    size="sm"
                    variant="danger-ghost"
                    icon={<Trash2 className="size-3.5" />}
                    loading={del.isPending && del.variables === n.id}
                    onClick={async () => {
                      const ok = await confirm({
                        title: 'Delete this note permanently?',
                        message: 'Unpublishing keeps it in the archive; deleting removes it for good.',
                        confirmLabel: 'Delete',
                        tone: 'danger',
                      });
                      if (ok) del.mutate(n.id);
                    }}
                  >
                    Delete
                  </Button>
                </div>
              </div>
              {open ? (
                <div className="grid gap-4 border-t border-line p-4 md:grid-cols-2">
                  <NoteLang title="বাংলা" lang="bn" summary={n.summary} facts={n.key_facts.map((f) => f.fact)} qa={n.probable_questions} />
                  <NoteLang
                    title="English"
                    lang="en"
                    summary={n.summary_en}
                    facts={n.key_facts_en.map((f) => f.fact)}
                    qa={n.probable_questions_en}
                  />
                  {n.source_links.length ? (
                    <div className="md:col-span-2">
                      <p className="mb-1 text-xs font-semibold text-muted uppercase">Sources</p>
                      <ul className="space-y-0.5 text-sm">
                        {n.source_links.map((l, i) =>
                          l.url ? (
                            <li key={i}>
                              <a
                                href={l.url}
                                target="_blank"
                                rel="noreferrer noopener"
                                className="inline-flex items-center gap-1 text-info hover:underline"
                                lang="bn"
                              >
                                {l.source ? `${l.source}: ` : ''}
                                {l.title ?? l.url} <ExternalLink className="size-3" />
                              </a>
                            </li>
                          ) : null,
                        )}
                      </ul>
                    </div>
                  ) : null}
                  <p className="text-xs text-muted md:col-span-2">
                    Created {fmtDateTime(n.created_at)}
                    {n.model ? ` · ${n.model}` : ''}
                  </p>
                </div>
              ) : null}
            </li>
          );
        })}
      </ul>
      {editing ? <NoteEditor note={editing} onClose={() => setEditing(null)} onSaved={refresh} /> : null}
    </>
  );
}

function NoteLang({
  title,
  lang,
  summary,
  facts,
  qa,
}: {
  title: string;
  lang: 'bn' | 'en';
  summary: string | null;
  facts: string[];
  qa: { q: string; a: string }[];
}) {
  return (
    <div lang={lang === 'bn' ? 'bn' : undefined} className="min-w-0 space-y-2 text-sm">
      <p className="text-xs font-semibold text-muted uppercase" lang="en">
        {title}
      </p>
      {summary ? (
        <p className="whitespace-pre-wrap text-fg">{summary}</p>
      ) : (
        <p className="text-warning" lang="en">
          Missing
        </p>
      )}
      {facts.length ? (
        <ul className="list-disc space-y-1 pl-5 text-fg-2">
          {facts.map((f, i) => (
            <li key={i}>{f}</li>
          ))}
        </ul>
      ) : null}
      {qa.length ? (
        <dl className="space-y-1 rounded-lg bg-surface-2 p-2 text-xs">
          {qa.map((x, i) => (
            <div key={i}>
              <dt className="font-medium text-fg">{x.q}</dt>
              <dd className="text-fg-2">{x.a}</dd>
            </div>
          ))}
        </dl>
      ) : null}
    </div>
  );
}

function ExamForDay({ date }: { date: string }) {
  const exam = useQuery({ queryKey: ['daily-exam', date], queryFn: () => rpc<DailyExam | null>('admin_get_daily_exam', { p_date: date }) });
  if (exam.error) return <ErrorState error={exam.error} onRetry={() => void exam.refetch()} />;
  if (exam.isLoading) return <Spinner />;
  const e = exam.data;
  if (!e)
    return (
      <Card>
        <EmptyState title="No daily exam for this day">The exam is generated at 05:50 (Bangladesh time) from the day's facts.</EmptyState>
      </Card>
    );
  return (
    <div className="space-y-4">
      <Card>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <p className="font-semibold" lang="bn">
              {e.title_bn}
            </p>
            {e.title_en ? <p className="text-sm text-muted">{e.title_en}</p> : null}
          </div>
          <Badge tone={e.status === 'published' ? 'success' : 'neutral'}>{e.status}</Badge>
        </div>
        <div className="mt-3 grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
          <Mini label="Questions" value={fmtNumber(e.questions.length)} />
          <Mini label="Duration" value={`${e.duration_minutes} min`} />
          <Mini label="Negative mark" value={`−${e.negative_mark}`} />
          <Mini
            label="Submissions"
            value={fmtNumber(e.submissions.count)}
            sub={e.submissions.avg_score !== null ? `avg ${e.submissions.avg_score} · best ${e.submissions.max_score}` : undefined}
          />
        </div>
      </Card>
      <ol className="space-y-3">
        {e.questions.map((q, i) => (
          <li key={q.id} className="card p-4">
            <div className="mb-2 flex flex-wrap items-center gap-1.5 text-xs text-muted">
              <span className="font-semibold text-fg">Q{i + 1}</span> · #{q.id}
              <StatusBadge status={q.status} />
              <ReviewBadge review={q.review_status} />
              {q.times_answered ? (
                <span>
                  · {fmtPercent(q.times_correct, q.times_answered)} correct of {q.times_answered}
                </span>
              ) : null}
            </div>
            <p className="text-fg" lang="bn">
              {q.stem}
            </p>
            <ol className="mt-2 grid gap-1 sm:grid-cols-2">
              {q.options.map((o, j) => (
                <li
                  key={j}
                  className={cx(
                    'flex items-start gap-1.5 rounded-md px-2 py-1 text-sm',
                    j === q.correct_index ? 'bg-success-soft text-success' : 'text-fg-2',
                  )}
                  lang="bn"
                >
                  <span className="font-semibold">{String.fromCharCode(65 + j)}.</span> {o}
                  {j === q.correct_index ? <CheckCircle2 className="ml-auto size-4 shrink-0" aria-label="correct" /> : null}
                </li>
              ))}
            </ol>
            {q.explanation ? (
              <p className="mt-2 text-sm text-muted" lang="bn">
                {q.explanation}
              </p>
            ) : null}
            {q.source_ref ? (
              <p className="mt-1 text-xs text-muted" lang="bn">
                {q.source_url ? (
                  <a href={q.source_url} target="_blank" rel="noreferrer noopener" className="text-info hover:underline">
                    {q.source_ref}
                  </a>
                ) : (
                  q.source_ref
                )}
              </p>
            ) : null}
          </li>
        ))}
      </ol>
    </div>
  );
}

function Mini({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="rounded-lg bg-surface-2 px-3 py-2">
      <p className="text-xs text-muted">{label}</p>
      <p className="font-semibold">{value}</p>
      {sub ? <p className="text-xs text-muted">{sub}</p> : null}
    </div>
  );
}
