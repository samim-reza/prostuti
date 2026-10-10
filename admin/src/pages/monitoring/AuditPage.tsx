import { ChevronDown } from 'lucide-react';
import { useState } from 'react';
import { Badge, Card, cx, EmptyState, ErrorState, LoadMore, PageHeader, Select, Spinner } from '../../components/ui';
import { toApiError } from '../../lib/errors';
import { fmtDateTime, fmtRelative } from '../../lib/format';
import { usePageTitle } from '../../lib/hooks';
import { useKeyset } from '../../lib/keyset';
import { supabase } from '../../lib/supabase';
import type { AuditRow } from '../../lib/types';

const PAGE = 50;
const AREAS = [
  { value: '', label: 'All actions' },
  { value: 'user.', label: 'Users' },
  { value: 'question.', label: 'Questions' },
  { value: 'report.', label: 'Moderation' },
  { value: 'note.', label: 'Daily notes' },
  { value: 'news_source.', label: 'News sources' },
  { value: 'pipeline.', label: 'Pipeline' },
  { value: 'schedule.', label: 'Schedules' },
  { value: 'track.', label: 'Exam tracks' },
  { value: 'addon.', label: 'Add-ons' },
  { value: 'feature.', label: 'Features' },
  { value: 'promo.', label: 'Promo codes' },
  { value: 'config.', label: 'App config' },
  { value: 'broadcast.', label: 'Broadcasts' },
];

export default function AuditPage() {
  usePageTitle('Audit log');
  const [area, setArea] = useState('');
  const [expanded, setExpanded] = useState<Set<number>>(new Set());
  const log = useKeyset<AuditRow, number>({
    key: ['audit', area],
    pageSize: PAGE,
    fetchPage: async (before) => {
      let q = supabase
        .from('admin_audit_log')
        .select('id, actor_id, action, target_type, target_id, details, created_at, actor:profiles(username, full_name)')
        .order('id', { ascending: false })
        .limit(PAGE);
      if (area) q = q.like('action', `${area}%`);
      if (before) q = q.lt('id', before);
      const { data, error } = await q;
      if (error) throw toApiError(error);
      return (data ?? []) as unknown as AuditRow[];
    },
    cursorOf: (last) => last.id,
  });

  return (
    <div>
      <PageHeader
        title="Audit log"
        description="Every change made through the admin RPCs, append-only. Rows cannot be edited or deleted from the console."
        actions={
          <Select aria-label="Area" value={area} onChange={(e) => setArea(e.target.value)} className="w-48">
            {AREAS.map((a) => (
              <option key={a.value} value={a.value}>
                {a.label}
              </option>
            ))}
          </Select>
        }
      />
      <Card pad={false}>
        {log.error ? <ErrorState error={log.error} onRetry={() => void log.refetch()} /> : null}
        {log.isLoading ? (
          <Spinner />
        ) : log.items.length === 0 && !log.error ? (
          <EmptyState title="Nothing recorded yet" />
        ) : (
          <ul className="divide-y divide-line">
            {log.items.map((a) => {
              const open = expanded.has(a.id);
              const hasDetails = a.details && Object.keys(a.details).length > 0;
              return (
                <li key={a.id}>
                  <button
                    type="button"
                    aria-expanded={hasDetails ? open : undefined}
                    disabled={!hasDetails}
                    onClick={() => {
                      const next = new Set(expanded);
                      if (open) next.delete(a.id);
                      else next.add(a.id);
                      setExpanded(next);
                    }}
                    className="flex w-full flex-wrap items-center gap-x-3 gap-y-1 px-4 py-2.5 text-left text-sm enabled:hover:bg-surface-2"
                  >
                    <Badge tone={a.action.endsWith('delete') || a.action.endsWith('ban') ? 'danger' : 'neutral'}>{a.action}</Badge>
                    <span className="min-w-0 flex-1 truncate text-fg-2">
                      {a.target_type ? (
                        <>
                          {a.target_type} <code className="text-xs">{a.target_id ?? ''}</code>
                        </>
                      ) : null}
                    </span>
                    <span className="text-xs text-muted">@{a.actor?.username ?? 'unknown'}</span>
                    <span className="text-xs text-muted" title={fmtDateTime(a.created_at)}>
                      {fmtRelative(a.created_at)}
                    </span>
                    {hasDetails ? (
                      <ChevronDown className={cx('size-4 text-muted transition-transform', open && 'rotate-180')} aria-hidden />
                    ) : null}
                  </button>
                  {open ? (
                    <pre className="mx-4 mb-3 max-h-96 overflow-auto rounded-lg bg-surface-2 p-3 font-mono text-xs whitespace-pre-wrap text-fg-2">
                      {JSON.stringify(a.details, null, 2)}
                    </pre>
                  ) : null}
                </li>
              );
            })}
          </ul>
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
