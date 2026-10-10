import { AlertOctagon, Search, Smartphone } from 'lucide-react';
import { useState } from 'react';
import { Modal } from '../../components/Modal';
import {
  Badge,
  Card,
  CopyButton,
  EmptyState,
  ErrorState,
  Input,
  LoadMore,
  PageHeader,
  Segmented,
  Select,
  Spinner,
  TableWrap,
  Checkbox,
} from '../../components/ui';
import { fmtDateTime, fmtNumber, fmtRelative, truncate } from '../../lib/format';
import { useDebounced, usePageTitle } from '../../lib/hooks';
import { useKeyset } from '../../lib/keyset';
import { clean, rpc } from '../../lib/rpc';
import type { ErrorEvent, ErrorGroup } from '../../lib/types';

const PAGE = 50;
type Window = '24' | '168' | '720';

export default function ErrorsPage() {
  usePageTitle('Client errors');
  const [hours, setHours] = useState<Window>('24');
  const [platform, setPlatform] = useState('');
  const [fatalOnly, setFatalOnly] = useState(false);
  const [search, setSearch] = useState('');
  const q = useDebounced(search.trim(), 350);
  const [open, setOpen] = useState<ErrorGroup | null>(null);

  const groups = useKeyset<ErrorGroup, { last: string; fp: string }>({
    key: ['client-errors', hours, platform, fatalOnly, q],
    pageSize: PAGE,
    fetchPage: (c) =>
      rpc<ErrorGroup[]>(
        'admin_list_client_errors',
        clean({
          p_hours: Number(hours),
          p_platform: platform,
          p_fatal_only: fatalOnly,
          p_search: q,
          p_limit: PAGE,
          p_after_last_seen: c?.last,
          p_after_fingerprint: c?.fp,
        }),
      ),
    cursorOf: (last) => ({ last: last.last_seen, fp: last.fingerprint }),
  });

  return (
    <div>
      <PageHeader
        title="Client errors"
        description="Uncaught errors reported by release builds, grouped by fingerprint. Repeats from the same user within an hour count as occurrences of one report."
        actions={
          <Segmented<Window>
            label="Time window"
            value={hours}
            onChange={setHours}
            options={[
              { value: '24', label: '24 h' },
              { value: '168', label: '7 days' },
              { value: '720', label: '30 days' },
            ]}
          />
        }
      />
      <Card pad={false}>
        <div className="flex flex-wrap items-center gap-3 border-b border-line p-3">
          <label className="relative min-w-56 flex-1">
            <span className="sr-only">Search errors</span>
            <Search className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted" aria-hidden />
            <Input
              type="search"
              className="pl-9"
              placeholder="Error text, route or fingerprint"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </label>
          <Select aria-label="Platform" value={platform} onChange={(e) => setPlatform(e.target.value)} className="w-40">
            <option value="">All platforms</option>
            <option value="android">Android</option>
            <option value="ios">iOS</option>
            <option value="web">Web</option>
          </Select>
          <Checkbox label="Fatal only" checked={fatalOnly} onChange={setFatalOnly} />
        </div>
        {groups.error ? <ErrorState error={groups.error} onRetry={() => void groups.refetch()} /> : null}
        {groups.isLoading ? (
          <Spinner />
        ) : groups.items.length === 0 && !groups.error ? (
          <EmptyState title="No errors in this window">Either the app is healthy, or crash reporting is not deployed yet.</EmptyState>
        ) : (
          <TableWrap>
            <table className="table-base">
              <thead>
                <tr>
                  <th scope="col">Error</th>
                  <th scope="col" className="text-right">
                    Events
                  </th>
                  <th scope="col" className="text-right">
                    Users
                  </th>
                  <th scope="col">Platforms · versions</th>
                  <th scope="col">Last seen</th>
                </tr>
              </thead>
              <tbody>
                {groups.items.map((g) => (
                  <tr
                    key={g.fingerprint}
                    className="row-link"
                    tabIndex={0}
                    onClick={() => setOpen(g)}
                    onKeyDown={(e) => e.key === 'Enter' && setOpen(g)}
                  >
                    <td className="min-w-80">
                      <p className="font-mono text-[0.8125rem] break-words text-fg">{truncate(g.error, 180)}</p>
                      <p className="mt-0.5 flex flex-wrap items-center gap-1.5 text-xs text-muted">
                        {g.fatal ? (
                          <Badge tone="danger" icon={<AlertOctagon className="size-3" />}>
                            fatal
                          </Badge>
                        ) : null}
                        {g.route ? <code>{g.route}</code> : null}
                        <span>first {fmtRelative(g.first_seen)}</span>
                      </p>
                    </td>
                    <td className="num text-right font-semibold">{fmtNumber(g.events)}</td>
                    <td className="num text-right">{fmtNumber(g.users)}</td>
                    <td className="text-xs text-fg-2">
                      {(g.platforms ?? []).join(', ') || '—'}
                      <span className="block text-muted">{(g.versions ?? []).join(', ')}</span>
                    </td>
                    <td className="text-sm whitespace-nowrap" title={fmtDateTime(g.last_seen)}>
                      {fmtRelative(g.last_seen)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TableWrap>
        )}
        <LoadMore
          hasMore={!!groups.hasNextPage}
          loading={groups.isFetchingNextPage}
          onClick={() => void groups.fetchNextPage()}
          count={groups.items.length}
        />
      </Card>
      <ErrorGroupDrawer group={open} onClose={() => setOpen(null)} />
    </div>
  );
}

function ErrorGroupDrawer({ group, onClose }: { group: ErrorGroup | null; onClose: () => void }) {
  const events = useKeyset<ErrorEvent, { created: string; id: number }>({
    key: ['client-error-events', group?.fingerprint],
    pageSize: 20,
    enabled: !!group,
    fetchPage: (c) =>
      rpc<ErrorEvent[]>(
        'admin_client_error_events',
        clean({ p_fingerprint: group?.fingerprint, p_limit: 20, p_before_created: c?.created, p_before_id: c?.id }),
      ),
    cursorOf: (last) => ({ created: last.created_at, id: last.id }),
  });
  return (
    <Modal
      open={!!group}
      onClose={onClose}
      variant="drawer"
      size="xl"
      title="Error details"
      description={
        group ? `${fmtNumber(group.events)} events · ${fmtNumber(group.users)} users · fingerprint ${group.fingerprint}` : undefined
      }
    >
      {group ? (
        <div className="space-y-4">
          <div className="flex items-start gap-2">
            <pre className="min-w-0 flex-1 rounded-lg bg-surface-2 p-3 font-mono text-[0.8125rem] whitespace-pre-wrap text-fg">
              {group.error}
            </pre>
            <CopyButton text={group.error} label="Copy error" />
          </div>
          {events.error ? <ErrorState error={events.error} onRetry={() => void events.refetch()} /> : null}
          {events.isLoading ? <Spinner /> : null}
          <ol className="space-y-3">
            {events.items.map((e) => (
              <li key={e.id} className="card p-3">
                <div className="flex flex-wrap items-center gap-1.5 text-xs text-muted">
                  {e.fatal ? <Badge tone="danger">fatal</Badge> : null}
                  <Badge icon={<Smartphone className="size-3" />}>
                    {e.platform ?? '?'} {e.app_version ?? ''}
                    {e.build_number ? ` (${e.build_number})` : ''}
                  </Badge>
                  {e.occurrences > 1 ? <Badge tone="warning">×{e.occurrences}</Badge> : null}
                  <span>{fmtDateTime(e.created_at)}</span>
                  {e.last_seen_at !== e.created_at ? <span>→ {fmtDateTime(e.last_seen_at)}</span> : null}
                </div>
                <dl className="mt-2 grid grid-cols-[6rem_1fr] gap-x-3 gap-y-1 text-xs">
                  <dt className="text-muted">User</dt>
                  <dd>{e.username ? `@${e.username}` : e.user_id ? e.user_id : 'signed out'}</dd>
                  <dt className="text-muted">Route</dt>
                  <dd>
                    <code>{e.route ?? '—'}</code>
                  </dd>
                  <dt className="text-muted">Device</dt>
                  <dd className="break-words">{e.os ?? '—'}</dd>
                  <dt className="text-muted">Locale</dt>
                  <dd>{e.locale ?? '—'}</dd>
                  {e.context ? (
                    <>
                      <dt className="text-muted">Context</dt>
                      <dd className="break-words">{e.context}</dd>
                    </>
                  ) : null}
                </dl>
                {e.stack ? (
                  <details className="mt-2">
                    <summary className="cursor-pointer text-xs text-muted hover:text-fg">Stack trace</summary>
                    <pre className="mt-1.5 max-h-80 overflow-auto rounded-lg bg-surface-2 p-2 font-mono text-[0.75rem] leading-relaxed whitespace-pre text-fg-2">
                      {e.stack}
                    </pre>
                  </details>
                ) : null}
              </li>
            ))}
          </ol>
          <LoadMore hasMore={!!events.hasNextPage} loading={events.isFetchingNextPage} onClick={() => void events.fetchNextPage()} />
        </div>
      ) : null}
    </Modal>
  );
}
