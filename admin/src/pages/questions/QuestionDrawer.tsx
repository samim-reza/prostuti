import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Archive, CheckCircle2, ExternalLink, Flag, Pencil, Send, XCircle } from 'lucide-react';
import { ReviewBadge, StatusBadge } from '../../components/badges';
import { EmphasisBars } from '../../components/charts';
import { useConfirm, useToast } from '../../components/feedback';
import { Modal } from '../../components/Modal';
import { Badge, Button, Card, cx, ErrorState, KeyValue, Spinner } from '../../components/ui';
import { fmtDate, fmtDateTime, fmtPercent } from '../../lib/format';
import { rpc } from '../../lib/rpc';
import { SOURCE_KINDS, trackLabel, type QuestionDetail } from '../../lib/types';

const LETTERS = ['A', 'B', 'C', 'D', 'E'];

export function QuestionDrawer({ id, onClose, onEdit }: { id: number | null; onClose: () => void; onEdit: (id: number) => void }) {
  const q = useQuery({
    queryKey: ['question', id],
    queryFn: () => rpc<QuestionDetail>('admin_get_question', { p_id: id }),
    enabled: id !== null,
  });
  return (
    <Modal open={id !== null} onClose={onClose} variant="drawer" title={id !== null ? `Question #${id}` : 'Question'}>
      {q.error ? <ErrorState error={q.error} onRetry={() => void q.refetch()} /> : null}
      {!q.data ? q.isLoading ? <Spinner /> : null : <Body d={q.data} onEdit={() => onEdit(q.data.id)} />}
    </Modal>
  );
}

function Body({ d, onEdit }: { d: QuestionDetail; onEdit: () => void }) {
  const qc = useQueryClient();
  const toast = useToast();
  const confirm = useConfirm();
  const lang = d.language === 'bn' ? 'bn' : undefined;
  const set = useMutation({
    mutationFn: (a: { label: string; status?: string; review?: string }) =>
      rpc<number>('admin_set_question_status', { p_ids: [d.id], p_status: a.status ?? null, p_review_status: a.review ?? null }),
    onSuccess: (_n, a) => {
      toast.success(`${a.label}: done.`);
      void qc.invalidateQueries({ queryKey: ['question', d.id] });
      void qc.invalidateQueries({ queryKey: ['questions'] });
    },
    onError: (e) => toast.error(e),
  });
  const answered = d.answer_stats.reduce((s, a) => s + a.count, 0);
  const busy = (label: string) => set.isPending && set.variables?.label === label;

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center gap-2">
        <StatusBadge status={d.status} />
        <ReviewBadge review={d.review_status} />
        {d.exam_tags.map((t) => (
          <Badge key={t}>{trackLabel(t)}</Badge>
        ))}
        {d.reports.open > 0 ? (
          <Badge tone="warning" icon={<Flag className="size-3" />}>
            {d.reports.open} open report{d.reports.open === 1 ? '' : 's'}
          </Badge>
        ) : null}
      </div>

      <div className="flex flex-wrap gap-2">
        <Button variant="primary" size="sm" icon={<Pencil className="size-3.5" />} onClick={onEdit}>
          Edit
        </Button>
        {d.review_status !== 'verified' ? (
          <Button
            size="sm"
            icon={<CheckCircle2 className="size-3.5" />}
            loading={busy('Verify')}
            onClick={() => set.mutate({ label: 'Verify', review: 'verified' })}
          >
            Verify
          </Button>
        ) : null}
        {d.review_status !== 'flagged' ? (
          <Button
            size="sm"
            icon={<Flag className="size-3.5" />}
            loading={busy('Flag')}
            onClick={() => set.mutate({ label: 'Flag', review: 'flagged' })}
          >
            Flag
          </Button>
        ) : null}
        {d.status !== 'published' ? (
          <Button
            size="sm"
            icon={<Send className="size-3.5" />}
            loading={busy('Publish')}
            onClick={() => set.mutate({ label: 'Publish', status: 'published' })}
          >
            Publish
          </Button>
        ) : null}
        {d.status !== 'archived' ? (
          <Button
            size="sm"
            icon={<Archive className="size-3.5" />}
            loading={busy('Archive')}
            onClick={() => set.mutate({ label: 'Archive', status: 'archived' })}
          >
            Archive
          </Button>
        ) : null}
        {d.status !== 'rejected' ? (
          <Button
            size="sm"
            variant="danger-ghost"
            icon={<XCircle className="size-3.5" />}
            loading={busy('Reject')}
            onClick={async () => {
              const ok = await confirm({
                title: 'Reject this question?',
                message: 'It leaves the bank and is excluded from practice and exams. You can publish it again later.',
                confirmLabel: 'Reject',
                tone: 'danger',
              });
              if (ok) set.mutate({ label: 'Reject', status: 'rejected' });
            }}
          >
            Reject
          </Button>
        ) : null}
      </div>

      <section aria-label="Question">
        <p className="text-base leading-relaxed whitespace-pre-wrap text-fg" lang={lang}>
          {d.stem}
        </p>
        <ol className="mt-3 space-y-1.5">
          {d.options.map((o, i) => (
            <li
              key={i}
              className={cx(
                'flex items-start gap-2.5 rounded-lg border px-3 py-2 text-sm',
                i === d.correct_index ? 'border-success/50 bg-success-soft' : 'border-line',
              )}
            >
              <span className={cx('mt-0.5 text-xs font-semibold', i === d.correct_index ? 'text-success' : 'text-muted')}>
                {LETTERS[i]}
              </span>
              <span className="min-w-0 flex-1" lang={lang}>
                {o}
              </span>
              {i === d.correct_index ? (
                <span className="flex items-center gap-1 text-xs font-medium text-success">
                  <CheckCircle2 className="size-3.5" aria-hidden /> correct
                </span>
              ) : null}
            </li>
          ))}
        </ol>
      </section>

      <Card title="Explanation">
        {d.explanation ? (
          <p className="text-sm whitespace-pre-wrap text-fg-2" lang={/[ঀ-৿]/.test(d.explanation) ? 'bn' : undefined}>
            {d.explanation}
          </p>
        ) : (
          <p className="text-sm text-muted">No explanation written.</p>
        )}
        {d.ai_explanation ? (
          <details className="mt-3 text-sm">
            <summary className="cursor-pointer text-muted hover:text-fg">AI explanation shown in the app</summary>
            <p className="mt-2 whitespace-pre-wrap text-fg-2" lang="bn">
              {d.ai_explanation}
            </p>
          </details>
        ) : null}
      </Card>

      <Card
        title={`Answers · ${answered ? `${fmtPercent(d.times_correct, d.times_answered)} correct of ${d.times_answered}` : 'not answered yet'}`}
      >
        {answered ? (
          <EmphasisBars
            ariaLabel="How learners answered"
            rows={d.options.map((o, i) => ({
              label: `${LETTERS[i]}. ${o}`,
              value: d.answer_stats.find((a) => a.selected_index === i)?.count ?? 0,
              emphasis: i === d.correct_index,
              note: i === d.correct_index ? '(correct)' : undefined,
            }))}
          />
        ) : (
          <p className="text-sm text-muted">No graded answers recorded yet.</p>
        )}
        {(d.answer_stats.find((a) => a.selected_index === null)?.count ?? 0) > 0 ? (
          <p className="mt-2 text-xs text-muted">{d.answer_stats.find((a) => a.selected_index === null)?.count} skipped in exams.</p>
        ) : null}
      </Card>

      <Card title="Details">
        <KeyValue
          items={[
            ['Subject', d.subject ? `${d.subject.name_en} · ${d.subject.name_bn}` : '—'],
            ['Topic', d.topic ? `${d.topic.name_en} · ${d.topic.name_bn}` : '—'],
            ['Difficulty', `${d.difficulty} / 5`],
            ['Language', d.language === 'bn' ? 'Bangla' : 'English'],
            ['Year', d.year ?? '—'],
            [
              'Source',
              d.source ? (
                <span>
                  {SOURCE_KINDS.find((k) => k.value === d.source?.kind)?.label} · <span lang="bn">{d.source.name}</span>
                </span>
              ) : (
                '—'
              ),
            ],
            ['Reference', d.source_ref ? <span lang="bn">{d.source_ref}</span> : '—'],
            [
              'Source link',
              d.source_url ? (
                <a
                  href={d.source_url}
                  target="_blank"
                  rel="noreferrer noopener"
                  className="inline-flex items-center gap-1 break-all text-info hover:underline"
                >
                  {d.source_url} <ExternalLink className="size-3" />
                </a>
              ) : (
                '—'
              ),
            ],
            ['Daily exams', d.daily_exam_dates.length ? d.daily_exam_dates.map(fmtDate).join(', ') : '—'],
            ['Created', `${fmtDateTime(d.created_at)}${d.created_by_user ? ` by @${d.created_by_user.username}` : ''}`],
            ['Embedding', d.has_embedding ? 'yes (used for semantic de-duplication)' : 'none'],
            ['Reports', `${d.reports.open} open · ${d.reports.total} total`],
          ]}
        />
      </Card>

      {d.fact ? (
        <Card title={`Built on fact #${d.fact.id}`}>
          <p className="text-sm text-fg-2" lang="bn">
            {d.fact.fact}
          </p>
          {d.fact.fact_en ? <p className="mt-1 text-sm text-muted">{d.fact.fact_en}</p> : null}
          <div className="mt-2 flex flex-wrap items-center gap-2 text-xs text-muted">
            <Badge tone={d.fact.status === 'active' ? 'success' : 'warning'}>{d.fact.status}</Badge>
            first seen {fmtDate(d.fact.first_seen_date)}
            {d.fact.superseded_by ? ` · superseded by #${d.fact.superseded_by}` : ''}
          </div>
          {d.fact.source_links.length ? (
            <ul className="mt-2 space-y-0.5 text-xs">
              {d.fact.source_links.slice(0, 5).map((l, i) =>
                l.url ? (
                  <li key={i}>
                    <a href={l.url} target="_blank" rel="noreferrer noopener" className="text-info hover:underline" lang="bn">
                      {l.source ? `${l.source}: ` : ''}
                      {l.title ?? l.url}
                    </a>
                  </li>
                ) : null,
              )}
            </ul>
          ) : null}
        </Card>
      ) : null}
    </div>
  );
}
