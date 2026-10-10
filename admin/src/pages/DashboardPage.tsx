import { useQuery } from '@tanstack/react-query';
import {
  Activity,
  AlertTriangle,
  Bot,
  CheckCircle2,
  CircleDashed,
  ClipboardCheck,
  FileQuestion,
  Flag,
  Newspaper,
  RefreshCw,
  UserPlus,
  Users,
  XCircle,
} from 'lucide-react';
import { Link } from 'react-router';
import { ColumnChart } from '../components/charts';
import { Badge, Button, Card, ErrorState, PageHeader, Skeleton, Stat, TableWrap } from '../components/ui';
import { fmtBdt, fmtDate, fmtDateTime, fmtNumber, fmtRelative, fmtShortDay, fmtUsd } from '../lib/format';
import { usePageTitle } from '../lib/hooks';
import { rpc } from '../lib/rpc';
import type { ConsoleStats } from '../lib/types';

const STATUS_ORDER = ['published', 'draft', 'archived', 'rejected'] as const;
const REVIEW_ORDER = ['unverified', 'verified', 'flagged'] as const;

export default function DashboardPage() {
  usePageTitle('Dashboard');
  const q = useQuery({
    queryKey: ['dashboard'],
    queryFn: () => rpc<ConsoleStats>('admin_console_stats'),
    refetchInterval: 60_000,
  });

  const s = q.data;
  return (
    <div className={q.isFetching && s ? 'opacity-80 transition-opacity' : undefined}>
      <PageHeader
        title="Dashboard"
        description={
          s ? `Bangladesh date ${fmtDate(s.bd_today)} · updated ${fmtRelative(s.generated_at)}` : 'Live numbers from the database.'
        }
        actions={
          <Button size="sm" icon={<RefreshCw className="size-3.5" />} loading={q.isFetching} onClick={() => void q.refetch()}>
            Refresh
          </Button>
        }
      />
      {q.error ? <ErrorState error={q.error} onRetry={() => void q.refetch()} /> : null}
      {!s ? (
        q.isLoading ? (
          <DashboardSkeleton />
        ) : null
      ) : (
        <div className="space-y-5">
          <section aria-label="Key numbers" className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
            <Stat
              label="Users"
              value={s.users.total}
              icon={<Users className="size-4" />}
              sub={`${fmtNumber(s.users.staff)} staff · ${fmtNumber(s.users.banned)} banned`}
            />
            <Stat
              label="New (7 days)"
              value={s.users.new_7d}
              icon={<UserPlus className="size-4" />}
              sub={`${fmtNumber(s.users.new_today)} today`}
            />
            <Stat
              label="Active today"
              value={s.users.active_today}
              icon={<Activity className="size-4" />}
              sub={`${fmtNumber(s.users.active_7d)} in 7 days`}
            />
            <Stat
              label="Exams submitted today"
              value={s.exams_today.submitted}
              icon={<ClipboardCheck className="size-4" />}
              sub={
                Object.entries(s.exams_today.by_kind)
                  .map(([k, n]) => `${k.replace('_', ' ')} ${n}`)
                  .join(' · ') || 'none yet'
              }
            />
            <Stat
              label="Open reports"
              value={s.reports.open}
              tone={s.reports.open > 0 ? 'warning' : undefined}
              icon={<Flag className="size-4" />}
              sub={
                <Link className="underline-offset-2 hover:underline" to="/moderation">
                  Review queue →
                </Link>
              }
            />
            <Stat
              label="AI cost (7 days)"
              value={fmtUsd(s.ai_7d.cost_usd)}
              icon={<Bot className="size-4" />}
              sub={`${fmtNumber(s.ai_7d.calls)} calls${s.ai_7d.usd_to_bdt ? ` · ≈ ${fmtBdt(s.ai_7d.cost_usd * s.ai_7d.usd_to_bdt)}` : ''}`}
            />
          </section>

          <div className="grid gap-5 xl:grid-cols-3">
            <Card title="Last 14 days" className="xl:col-span-2">
              <div className="grid gap-6 md:grid-cols-3">
                <ColumnChart
                  title="Sign-ups per day"
                  data={s.series.map((d) => ({ label: d.day, value: d.signups }))}
                  format={fmtNumber}
                  labelFormat={fmtShortDay}
                />
                <ColumnChart
                  title="Exams submitted per day"
                  data={s.series.map((d) => ({ label: d.day, value: d.exams }))}
                  format={fmtNumber}
                  labelFormat={fmtShortDay}
                />
                <ColumnChart
                  title="AI cost per day (USD)"
                  data={s.series.map((d) => ({ label: d.day, value: Number(d.ai_cost_usd) }))}
                  format={(v) => fmtUsd(v)}
                  labelFormat={fmtShortDay}
                />
              </div>
            </Card>
            <TodayCard s={s} />
          </div>

          <div className="grid gap-5 xl:grid-cols-3">
            <QuestionsCard s={s} />
            <Card
              title="Client errors (24 h)"
              actions={
                <Link to="/monitoring/errors" className="text-xs text-muted hover:text-fg">
                  Open →
                </Link>
              }
            >
              {s.client_errors_24h ? (
                <div className="grid grid-cols-2 gap-3 text-sm">
                  <Metric label="Events" value={s.client_errors_24h.events} tone={s.client_errors_24h.events > 0 ? 'warning' : undefined} />
                  <Metric label="Distinct errors" value={s.client_errors_24h.groups} />
                  <Metric label="Fatal" value={s.client_errors_24h.fatal} tone={s.client_errors_24h.fatal > 0 ? 'danger' : undefined} />
                  <Metric label="Users affected" value={s.client_errors_24h.users} />
                </div>
              ) : (
                <p className="text-sm text-muted">Crash reporting is not installed on this database yet.</p>
              )}
            </Card>
            <Card
              title="Pipeline health"
              actions={
                <Link to="/current-affairs/pipeline" className="text-xs text-muted hover:text-fg">
                  Run stages →
                </Link>
              }
            >
              <div className="grid grid-cols-2 gap-3 text-sm">
                <Metric
                  label="News feeds"
                  value={`${s.pipeline.news_sources.enabled}/${s.pipeline.news_sources.total}`}
                  sub={s.pipeline.news_sources.failing ? `${s.pipeline.news_sources.failing} failing` : 'all healthy'}
                  tone={s.pipeline.news_sources.failing ? 'warning' : undefined}
                />
                <Metric label="Last fetch" value={fmtRelative(s.pipeline.news_sources.last_fetched_at)} />
                <Metric label="Unprocessed articles" value={s.pipeline.unprocessed_articles} />
                <Metric label="Pending re-plans" value={s.pipeline.pending_replans} />
                <Metric label="Pending pushes" value={s.pipeline.pending_push} />
                <Metric
                  label="AI cache hits (7 d)"
                  value={s.ai_7d.calls ? `${Math.round((s.ai_7d.cache_hits / s.ai_7d.calls) * 100)}%` : '—'}
                />
              </div>
            </Card>
          </div>

          <Card title="Scheduled jobs (last run)" pad={false}>
            <TableWrap>
              <table className="table-base">
                <thead>
                  <tr>
                    <th scope="col">Job</th>
                    <th scope="col">Schedule (UTC)</th>
                    <th scope="col">Last run</th>
                    <th scope="col">Status</th>
                    <th scope="col">Message</th>
                  </tr>
                </thead>
                <tbody>
                  {s.pipeline.cron.length === 0 ? (
                    <tr>
                      <td colSpan={5} className="text-muted">
                        No cron jobs visible.
                      </td>
                    </tr>
                  ) : (
                    s.pipeline.cron.map((j) => (
                      <tr key={j.job}>
                        <td className="font-medium whitespace-nowrap">{j.job.replace(/^prostuti-/, '')}</td>
                        <td className="font-mono text-xs whitespace-nowrap text-muted">{j.schedule}</td>
                        <td className="whitespace-nowrap" title={fmtDateTime(j.started_at)}>
                          {fmtRelative(j.started_at)}
                        </td>
                        <td>
                          {!j.active ? (
                            <Badge>paused</Badge>
                          ) : j.status === 'succeeded' ? (
                            <Badge tone="success" icon={<CheckCircle2 className="size-3" />}>
                              succeeded
                            </Badge>
                          ) : j.status === 'failed' ? (
                            <Badge tone="danger" icon={<XCircle className="size-3" />}>
                              failed
                            </Badge>
                          ) : j.status ? (
                            <Badge tone="info" icon={<CircleDashed className="size-3" />}>
                              {j.status}
                            </Badge>
                          ) : (
                            <Badge>no runs (3 d)</Badge>
                          )}
                        </td>
                        <td className="max-w-md truncate text-xs text-muted" title={j.message ?? ''}>
                          {j.message ?? ''}
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </TableWrap>
          </Card>
        </div>
      )}
    </div>
  );
}

function Metric({ label, value, sub, tone }: { label: string; value: number | string; sub?: string; tone?: 'warning' | 'danger' }) {
  return (
    <div className="rounded-lg bg-surface-2 px-3 py-2">
      <p className="text-xs text-muted">{label}</p>
      <p
        className={
          tone === 'danger' ? 'font-semibold text-danger' : tone === 'warning' ? 'font-semibold text-warning' : 'font-semibold text-fg'
        }
      >
        {typeof value === 'number' ? fmtNumber(value) : value}
      </p>
      {sub ? <p className="text-xs text-muted">{sub}</p> : null}
    </div>
  );
}

function TodayCard({ s }: { s: ConsoleStats }) {
  const notes = s.today.notes;
  const exam = s.today.daily_exam;
  return (
    <Card
      title={`Today · ${fmtDate(s.bd_today)}`}
      actions={
        <Link to="/current-affairs" className="text-xs text-muted hover:text-fg">
          Current affairs →
        </Link>
      }
    >
      <ul className="space-y-3 text-sm">
        <li className="flex items-start gap-3">
          <Newspaper className="mt-0.5 size-4 shrink-0 text-muted" aria-hidden />
          <div className="min-w-0 flex-1">
            <p className="font-medium text-fg">Daily notes</p>
            {notes.published > 0 ? (
              <p className="text-muted">
                {notes.published} published
                {notes.draft ? ` · ${notes.draft} draft` : ''}
                {notes.archived ? ` · ${notes.archived} archived` : ''}
              </p>
            ) : (
              <p className="flex items-center gap-1.5 text-warning">
                <AlertTriangle className="size-3.5" /> No notes published yet
              </p>
            )}
            {notes.missing_en > 0 ? <p className="text-xs text-warning">{notes.missing_en} without English text</p> : null}
          </div>
        </li>
        <li className="flex items-start gap-3">
          <ClipboardCheck className="mt-0.5 size-4 shrink-0 text-muted" aria-hidden />
          <div className="min-w-0 flex-1">
            <p className="font-medium text-fg">Daily exam</p>
            {exam ? (
              <p className="text-muted">
                <Badge tone={exam.status === 'published' ? 'success' : 'neutral'}>{exam.status}</Badge> {exam.question_count} questions ·{' '}
                {fmtNumber(exam.submissions)} submissions
              </p>
            ) : (
              <p className="flex items-center gap-1.5 text-warning">
                <AlertTriangle className="size-3.5" /> Not generated yet
              </p>
            )}
          </div>
        </li>
        <li className="flex items-start gap-3">
          <FileQuestion className="mt-0.5 size-4 shrink-0 text-muted" aria-hidden />
          <div className="min-w-0 flex-1">
            <p className="font-medium text-fg">Recent pipeline runs</p>
            {s.pipeline.recent_runs.length ? (
              <ul className="mt-1 space-y-0.5 text-xs text-muted">
                {s.pipeline.recent_runs.slice(0, 5).map((r) => (
                  <li key={r.key} className="flex justify-between gap-2">
                    <span className="truncate font-mono">{r.key}</span>
                    <span className="shrink-0">{fmtRelative(r.created_at)}</span>
                  </li>
                ))}
              </ul>
            ) : (
              <p className="text-muted">None recorded.</p>
            )}
          </div>
        </li>
      </ul>
    </Card>
  );
}

function QuestionsCard({ s }: { s: ConsoleStats }) {
  const cell = (status: string, review: string) => s.questions.find((x) => x.status === status && x.review_status === review)?.count ?? 0;
  const total = s.questions.reduce((a, b) => a + b.count, 0);
  return (
    <Card
      title={`Question bank · ${fmtNumber(total)}`}
      pad={false}
      actions={
        <Link to="/questions" className="text-xs text-muted hover:text-fg">
          Open →
        </Link>
      }
    >
      <TableWrap>
        <table className="table-base">
          <thead>
            <tr>
              <th scope="col">Status</th>
              {REVIEW_ORDER.map((r) => (
                <th key={r} scope="col" className="text-right">
                  {r}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {STATUS_ORDER.map((st) => (
              <tr key={st}>
                <th scope="row">{st}</th>
                {REVIEW_ORDER.map((r) => {
                  const n = cell(st, r);
                  return (
                    <td key={r} className="num text-right">
                      {n ? (
                        <Link className="hover:underline" to={`/questions?status=${st}&review=${r}`}>
                          {fmtNumber(n)}
                        </Link>
                      ) : (
                        <span className="text-muted">0</span>
                      )}
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </TableWrap>
    </Card>
  );
}

function DashboardSkeleton() {
  return (
    <div className="space-y-5" aria-busy>
      <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
        {Array.from({ length: 6 }, (_, i) => (
          <Skeleton key={i} className="h-24" />
        ))}
      </div>
      <div className="grid gap-5 xl:grid-cols-3">
        <Skeleton className="h-64 xl:col-span-2" />
        <Skeleton className="h-64" />
      </div>
    </div>
  );
}
