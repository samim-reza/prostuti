import { useMutation, useQuery } from '@tanstack/react-query';
import { CheckCircle2, Clock, Loader2, Play, XCircle } from 'lucide-react';
import { useState } from 'react';
import { useConfirm, useToast } from '../../components/feedback';
import { Badge, Button, Card, Notice, PageHeader, TabLinks } from '../../components/ui';
import { fmtDateTime, fmtRelative } from '../../lib/format';
import { usePageTitle } from '../../lib/hooks';
import { rpc } from '../../lib/rpc';
import type { ConsoleStats } from '../../lib/types';
import { CA_TABS } from './tabs';

type Stage = 'ingest-news' | 'generate-daily-notes' | 'generate-daily-exam' | 'dispatch-notifications';

const STAGES: { stage: Stage; title: string; when: string; job: string; what: string; cost: boolean }[] = [
  {
    stage: 'ingest-news',
    title: 'Ingest news',
    when: 'every 3 hours',
    job: 'prostuti-ingest-news',
    what: 'Pulls every enabled RSS feed into news_articles (titles and summaries only).',
    cost: false,
  },
  {
    stage: 'generate-daily-notes',
    title: 'Generate daily notes',
    when: '05:20 and 15:30 BD',
    job: 'prostuti-notes-morning',
    what: 'Clusters articles, extracts facts, reconciles them with the fact store and writes bilingual notes. Uses the LLM (costs money).',
    cost: true,
  },
  {
    stage: 'generate-daily-exam',
    title: 'Generate daily exam',
    when: '05:50 BD',
    job: 'prostuti-daily-exam',
    what: "Builds today's exam from today's facts (falls back to the last 3 days). Uses the LLM.",
    cost: true,
  },
  {
    stage: 'dispatch-notifications',
    title: 'Dispatch notifications',
    when: 'every 15 min',
    job: 'prostuti-dispatch',
    what: 'Morning routine, reminders and the push outbox. Idempotent per day.',
    cost: false,
  },
];

interface RunResult {
  request_id: number | null;
  configured: boolean;
}
interface HttpResult {
  pending?: boolean;
  available?: boolean;
  status_code?: number | null;
  content?: string | null;
  error?: string | null;
  timed_out?: boolean | null;
  created?: string;
}

export default function PipelinePage() {
  usePageTitle('Pipeline');
  const stats = useQuery({ queryKey: ['dashboard'], queryFn: () => rpc<ConsoleStats>('admin_console_stats'), staleTime: 30_000 });
  return (
    <div>
      <PageHeader
        title="Current affairs"
        description="Run a pipeline stage by hand. Stages normally run on schedule (pg_cron → Edge Functions)."
      />
      <TabLinks tabs={CA_TABS} />
      <Notice tone="warning">
        Runs are asynchronous, limited to 3 per stage per 10 minutes, and recorded in the audit log. Notes and exams are idempotent per day,
        so a second run tops up instead of duplicating.
      </Notice>
      <div className="mt-5 grid gap-4 md:grid-cols-2">
        {STAGES.map((s) => (
          <StageCard key={s.stage} {...s} lastRun={stats.data?.pipeline.cron.find((c) => c.job === s.job)} />
        ))}
      </div>
    </div>
  );
}

function StageCard({
  stage,
  title,
  when,
  what,
  cost,
  lastRun,
}: (typeof STAGES)[number] & { lastRun?: ConsoleStats['pipeline']['cron'][number] }) {
  const toast = useToast();
  const confirm = useConfirm();
  const [requestId, setRequestId] = useState<number | null>(null);
  const [startedAt, setStartedAt] = useState<number>(0);
  const run = useMutation({
    mutationFn: () => rpc<RunResult>('admin_trigger_pipeline', { p_stage: stage }),
    onSuccess: (r) => {
      if (!r.configured || r.request_id === null) {
        toast.error('The Edge Function secrets (project_url / cron_secret) are not configured in Vault, so nothing was sent.');
        return;
      }
      setRequestId(r.request_id);
      setStartedAt(Date.now());
      toast.info(`${title} started.`);
    },
    onError: (e) => toast.error(e),
  });
  const result = useQuery({
    queryKey: ['pipeline-result', requestId],
    queryFn: () => rpc<HttpResult>('admin_pipeline_result', { p_request_id: requestId }),
    enabled: requestId !== null,
    refetchInterval: (q) => (q.state.data?.pending && Date.now() - startedAt < 180_000 ? 3000 : false),
  });
  const r = result.data;

  return (
    <Card title={title} actions={<Badge icon={<Clock className="size-3" />}>{when}</Badge>}>
      <p className="text-sm text-fg-2">{what}</p>
      <p className="mt-2 text-xs text-muted">
        Last scheduled run:{' '}
        {lastRun?.started_at ? (
          <>
            {fmtRelative(lastRun.started_at)} · {lastRun.status ?? 'unknown'}
          </>
        ) : (
          'none in the last 3 days'
        )}
      </p>
      <div className="mt-4 flex flex-wrap items-center gap-3">
        <Button
          variant="primary"
          size="sm"
          icon={<Play className="size-3.5" />}
          loading={run.isPending}
          onClick={async () => {
            const ok = await confirm({
              title: `Run "${title}" now?`,
              message: cost
                ? 'This stage calls the LLM and costs money. It is safe to re-run (idempotent per day).'
                : 'This stage is cheap and idempotent.',
              confirmLabel: 'Run now',
            });
            if (ok) run.mutate();
          }}
        >
          Run now
        </Button>
        {requestId !== null ? (
          r?.pending || (!r && result.isFetching) ? (
            <span className="flex items-center gap-1.5 text-sm text-muted">
              <Loader2 className="size-4 animate-spin" aria-hidden /> Running (request #{requestId})…
            </span>
          ) : r?.available === false ? (
            <span className="text-sm text-muted">Request #{requestId} sent. Result tracking is unavailable.</span>
          ) : r ? (
            <span className={`flex items-center gap-1.5 text-sm ${r.status_code && r.status_code < 300 ? 'text-success' : 'text-danger'}`}>
              {r.status_code && r.status_code < 300 ? (
                <CheckCircle2 className="size-4" aria-hidden />
              ) : (
                <XCircle className="size-4" aria-hidden />
              )}
              {r.timed_out ? 'Timed out' : `HTTP ${r.status_code ?? '—'}`} · {fmtDateTime(r.created)}
            </span>
          ) : null
        ) : null}
      </div>
      {r && !r.pending && (r.content || r.error) ? (
        <pre className="mt-3 max-h-48 overflow-auto rounded-lg bg-surface-2 p-2 text-xs whitespace-pre-wrap text-fg-2">
          {r.error ?? r.content}
        </pre>
      ) : null}
      {r?.pending && Date.now() - startedAt >= 180_000 ? (
        <p className="mt-2 text-xs text-muted">Still running after 3 minutes; check the dashboard later.</p>
      ) : null}
    </Card>
  );
}
