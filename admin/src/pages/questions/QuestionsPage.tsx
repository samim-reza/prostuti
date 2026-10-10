import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Archive, CheckCircle2, Download, Flag, Plus, Search, Send, Upload, X, XCircle } from 'lucide-react';
import { useMemo, useState, type ReactNode } from 'react';
import { useSearchParams } from 'react-router';
import { useIsAdmin } from '../../auth/AuthProvider';
import { ReviewBadge, StatusBadge } from '../../components/badges';
import { useConfirm, useToast } from '../../components/feedback';
import { Badge, Button, Card, EmptyState, ErrorState, Input, LoadMore, PageHeader, Select, Spinner, TableWrap } from '../../components/ui';
import { subjectName, useSubjects, useTopics } from '../../lib/catalog';
import { downloadJson } from '../../lib/download';
import { bdToday, fmtPercent, truncate } from '../../lib/format';
import { useDebounced, usePageTitle } from '../../lib/hooks';
import { useKeyset } from '../../lib/keyset';
import { rpc } from '../../lib/rpc';
import { SOURCE_KINDS, TRACKS, trackLabel, type QuestionRow } from '../../lib/types';
import { exportQuestions, fetchQuestions, PAGE_SIZE, type QuestionFilters } from './api';
import { ImportDialog } from './ImportDialog';
import { QuestionDrawer } from './QuestionDrawer';
import { QuestionEditor } from './QuestionEditor';

type BulkAction = { label: string; status?: string; review?: string; icon: ReactNode; danger?: boolean };
const BULK: BulkAction[] = [
  { label: 'Verify', review: 'verified', icon: <CheckCircle2 className="size-3.5" /> },
  { label: 'Flag', review: 'flagged', icon: <Flag className="size-3.5" /> },
  { label: 'Publish', status: 'published', icon: <Send className="size-3.5" /> },
  { label: 'Archive', status: 'archived', icon: <Archive className="size-3.5" /> },
  { label: 'Reject', status: 'rejected', icon: <XCircle className="size-3.5" />, danger: true },
];

export default function QuestionsPage() {
  usePageTitle('Questions');
  const isAdmin = useIsAdmin();
  const toast = useToast();
  const confirm = useConfirm();
  const qc = useQueryClient();
  const [params, setParams] = useSearchParams();
  const subjects = useSubjects();
  const topics = useTopics();

  const filters: QuestionFilters = useMemo(
    () => ({
      subject: params.get('subject') ?? '',
      topic: params.get('topic') ?? '',
      tag: params.get('tag') ?? '',
      status: params.get('status') ?? '',
      review: params.get('review') ?? '',
      kind: params.get('kind') ?? '',
      q: params.get('q') ?? '',
    }),
    [params],
  );
  const [searchText, setSearchText] = useState(filters.q);
  const debouncedQ = useDebounced(searchText.trim(), 350);
  const effective = useMemo(() => ({ ...filters, q: debouncedQ }), [filters, debouncedQ]);

  const selectedId = params.get('id') ? Number(params.get('id')) : null;
  const [editing, setEditing] = useState<{ id: number | null } | null>(null);
  const [importOpen, setImportOpen] = useState(false);
  const [checked, setChecked] = useState<Set<number>>(new Set());
  const [exporting, setExporting] = useState<number | null>(null);

  const setParam = (patch: Partial<Record<keyof QuestionFilters | 'id', string | null>>) => {
    const next = new URLSearchParams(params);
    for (const [k, v] of Object.entries(patch)) {
      if (v) next.set(k, v);
      else next.delete(k);
    }
    setParams(next, { replace: true });
    if (!('id' in patch)) setChecked(new Set());
  };

  const list = useKeyset<QuestionRow, number>({
    key: ['questions', effective],
    pageSize: PAGE_SIZE,
    fetchPage: (cursor) => fetchQuestions(effective, cursor),
    cursorOf: (last) => last.id,
  });

  const bulk = useMutation({
    mutationFn: (a: BulkAction) =>
      rpc<number>('admin_set_question_status', { p_ids: [...checked], p_status: a.status ?? null, p_review_status: a.review ?? null }),
    onSuccess: (n, a) => {
      toast.success(`${a.label}: ${n} question${n === 1 ? '' : 's'} updated.`);
      setChecked(new Set());
      void qc.invalidateQueries({ queryKey: ['questions'] });
      void qc.invalidateQueries({ queryKey: ['question'] });
    },
    onError: (e) => toast.error(e),
  });

  const topicOptions = (topics.data ?? []).filter((t) => !filters.subject || t.subject_id === Number(filters.subject));
  const activeFilters = Object.entries(filters).filter(([k, v]) => v && k !== 'q').length + (debouncedQ ? 1 : 0);
  const allChecked = list.items.length > 0 && list.items.every((q) => checked.has(q.id));

  async function runExport() {
    setExporting(0);
    try {
      const rows = await exportQuestions(effective, setExporting);
      downloadJson(`prostuti-questions-${bdToday()}.json`, rows);
      toast.success(`Exported ${rows.length} questions.`);
    } catch (e) {
      toast.error(e);
    } finally {
      setExporting(null);
    }
  }

  return (
    <div>
      <PageHeader
        title="Questions"
        description="The sourced question bank. Filter, review, edit, import and export."
        actions={
          <>
            <Button icon={<Download className="size-4" />} loading={exporting !== null} onClick={() => void runExport()}>
              {exporting !== null ? `Exporting ${exporting}…` : 'Export JSON'}
            </Button>
            {isAdmin ? (
              <Button icon={<Upload className="size-4" />} onClick={() => setImportOpen(true)}>
                Import JSON
              </Button>
            ) : null}
            <Button variant="primary" icon={<Plus className="size-4" />} onClick={() => setEditing({ id: null })}>
              New question
            </Button>
          </>
        }
      />
      <Card pad={false}>
        <div className="grid grid-cols-2 gap-2 border-b border-line p-3 lg:grid-cols-4 xl:grid-cols-8">
          <label className="relative col-span-2">
            <span className="sr-only">Search question text or #id</span>
            <Search className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted" aria-hidden />
            <Input
              type="search"
              placeholder="Search text or #id"
              className="pl-9"
              value={searchText}
              onChange={(e) => {
                setSearchText(e.target.value);
                setParam({ q: e.target.value.trim() || null });
              }}
            />
          </label>
          <Select aria-label="Subject" value={filters.subject} onChange={(e) => setParam({ subject: e.target.value || null, topic: null })}>
            <option value="">All subjects</option>
            {subjects.data?.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name_en}
              </option>
            ))}
          </Select>
          <Select
            aria-label="Topic"
            value={filters.topic}
            onChange={(e) => setParam({ topic: e.target.value || null })}
            disabled={!filters.subject}
          >
            <option value="">{filters.subject ? 'All topics' : 'Any topic'}</option>
            {topicOptions.map((t) => (
              <option key={t.id} value={t.id}>
                {t.name_en}
              </option>
            ))}
          </Select>
          <Select aria-label="Track" value={filters.tag} onChange={(e) => setParam({ tag: e.target.value || null })}>
            <option value="">All tracks</option>
            {TRACKS.map((t) => (
              <option key={t.code} value={t.code}>
                {t.label}
              </option>
            ))}
            <option value="none">No track tag</option>
          </Select>
          <Select aria-label="Status" value={filters.status} onChange={(e) => setParam({ status: e.target.value || null })}>
            <option value="">Any status</option>
            <option value="published">Published</option>
            <option value="draft">Draft</option>
            <option value="archived">Archived</option>
            <option value="rejected">Rejected</option>
          </Select>
          <Select aria-label="Review status" value={filters.review} onChange={(e) => setParam({ review: e.target.value || null })}>
            <option value="">Any review</option>
            <option value="unverified">Unverified</option>
            <option value="verified">Verified</option>
            <option value="flagged">Flagged</option>
          </Select>
          <Select aria-label="Source kind" value={filters.kind} onChange={(e) => setParam({ kind: e.target.value || null })}>
            <option value="">Any source</option>
            {SOURCE_KINDS.map((k) => (
              <option key={k.value} value={k.value}>
                {k.label}
              </option>
            ))}
          </Select>
        </div>
        {activeFilters > 0 ? (
          <div className="flex items-center gap-2 border-b border-line px-3 py-2 text-xs text-muted">
            <span>
              {activeFilters} filter{activeFilters === 1 ? '' : 's'} active
            </span>
            <Button
              size="sm"
              variant="ghost"
              icon={<X className="size-3.5" />}
              onClick={() => {
                setSearchText('');
                setParams(new URLSearchParams(), { replace: true });
                setChecked(new Set());
              }}
            >
              Clear
            </Button>
          </div>
        ) : null}
        {checked.size > 0 ? (
          <div
            className="flex flex-wrap items-center gap-2 border-b border-line bg-brand-soft/60 px-3 py-2"
            role="region"
            aria-label="Bulk actions"
          >
            <span className="text-sm font-medium">{checked.size} selected</span>
            {BULK.map((a) => (
              <Button
                key={a.label}
                size="sm"
                variant={a.danger ? 'danger-ghost' : 'secondary'}
                icon={a.icon}
                loading={bulk.isPending && bulk.variables?.label === a.label}
                onClick={async () => {
                  if (a.danger) {
                    const ok = await confirm({
                      title: `${a.label} ${checked.size} question${checked.size === 1 ? '' : 's'}?`,
                      message: 'Rejected questions leave the bank and are excluded from practice and exams.',
                      confirmLabel: a.label,
                      tone: 'danger',
                    });
                    if (!ok) return;
                  }
                  bulk.mutate(a);
                }}
              >
                {a.label}
              </Button>
            ))}
            <Button size="sm" variant="ghost" onClick={() => setChecked(new Set())}>
              Clear selection
            </Button>
          </div>
        ) : null}
        {list.error ? <ErrorState error={list.error} onRetry={() => void list.refetch()} /> : null}
        {list.isLoading ? (
          <Spinner />
        ) : list.items.length === 0 && !list.error ? (
          <EmptyState title="No questions match">Change the filters or add a question.</EmptyState>
        ) : (
          <TableWrap>
            <table className="table-base">
              <thead>
                <tr>
                  <th scope="col" className="w-8">
                    <input
                      type="checkbox"
                      aria-label="Select all loaded questions"
                      className="size-4 accent-[var(--brand)]"
                      checked={allChecked}
                      onChange={(e) => setChecked(e.target.checked ? new Set(list.items.slice(0, 500).map((q) => q.id)) : new Set())}
                    />
                  </th>
                  <th scope="col">#</th>
                  <th scope="col">Question</th>
                  <th scope="col">Subject</th>
                  <th scope="col">Tracks</th>
                  <th scope="col">Status</th>
                  <th scope="col">Source</th>
                  <th scope="col" className="text-right">
                    Correct
                  </th>
                </tr>
              </thead>
              <tbody>
                {list.items.map((q) => (
                  <tr
                    key={q.id}
                    className="row-link"
                    onClick={() => setParam({ id: String(q.id) })}
                    onKeyDown={(e) => e.key === 'Enter' && setParam({ id: String(q.id) })}
                    tabIndex={0}
                    aria-label={`Open question ${q.id}`}
                  >
                    <td onClick={(e) => e.stopPropagation()}>
                      <input
                        type="checkbox"
                        aria-label={`Select question ${q.id}`}
                        className="size-4 accent-[var(--brand)]"
                        checked={checked.has(q.id)}
                        onChange={(e) => {
                          const next = new Set(checked);
                          if (e.target.checked) next.add(q.id);
                          else next.delete(q.id);
                          setChecked(next);
                        }}
                      />
                    </td>
                    <td className="num text-xs text-muted">{q.id}</td>
                    <td className="min-w-72">
                      <p lang={q.language === 'bn' ? 'bn' : undefined} className="text-fg">
                        {truncate(q.stem, 140)}
                      </p>
                      <p className="mt-0.5 truncate text-xs text-muted" lang={q.language === 'bn' ? 'bn' : undefined}>
                        ✓ {truncate(q.options[q.correct_index] ?? '', 60)}
                      </p>
                      {q.open_reports > 0 ? (
                        <Badge tone="warning" className="mt-1" icon={<Flag className="size-3" />}>
                          {q.open_reports} open report{q.open_reports === 1 ? '' : 's'}
                        </Badge>
                      ) : null}
                    </td>
                    <td className="text-sm whitespace-nowrap text-fg-2">{subjectName(subjects.data, q.subject_id)}</td>
                    <td className="whitespace-nowrap">
                      <div className="flex flex-wrap gap-1">
                        {q.exam_tags.length ? (
                          q.exam_tags.map((t) => <Badge key={t}>{trackLabel(t)}</Badge>)
                        ) : (
                          <span className="text-xs text-muted">—</span>
                        )}
                      </div>
                    </td>
                    <td>
                      <div className="flex flex-col items-start gap-1">
                        <StatusBadge status={q.status} />
                        <ReviewBadge review={q.review_status} />
                      </div>
                    </td>
                    <td className="max-w-48 text-xs text-fg-2">
                      <p className="truncate" lang="bn">
                        {q.source_ref ?? q.source_name ?? '—'}
                      </p>
                      <p className="text-muted">{SOURCE_KINDS.find((k) => k.value === q.source_kind)?.label ?? ''}</p>
                    </td>
                    <td className="num text-right text-xs whitespace-nowrap">
                      {q.times_answered ? (
                        <>
                          {fmtPercent(q.times_correct, q.times_answered)}
                          <span className="block text-muted">of {q.times_answered}</span>
                        </>
                      ) : (
                        <span className="text-muted">—</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TableWrap>
        )}
        <LoadMore
          hasMore={!!list.hasNextPage}
          loading={list.isFetchingNextPage}
          onClick={() => void list.fetchNextPage()}
          count={list.items.length}
        />
      </Card>

      <QuestionDrawer id={selectedId} onClose={() => setParam({ id: null })} onEdit={(id) => setEditing({ id })} />
      {editing ? (
        <QuestionEditor
          id={editing.id}
          onClose={() => setEditing(null)}
          onSaved={(id) => {
            setEditing(null);
            setParam({ id: String(id) });
          }}
        />
      ) : null}
      {isAdmin ? <ImportDialog open={importOpen} onClose={() => setImportOpen(false)} /> : null}
    </div>
  );
}
