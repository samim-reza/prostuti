import { Ban, Search } from 'lucide-react';
import { useState } from 'react';
import { useSearchParams } from 'react-router';
import { RoleBadge } from '../../components/badges';
import { Avatar, Badge, Card, EmptyState, ErrorState, Input, LoadMore, PageHeader, Select, Spinner, TableWrap } from '../../components/ui';
import { fmtDate, fmtNumber, fmtRelative } from '../../lib/format';
import { useDebounced, usePageTitle } from '../../lib/hooks';
import { useKeyset } from '../../lib/keyset';
import { clean, rpc } from '../../lib/rpc';
import type { UserRow } from '../../lib/types';
import { UserDrawer } from './UserDrawer';

const PAGE = 30;

export default function UsersPage() {
  usePageTitle('Users');
  const [params, setParams] = useSearchParams();
  const [search, setSearch] = useState(params.get('q') ?? '');
  const role = params.get('role') ?? '';
  const banned = params.get('banned') ?? '';
  const selected = params.get('user');
  const q = useDebounced(search.trim(), 350);

  const setParam = (key: string, value: string | null) => {
    const next = new URLSearchParams(params);
    if (value) next.set(key, value);
    else next.delete(key);
    setParams(next, { replace: true });
  };

  const list = useKeyset<UserRow, { created: string; id: string }>({
    key: ['users', q, role, banned],
    pageSize: PAGE,
    fetchPage: (cursor) =>
      rpc<UserRow[]>(
        'admin_list_users',
        clean({
          p_search: q,
          p_role: role,
          p_banned: banned === '' ? undefined : banned === 'yes',
          p_limit: PAGE,
          p_after_created: cursor?.created,
          p_after_id: cursor?.id,
        }),
      ),
    cursorOf: (last) => ({ created: last.created_at, id: last.id }),
  });

  return (
    <div>
      <PageHeader title="Users" description="Search by username, name, e-mail or user id. Click a user for details and actions." />
      <Card pad={false}>
        <div className="flex flex-wrap items-end gap-3 border-b border-line p-3">
          <label className="relative min-w-56 flex-1">
            <span className="sr-only">Search users</span>
            <Search className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted" aria-hidden />
            <Input
              type="search"
              placeholder="username, name, e-mail or id"
              value={search}
              onChange={(e) => {
                setSearch(e.target.value);
                setParam('q', e.target.value.trim() || null);
              }}
              className="pl-9"
            />
          </label>
          <Select aria-label="Role" value={role} onChange={(e) => setParam('role', e.target.value || null)} className="w-40">
            <option value="">All roles</option>
            <option value="user">Users</option>
            <option value="moderator">Moderators</option>
            <option value="admin">Admins</option>
          </Select>
          <Select aria-label="Ban status" value={banned} onChange={(e) => setParam('banned', e.target.value || null)} className="w-40">
            <option value="">Any status</option>
            <option value="no">Not banned</option>
            <option value="yes">Banned</option>
          </Select>
        </div>
        {list.error ? <ErrorState error={list.error} onRetry={() => void list.refetch()} /> : null}
        {list.isLoading ? (
          <Spinner />
        ) : list.items.length === 0 && !list.error ? (
          <EmptyState title="No users match">Try a different search or filter.</EmptyState>
        ) : (
          <TableWrap>
            <table className="table-base">
              <thead>
                <tr>
                  <th scope="col">User</th>
                  <th scope="col">E-mail</th>
                  <th scope="col">Role</th>
                  <th scope="col">Targets</th>
                  <th scope="col">Onboarding</th>
                  <th scope="col" className="text-right">
                    Exams
                  </th>
                  <th scope="col">Last active</th>
                  <th scope="col">Joined</th>
                </tr>
              </thead>
              <tbody>
                {list.items.map((u) => (
                  <tr
                    key={u.id}
                    className="row-link"
                    tabIndex={0}
                    onClick={() => setParam('user', u.id)}
                    onKeyDown={(e) => e.key === 'Enter' && setParam('user', u.id)}
                    aria-label={`Open ${u.username ?? u.id}`}
                  >
                    <td>
                      <div className="flex items-center gap-2.5">
                        <Avatar name={u.full_name || u.username || '?'} url={u.avatar_url} size={30} />
                        <div className="min-w-0">
                          <p className="truncate font-medium text-fg" lang={/[ঀ-৿]/.test(u.full_name ?? '') ? 'bn' : undefined}>
                            {u.full_name || '—'}
                          </p>
                          <p className="truncate text-xs text-muted">@{u.username ?? '—'}</p>
                        </div>
                      </div>
                    </td>
                    <td className="max-w-56 truncate text-fg-2">{u.email ?? '—'}</td>
                    <td>
                      <div className="flex flex-wrap gap-1">
                        <RoleBadge role={u.role} />
                        {u.is_banned ? (
                          <Badge tone="danger" icon={<Ban className="size-3" />}>
                            banned
                          </Badge>
                        ) : null}
                      </div>
                    </td>
                    <td className="text-xs whitespace-nowrap text-fg-2">{u.target_exams.join(', ') || '—'}</td>
                    <td>
                      <Badge tone={u.onboarding_step === 'done' ? 'success' : 'neutral'}>{u.onboarding_step}</Badge>
                    </td>
                    <td className="num text-right">{fmtNumber(u.exams_taken)}</td>
                    <td className="whitespace-nowrap text-fg-2">{u.last_active_date ? fmtDate(u.last_active_date) : '—'}</td>
                    <td className="whitespace-nowrap text-fg-2" title={u.created_at}>
                      {fmtRelative(u.created_at)}
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
      <UserDrawer userId={selected} onClose={() => setParam('user', null)} />
    </div>
  );
}
