import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Pencil, Plus, Search, Trash2 } from 'lucide-react';
import { useState } from 'react';
import { useConfirm, useToast } from '../../components/feedback';
import { Modal } from '../../components/Modal';
import {
  Badge,
  Button,
  Card,
  CopyButton,
  EmptyState,
  ErrorState,
  Field,
  Input,
  LoadMore,
  PageHeader,
  Select,
  Spinner,
  Switch,
  TableWrap,
} from '../../components/ui';
import { describeError } from '../../lib/errors';
import { fmtDateTime, fmtNumber, fmtRelative, fromLocalInput, toLocalInput } from '../../lib/format';
import { useDebounced, usePageTitle } from '../../lib/hooks';
import { useKeyset } from '../../lib/keyset';
import { useAddons } from '../../lib/queries';
import { clean, rpc } from '../../lib/rpc';
import type { Promo } from '../../lib/types';

const PAGE = 50;
const STATE_TONE = { live: 'success', inactive: 'neutral', expired: 'warning', exhausted: 'info' } as const;

export default function PromosPage() {
  usePageTitle('Promo codes');
  const qc = useQueryClient();
  const toast = useToast();
  const confirm = useConfirm();
  const [search, setSearch] = useState('');
  const q = useDebounced(search.trim(), 300);
  const [editing, setEditing] = useState<{ promo: Promo | null } | null>(null);

  const list = useKeyset<Promo, { created: string; code: string }>({
    key: ['promos', q],
    pageSize: PAGE,
    fetchPage: (c) =>
      rpc<Promo[]>('admin_list_promos', clean({ p_search: q, p_limit: PAGE, p_after_created: c?.created, p_after_code: c?.code })),
    cursorOf: (last) => ({ created: last.created_at, code: last.code }),
  });
  const del = useMutation({
    mutationFn: (code: string) => rpc('admin_delete_promo', { p_code: code }),
    onSuccess: () => {
      toast.success('Promo code deleted.');
      void qc.invalidateQueries({ queryKey: ['promos'] });
    },
    onError: (e) => toast.error(e),
  });

  return (
    <div>
      <PageHeader
        title="Promo codes"
        description="Learners redeem codes in Add-ons; each code grants an add-on for a number of days (stacked on any running period)."
        actions={
          <Button variant="primary" icon={<Plus className="size-4" />} onClick={() => setEditing({ promo: null })}>
            New code
          </Button>
        }
      />
      <Card pad={false}>
        <div className="border-b border-line p-3">
          <label className="relative block max-w-sm">
            <span className="sr-only">Search codes</span>
            <Search className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted" aria-hidden />
            <Input type="search" placeholder="Search codes" className="pl-9" value={search} onChange={(e) => setSearch(e.target.value)} />
          </label>
        </div>
        {list.error ? <ErrorState error={list.error} onRetry={() => void list.refetch()} /> : null}
        {list.isLoading ? (
          <Spinner />
        ) : list.items.length === 0 && !list.error ? (
          <EmptyState title="No promo codes yet" />
        ) : (
          <TableWrap>
            <table className="table-base">
              <thead>
                <tr>
                  <th scope="col">Code</th>
                  <th scope="col">Grants</th>
                  <th scope="col">Redemptions</th>
                  <th scope="col">Expires</th>
                  <th scope="col">State</th>
                  <th scope="col">
                    <span className="sr-only">Actions</span>
                  </th>
                </tr>
              </thead>
              <tbody>
                {list.items.map((p) => (
                  <tr key={p.code}>
                    <td>
                      <span className="inline-flex items-center gap-1">
                        <code className="font-semibold">{p.code}</code>
                        <CopyButton text={p.code} label="Copy code" />
                      </span>
                      <p className="text-xs text-muted">created {fmtRelative(p.created_at)}</p>
                    </td>
                    <td className="text-sm">
                      {p.addon_name ?? p.addon_code} · {p.days} days
                    </td>
                    <td className="num text-sm">
                      {fmtNumber(p.redeemed_count)}
                      {p.max_redemptions ? ` / ${fmtNumber(p.max_redemptions)}` : ' / ∞'}
                    </td>
                    <td className="text-sm whitespace-nowrap" title={fmtDateTime(p.expires_at)}>
                      {p.expires_at ? fmtDateTime(p.expires_at) : 'never'}
                    </td>
                    <td>
                      <Badge tone={STATE_TONE[p.state]}>{p.state}</Badge>
                    </td>
                    <td className="text-right whitespace-nowrap">
                      <Button size="sm" variant="ghost" icon={<Pencil className="size-3.5" />} onClick={() => setEditing({ promo: p })}>
                        Edit
                      </Button>
                      <Button
                        size="sm"
                        variant="danger-ghost"
                        icon={<Trash2 className="size-3.5" />}
                        disabled={p.redeemed_count > 0}
                        title={p.redeemed_count > 0 ? 'Redeemed codes can only be deactivated' : undefined}
                        loading={del.isPending && del.variables === p.code}
                        onClick={async () => {
                          const ok = await confirm({ title: `Delete ${p.code}?`, confirmLabel: 'Delete', tone: 'danger' });
                          if (ok) del.mutate(p.code);
                        }}
                      >
                        Delete
                      </Button>
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
      {editing ? <PromoEditor promo={editing.promo} onClose={() => setEditing(null)} /> : null}
    </div>
  );
}

function randomCode(): string {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  return `PRO-${Array.from(bytes, (b) => alphabet[b % alphabet.length]).join('')}`;
}

function PromoEditor({ promo, onClose }: { promo: Promo | null; onClose: () => void }) {
  const qc = useQueryClient();
  const toast = useToast();
  const addons = useAddons();
  const [code, setCode] = useState(promo?.code ?? '');
  const [addon, setAddon] = useState(promo?.addon_code ?? 'prostuti_pro');
  const [days, setDays] = useState(String(promo?.days ?? 30));
  const [max, setMax] = useState(promo?.max_redemptions ? String(promo.max_redemptions) : '');
  const [expires, setExpires] = useState(toLocalInput(promo?.expires_at));
  const [active, setActive] = useState(promo?.is_active ?? true);
  const errors = {
    code: !/^[A-Za-z0-9_-]{3,40}$/.test(code) ? '3–40 letters, digits, - or _' : null,
    days: !/^\d+$/.test(days) || Number(days) < 1 || Number(days) > 3650 ? '1–3650' : null,
    max:
      max && (!/^\d+$/.test(max) || Number(max) < 1)
        ? 'A positive number, or empty for unlimited'
        : max && promo && Number(max) < promo.redeemed_count
          ? `At least ${promo.redeemed_count} (already redeemed)`
          : null,
    expires: !promo && expires && (fromLocalInput(expires) ?? '') <= new Date().toISOString() ? 'Must be in the future' : null,
  };
  const save = useMutation({
    mutationFn: () =>
      rpc<Promo>('admin_save_promo', {
        p_code: code,
        p_create: !promo,
        p_promo: {
          addon_code: addon,
          days: Number(days),
          max_redemptions: max ? Number(max) : null,
          expires_at: fromLocalInput(expires),
          is_active: active,
        },
      }),
    onSuccess: () => {
      toast.success(promo ? 'Promo code saved.' : `Promo code ${code} created.`);
      void qc.invalidateQueries({ queryKey: ['promos'] });
      onClose();
    },
  });
  return (
    <Modal
      open
      onClose={onClose}
      title={promo ? `Edit ${promo.code}` : 'New promo code'}
      footer={
        <>
          {save.error ? (
            <p role="alert" className="mr-auto text-sm text-danger">
              {describeError(save.error)}
            </p>
          ) : null}
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="primary" disabled={Object.values(errors).some(Boolean)} loading={save.isPending} onClick={() => save.mutate()}>
            Save
          </Button>
        </>
      }
    >
      <div className="space-y-3">
        <Field label="Code" htmlFor="pr-code" error={errors.code} hint="Case-insensitive for learners.">
          <div className="flex gap-2">
            <Input
              id="pr-code"
              value={code}
              disabled={!!promo}
              onChange={(e) => setCode(e.target.value.trim())}
              className="font-mono uppercase"
            />
            {!promo ? <Button onClick={() => setCode(randomCode())}>Generate</Button> : null}
          </div>
        </Field>
        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="Add-on" htmlFor="pr-addon">
            <Select id="pr-addon" value={addon} onChange={(e) => setAddon(e.target.value)}>
              {addons.data?.addons.map((a) => (
                <option key={a.code} value={a.code}>
                  {a.name_en}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Days granted" htmlFor="pr-days" error={errors.days}>
            <Input id="pr-days" inputMode="numeric" value={days} onChange={(e) => setDays(e.target.value)} />
          </Field>
          <Field label="Max redemptions" htmlFor="pr-max" error={errors.max} hint="Empty = unlimited">
            <Input id="pr-max" inputMode="numeric" value={max} onChange={(e) => setMax(e.target.value.trim())} />
          </Field>
          <Field label="Expires (your local time)" htmlFor="pr-exp" error={errors.expires} hint="Empty = never">
            <Input id="pr-exp" type="datetime-local" value={expires} onChange={(e) => setExpires(e.target.value)} />
          </Field>
        </div>
        <Switch checked={active} onChange={setActive} label="Active" description="Inactive codes can't be redeemed." />
      </div>
    </Modal>
  );
}
