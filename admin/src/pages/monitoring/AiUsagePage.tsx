import { useQuery } from '@tanstack/react-query';
import { AlertTriangle } from 'lucide-react';
import { useState } from 'react';
import { Link } from 'react-router';
import { ColumnChart } from '../../components/charts';
import {
  Badge,
  Card,
  EmptyState,
  ErrorState,
  LoadMore,
  Notice,
  PageHeader,
  Segmented,
  Spinner,
  Stat,
  TableWrap,
} from '../../components/ui';
import { toApiError } from '../../lib/errors';
import { fmtBdt, fmtCompact, fmtDateTime, fmtNumber, fmtShortDay, fmtUsd } from '../../lib/format';
import { usePageTitle } from '../../lib/hooks';
import { useKeyset } from '../../lib/keyset';
import { rpc } from '../../lib/rpc';
import { supabase } from '../../lib/supabase';
import type { AiUsageRow, AiUsageSummary } from '../../lib/types';

type Range = '7' | '30' | '90';
const LOG_PAGE = 50;

export default function AiUsagePage() {
  usePageTitle('AI usage');
  const [days, setDays] = useState<Range>('7');
  const summary = useQuery({
    queryKey: ['ai-usage', days],
    queryFn: () => rpc<AiUsageSummary>('admin_ai_usage_summary', { p_days: Number(days) }),
    placeholderData: (prev) => prev,
  });
  const log = useKeyset<AiUsageRow, number>({
    key: ['ai-usage-log'],
    pageSize: LOG_PAGE,
    fetchPage: async (before) => {
      let query = supabase
        .from('ai_usage_log')
        .select('id, user_id, function_name, model, prompt_tokens, completion_tokens, cache, latency_ms, created_at')
        .order('id', { ascending: false })
        .limit(LOG_PAGE);
      if (before) query = query.lt('id', before);
      const { data, error } = await query;
      if (error) throw toApiError(error);
      return (data ?? []) as AiUsageRow[];
    },
    cursorOf: (last) => last.id,
  });

  const s = summary.data;
  const totals = s
    ? s.by_day.reduce(
        (acc, d) => ({
          calls: acc.calls + d.calls,
          hits: acc.hits + d.cache_hits,
          tokens: acc.tokens + d.prompt_tokens + d.completion_tokens,
          cost: acc.cost + Number(d.cost_usd),
        }),
        { calls: 0, hits: 0, tokens: 0, cost: 0 },
      )
    : null;
  const rate = s?.pricing.usd_to_bdt;

  return (
    <div>
      <PageHeader
        title="AI usage"
        description="Every LLM and embedding call made by the Edge Functions, with cache hits. Costs are estimates from the ai_pricing config."
        actions={
          <Segmented<Range>
            label="Range"
            value={days}
            onChange={setDays}
            options={[
              { value: '7', label: '7 days' },
              { value: '30', label: '30 days' },
              { value: '90', label: '90 days' },
            ]}
          />
        }
      />
      {summary.error ? <ErrorState error={summary.error} onRetry={() => void summary.refetch()} /> : null}
      {!s ? (
        summary.isLoading ? (
          <Spinner />
        ) : null
      ) : (
        <div className={summary.isFetching ? 'space-y-5 opacity-80' : 'space-y-5'}>
          {s.unpriced_models.length ? (
            <Notice tone="warning" icon={<AlertTriangle className="size-4" />}>
              No price for {s.unpriced_models.join(', ')}; their cost counts as $0. Add them to{' '}
              <Link className="underline" to="/config">
                ai_pricing
              </Link>
              .
            </Notice>
          ) : null}
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <Stat
              label="Estimated cost"
              value={fmtUsd(totals?.cost ?? 0)}
              sub={rate ? `≈ ${fmtBdt((totals?.cost ?? 0) * rate)}` : undefined}
            />
            <Stat label="Calls" value={totals?.calls ?? 0} />
            <Stat
              label="Cache hits"
              value={totals?.hits ?? 0}
              sub={totals?.calls ? `${Math.round((totals.hits / totals.calls) * 100)}% of calls` : undefined}
            />
            <Stat label="Tokens" value={fmtCompact(totals?.tokens ?? 0)} />
          </div>
          <Card title={`Cost per day · last ${days} days`}>
            <ColumnChart
              title="Estimated cost (USD)"
              data={s.by_day.map((d) => ({ label: d.day, value: Number(d.cost_usd) }))}
              format={(v) => fmtUsd(v)}
              labelFormat={fmtShortDay}
              height={180}
            />
          </Card>
          <Card title="By function and model" pad={false}>
            {s.by_function.length === 0 ? (
              <EmptyState title="No AI calls in this range" />
            ) : (
              <TableWrap>
                <table className="table-base">
                  <thead>
                    <tr>
                      <th scope="col">Function</th>
                      <th scope="col">Model</th>
                      <th scope="col" className="text-right">
                        Calls
                      </th>
                      <th scope="col" className="text-right">
                        Cache hits
                      </th>
                      <th scope="col" className="text-right">
                        Prompt tokens
                      </th>
                      <th scope="col" className="text-right">
                        Completion tokens
                      </th>
                      <th scope="col" className="text-right">
                        Avg latency
                      </th>
                      <th scope="col" className="text-right">
                        Cost
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    {s.by_function.map((f) => (
                      <tr key={`${f.function_name}|${f.model}`}>
                        <td className="font-medium">{f.function_name}</td>
                        <td className="text-sm text-fg-2">{f.model ?? '—'}</td>
                        <td className="num text-right">{fmtNumber(f.calls)}</td>
                        <td className="num text-right">{fmtNumber(f.cache_hits)}</td>
                        <td className="num text-right">{fmtNumber(f.prompt_tokens)}</td>
                        <td className="num text-right">{fmtNumber(f.completion_tokens)}</td>
                        <td className="num text-right">{f.avg_latency_ms !== null ? `${fmtNumber(f.avg_latency_ms)} ms` : '—'}</td>
                        <td className="num text-right font-medium">{fmtUsd(f.cost_usd)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </TableWrap>
            )}
          </Card>
        </div>
      )}

      <Card title="Recent calls" pad={false} className="mt-5">
        {log.error ? <ErrorState error={log.error} onRetry={() => void log.refetch()} /> : null}
        {log.isLoading ? (
          <Spinner />
        ) : (
          <TableWrap>
            <table className="table-base">
              <thead>
                <tr>
                  <th scope="col">Time</th>
                  <th scope="col">Function</th>
                  <th scope="col">Model</th>
                  <th scope="col" className="text-right">
                    Tokens in / out
                  </th>
                  <th scope="col">Cache</th>
                  <th scope="col" className="text-right">
                    Latency
                  </th>
                </tr>
              </thead>
              <tbody>
                {log.items.map((r) => (
                  <tr key={r.id}>
                    <td className="text-sm whitespace-nowrap">{fmtDateTime(r.created_at)}</td>
                    <td className="text-sm">{r.function_name}</td>
                    <td className="text-sm text-fg-2">{r.model ?? '—'}</td>
                    <td className="num text-right text-sm">
                      {fmtNumber(r.prompt_tokens ?? 0)} / {fmtNumber(r.completion_tokens ?? 0)}
                    </td>
                    <td>{r.cache ? <Badge tone="success">{r.cache}</Badge> : <span className="text-xs text-muted">miss</span>}</td>
                    <td className="num text-right text-sm">{r.latency_ms !== null ? `${fmtNumber(r.latency_ms)} ms` : '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TableWrap>
        )}
        <LoadMore
          hasMore={!!log.hasNextPage}
          loading={log.isFetchingNextPage}
          onClick={() => void log.fetchNextPage()}
          count={log.items.length}
        />
      </Card>
    </div>
  );
}
