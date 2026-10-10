import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { CheckCircle2, EyeOff, Flag, MessageSquare, RotateCcw, ShieldX, User, X } from 'lucide-react';
import { useState } from 'react';
import { Link, useSearchParams } from 'react-router';
import { RoleBadge } from '../components/badges';
import { useConfirm, useToast } from '../components/feedback';
import { Modal } from '../components/Modal';
import {
  Avatar,
  Badge,
  Button,
  Card,
  cx,
  EmptyState,
  ErrorState,
  Field,
  LoadMore,
  PageHeader,
  Segmented,
  Spinner,
  Textarea,
} from '../components/ui';
import { fmtDateTime, fmtRelative } from '../lib/format';
import { usePageTitle } from '../lib/hooks';
import { useKeyset } from '../lib/keyset';
import { rpc } from '../lib/rpc';
import { publicStorageUrl } from '../lib/supabase';
import type { ReportRow, ReportTarget } from '../lib/types';

const PAGE = 30;
type Status = 'open' | 'actioned' | 'dismissed';

const REASON_TONE: Record<string, 'danger' | 'warning' | 'neutral' | 'info'> = {
  abuse: 'danger',
  nudity: 'danger',
  violence: 'danger',
  spam: 'warning',
  misinformation: 'warning',
  wrong_answer: 'info',
  other: 'neutral',
};

export default function ModerationPage() {
  usePageTitle('Moderation');
  const [params, setParams] = useSearchParams();
  const status = (params.get('status') as Status | null) ?? 'open';
  const [selected, setSelected] = useState<ReportRow | null>(null);

  const list = useKeyset<ReportRow, string>({
    key: ['reports', status],
    pageSize: PAGE,
    fetchPage: (before) => rpc<ReportRow[]>('admin_list_reports', { p_status: status, p_limit: PAGE, p_before: before }),
    cursorOf: (last) => last.created_at,
  });

  return (
    <div>
      <PageHeader
        title="Moderation"
        description="Reports from learners. Posts and comments hide automatically after 5 open reports; questions are flagged after 3."
        actions={
          <Segmented<Status>
            label="Report status"
            value={status}
            onChange={(v) => setParams(v === 'open' ? {} : { status: v }, { replace: true })}
            options={[
              { value: 'open', label: 'Open' },
              { value: 'actioned', label: 'Actioned' },
              { value: 'dismissed', label: 'Dismissed' },
            ]}
          />
        }
      />
      <Card pad={false}>
        {list.error ? <ErrorState error={list.error} onRetry={() => void list.refetch()} /> : null}
        {list.isLoading ? (
          <Spinner />
        ) : list.items.length === 0 && !list.error ? (
          <EmptyState
            title={status === 'open' ? 'The queue is empty' : `No ${status} reports`}
            icon={<CheckCircle2 className="size-8 text-success" />}
          >
            {status === 'open' ? 'Nothing needs your attention right now.' : null}
          </EmptyState>
        ) : (
          <ul className="divide-y divide-line">
            {list.items.map((r) => (
              <li key={r.id}>
                <button
                  type="button"
                  onClick={() => setSelected(r)}
                  className="flex w-full flex-col gap-1.5 px-4 py-3 text-left hover:bg-surface-2 sm:flex-row sm:items-start sm:gap-4"
                >
                  <div className="flex shrink-0 flex-wrap items-center gap-1.5 sm:w-44 sm:flex-col sm:items-start">
                    <Badge tone="neutral" icon={<TypeIcon type={r.target_type} />}>
                      {r.target_type}
                    </Badge>
                    <Badge tone={REASON_TONE[r.reason] ?? 'neutral'}>{r.reason.replace('_', ' ')}</Badge>
                  </div>
                  <div className="min-w-0 flex-1">
                    <p
                      className={cx('text-sm', r.preview ? 'text-fg' : 'text-muted italic')}
                      lang={/[ঀ-৿]/.test(r.preview ?? '') ? 'bn' : undefined}
                    >
                      {r.preview ?? 'No preview available (deleted or private content).'}
                    </p>
                    {r.details ? (
                      <p className="mt-1 text-xs text-fg-2" lang={/[ঀ-৿]/.test(r.details) ? 'bn' : undefined}>
                        “{r.details}”
                      </p>
                    ) : null}
                  </div>
                  <div className="shrink-0 text-xs text-muted sm:text-right">
                    <p>by @{r.reporter.username ?? 'unknown'}</p>
                    <p title={fmtDateTime(r.created_at)}>{fmtRelative(r.created_at)}</p>
                  </div>
                </button>
              </li>
            ))}
          </ul>
        )}
        <LoadMore
          hasMore={!!list.hasNextPage}
          loading={list.isFetchingNextPage}
          onClick={() => void list.fetchNextPage()}
          count={list.items.length}
        />
      </Card>
      <ReportDrawer report={selected} onClose={() => setSelected(null)} />
    </div>
  );
}

function TypeIcon({ type }: { type: string }) {
  if (type === 'user') return <User className="size-3" aria-hidden />;
  if (type === 'question') return <Flag className="size-3" aria-hidden />;
  return <MessageSquare className="size-3" aria-hidden />;
}

function ReportDrawer({ report, onClose }: { report: ReportRow | null; onClose: () => void }) {
  const qc = useQueryClient();
  const toast = useToast();
  const confirm = useConfirm();
  const [note, setNote] = useState('');
  const target = useQuery({
    queryKey: ['report-target', report?.target_type, report?.target_id],
    queryFn: () => rpc<ReportTarget>('admin_get_report_target', { p_target_type: report?.target_type, p_target_id: report?.target_id }),
    enabled: !!report,
  });
  const act = useMutation({
    mutationFn: (action: 'hide' | 'restore' | 'dismiss' | 'resolve') =>
      rpc<{ closed_reports: number }>('admin_moderate_report', { p_report: report?.id, p_action: action, p_note: note.trim() || null }),
    onSuccess: (res, action) => {
      toast.success(
        `${actionLabel(action, report?.target_type)}: ${res.closed_reports} report${res.closed_reports === 1 ? '' : 's'} closed.`,
      );
      setNote('');
      void qc.invalidateQueries({ queryKey: ['reports'] });
      void qc.invalidateQueries({ queryKey: ['report-target'] });
      void qc.invalidateQueries({ queryKey: ['dashboard'] });
      onClose();
    },
    onError: (e) => toast.error(e),
  });

  const t = target.data;
  const c = t?.content ?? null;
  const isOpen = report?.status === 'open';

  return (
    <Modal
      open={!!report}
      onClose={onClose}
      variant="drawer"
      title={report ? `Report #${report.id} · ${report.target_type}` : 'Report'}
      description={report ? `${report.reason.replace('_', ' ')} · ${fmtRelative(report.created_at)}` : undefined}
      footer={
        isOpen ? (
          <div className="flex w-full flex-col gap-3">
            <Field label="Note for the audit log (optional)" htmlFor="mod-note">
              <Textarea id="mod-note" rows={2} maxLength={500} value={note} onChange={(e) => setNote(e.target.value)} />
            </Field>
            <div className="flex flex-wrap justify-end gap-2">
              <Button
                variant="ghost"
                icon={<X className="size-4" />}
                loading={act.isPending && act.variables === 'dismiss'}
                onClick={() => act.mutate('dismiss')}
              >
                Dismiss
              </Button>
              <Button
                icon={<CheckCircle2 className="size-4" />}
                loading={act.isPending && act.variables === 'resolve'}
                onClick={() => act.mutate('resolve')}
              >
                Mark resolved
              </Button>
              {report?.target_type === 'post' || report?.target_type === 'comment' ? (
                c?.is_hidden ? (
                  <Button
                    icon={<RotateCcw className="size-4" />}
                    loading={act.isPending && act.variables === 'restore'}
                    onClick={() => act.mutate('restore')}
                  >
                    Restore content
                  </Button>
                ) : null
              ) : null}
              {report && report.target_type !== 'message' ? (
                <Button
                  variant="danger"
                  icon={report.target_type === 'user' ? <ShieldX className="size-4" /> : <EyeOff className="size-4" />}
                  loading={act.isPending && act.variables === 'hide'}
                  disabled={report.target_type === 'user' && t?.author?.role !== undefined && t.author.role !== 'user'}
                  onClick={async () => {
                    const ok = await confirm({
                      title: `${actionLabel('hide', report.target_type)}?`,
                      message:
                        report.target_type === 'user'
                          ? 'The account is marked banned and leaves broadcasts and suggestions. (Admins can also block sign-in from Users.)'
                          : report.target_type === 'question'
                            ? 'The question is rejected and leaves practice and exams.'
                            : 'The content is hidden from everyone except its author and staff.',
                      confirmLabel: actionLabel('hide', report.target_type),
                      tone: 'danger',
                    });
                    if (ok) act.mutate('hide');
                  }}
                >
                  {actionLabel('hide', report.target_type)}
                </Button>
              ) : null}
            </div>
          </div>
        ) : null
      }
    >
      {target.error ? <ErrorState error={target.error} onRetry={() => void target.refetch()} /> : null}
      {!t ? (
        target.isLoading ? (
          <Spinner />
        ) : null
      ) : (
        <div className="space-y-5">
          {t.author ? (
            <div className="flex items-center gap-3">
              <Avatar name={t.author.full_name || t.author.username || '?'} url={t.author.avatar_url} size={40} />
              <div className="min-w-0">
                <p className="font-medium text-fg" lang="bn">
                  {t.author.full_name || '—'}
                </p>
                <p className="text-sm text-muted">@{t.author.username ?? '—'}</p>
              </div>
              <div className="ml-auto flex gap-1">
                <RoleBadge role={t.author.role} />
                {t.author.is_banned ? <Badge tone="danger">banned</Badge> : null}
              </div>
            </div>
          ) : null}
          <Card title="Reported content">
            {c ? <TargetContent type={t.target_type} c={c} /> : <p className="text-sm text-muted">The content no longer exists.</p>}
          </Card>
          <Card title={`All reports on this ${t.target_type} (${t.reports.length})`} pad={false}>
            <ul className="divide-y divide-line">
              {t.reports.map((r) => (
                <li key={r.id} className="px-4 py-2.5 text-sm">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <span className="flex items-center gap-1.5">
                      <Badge tone={REASON_TONE[r.reason] ?? 'neutral'}>{r.reason.replace('_', ' ')}</Badge>
                      <Badge tone={r.status === 'open' ? 'warning' : 'neutral'}>{r.status}</Badge>
                    </span>
                    <span className="text-xs text-muted">
                      @{r.reporter.username ?? '—'} · {fmtRelative(r.created_at)}
                    </span>
                  </div>
                  {r.details ? (
                    <p className="mt-1 text-fg-2" lang={/[ঀ-৿]/.test(r.details) ? 'bn' : undefined}>
                      “{r.details}”
                    </p>
                  ) : null}
                </li>
              ))}
            </ul>
          </Card>
        </div>
      )}
    </Modal>
  );
}

function actionLabel(action: string, type: string | undefined): string {
  if (action === 'hide') return type === 'user' ? 'Ban user' : type === 'question' ? 'Reject question' : 'Hide content';
  if (action === 'restore') return 'Restored';
  if (action === 'dismiss') return 'Dismissed';
  return 'Resolved';
}

function str(v: unknown): string {
  return typeof v === 'string' ? v : v === null || v === undefined ? '' : String(v);
}

function TargetContent({ type, c }: { type: string; c: Record<string, unknown> }) {
  const bn = (s: string) => (/[ঀ-৿]/.test(s) ? 'bn' : undefined);
  if (type === 'post') {
    const images = Array.isArray(c.image_paths) ? (c.image_paths as string[]) : [];
    const body = str(c.body);
    return (
      <div className="space-y-3">
        <div className="flex flex-wrap gap-1.5">
          {c.is_hidden ? <Badge tone="danger">hidden</Badge> : <Badge tone="success">visible</Badge>}
          <Badge>{str(c.visibility)}</Badge>
          <Badge>{str(c.kind)}</Badge>
          <Badge>{str(c.report_count)} reports</Badge>
        </div>
        {body ? (
          <p className="text-sm whitespace-pre-wrap text-fg" lang={bn(body)}>
            {body}
          </p>
        ) : (
          <p className="text-sm text-muted">No text.</p>
        )}
        {images.length ? (
          <div className="grid grid-cols-2 gap-2">
            {images.map((p) => (
              <a key={p} href={publicStorageUrl('post-media', p)} target="_blank" rel="noreferrer noopener">
                <img
                  src={publicStorageUrl('post-media', p)}
                  alt="Post attachment"
                  loading="lazy"
                  className="aspect-square w-full rounded-lg border border-line object-cover"
                />
              </a>
            ))}
          </div>
        ) : null}
        <p className="text-xs text-muted">Posted {fmtDateTime(str(c.created_at))}</p>
      </div>
    );
  }
  if (type === 'comment') {
    const body = str(c.body);
    return (
      <div className="space-y-2 text-sm">
        {c.is_hidden ? <Badge tone="danger">hidden</Badge> : <Badge tone="success">visible</Badge>}
        <p className="whitespace-pre-wrap text-fg" lang={bn(body)}>
          {body}
        </p>
        {c.post_excerpt ? (
          <p className="rounded-lg bg-surface-2 p-2 text-xs text-muted" lang={bn(str(c.post_excerpt))}>
            On post: {str(c.post_excerpt)}
          </p>
        ) : null}
      </div>
    );
  }
  if (type === 'message') {
    const body = str(c.body);
    return (
      <div className="space-y-2 text-sm">
        {c.deleted ? <Badge>deleted by sender</Badge> : null}
        <p className="whitespace-pre-wrap text-fg" lang={bn(body)}>
          {body || (c.kind === 'image' ? '[image]' : '—')}
        </p>
        <p className="text-xs text-muted">Private message · shown to staff only because it was reported.</p>
      </div>
    );
  }
  if (type === 'question') {
    const options = Array.isArray(c.options) ? (c.options as string[]) : [];
    return (
      <div className="space-y-2 text-sm">
        <p className="text-fg" lang={bn(str(c.stem))}>
          {str(c.stem)}
        </p>
        <ol className="space-y-1">
          {options.map((o, i) => (
            <li
              key={i}
              className={cx('rounded-md px-2 py-1', i === c.correct_index ? 'bg-success-soft text-success' : 'text-fg-2')}
              lang={bn(o)}
            >
              {String.fromCharCode(65 + i)}. {o} {i === c.correct_index ? '✓' : ''}
            </li>
          ))}
        </ol>
        {c.explanation ? (
          <p className="text-xs text-muted" lang={bn(str(c.explanation))}>
            {str(c.explanation)}
          </p>
        ) : null}
        <p className="text-xs text-muted">
          Status {str(c.status)} · review {str(c.review_status)} ·{' '}
          <Link className="text-info hover:underline" to={`/questions?id=${str(c.id)}`}>
            open in Questions
          </Link>
        </p>
      </div>
    );
  }
  return (
    <div className="space-y-1 text-sm">
      <p className="text-fg" lang="bn">
        {str(c.full_name)} <span className="text-muted">@{str(c.username)}</span>
      </p>
      {c.bio ? (
        <p className="text-fg-2" lang={bn(str(c.bio))}>
          {str(c.bio)}
        </p>
      ) : null}
      <p className="text-xs text-muted">
        {str(c.posts_count)} posts · joined {fmtDateTime(str(c.created_at))}
      </p>
    </div>
  );
}
