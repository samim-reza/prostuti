import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Eye, EyeOff, Lock, Pencil, Plus } from 'lucide-react';
import { useMemo, useState } from 'react';
import { JsonDiff, JsonEditor, parseJson } from '../components/json';
import { Modal } from '../components/Modal';
import { useToast } from '../components/feedback';
import {
  Badge,
  Button,
  Card,
  EmptyState,
  ErrorState,
  Field,
  Input,
  Notice,
  PageHeader,
  Spinner,
  Switch,
  TableWrap,
} from '../components/ui';
import { prettyJson } from '../lib/diff';
import { describeError } from '../lib/errors';
import { fmtDateTime, fmtRelative, truncate } from '../lib/format';
import { usePageTitle } from '../lib/hooks';
import { rpc } from '../lib/rpc';
import type { ConfigRow } from '../lib/types';

/** What the server accepts for well-known keys (mirrors public._admin_config_error). */
const KNOWN: Record<string, { hint: string; check?: (v: unknown) => string | null }> = {
  min_app_version: {
    hint: 'Version string. Clients below it must update.',
    check: (v) => (typeof v === 'string' && /^\d+\.\d+\.\d+(\+\d+)?$/.test(v) ? null : 'Expected a version string like "1.2.3".'),
  },
  latest_app_version: {
    hint: 'Version string shown as an optional update.',
    check: (v) => (typeof v === 'string' && /^\d+\.\d+\.\d+(\+\d+)?$/.test(v) ? null : 'Expected a version string like "1.2.3".'),
  },
  morning_routine_time: {
    hint: 'Asia/Dhaka time of the morning routine notification, "HH:MM".',
    check: (v) => (typeof v === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(v) ? null : 'Expected a time like "06:30".'),
  },
  notes_ready_time: {
    hint: 'Asia/Dhaka time notes are expected to be ready, "HH:MM".',
    check: (v) => (typeof v === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(v) ? null : 'Expected a time like "06:00".'),
  },
  default_schedule_id: {
    hint: 'Id of the exam schedule new study plans target (see Exam schedules).',
    check: (v) => (Number.isInteger(v) ? null : 'Expected a schedule id.'),
  },
  ads: {
    hint: '{"rewarded_enabled": true, "android_rewarded_unit": "", "ios_rewarded_unit": ""}; empty unit ids use Google test ads.',
    check: (v) => (typeof v === 'object' && v !== null && !Array.isArray(v) ? null : 'Expected an object.'),
  },
  maintenance: {
    hint: '{"enabled": false, "message_bn": ""} shows a maintenance banner in the app.',
    check: (v) =>
      typeof v === 'object' && v !== null && typeof (v as { enabled?: unknown }).enabled === 'boolean'
        ? null
        : 'Expected {"enabled": true|false, …}.',
  },
  placement: {
    hint: 'Level test shape: {"per_group": 1–50, "duration_minutes": 5–180}.',
    check: (v) => {
      const o = v as { per_group?: unknown; duration_minutes?: unknown } | null;
      return o &&
        Number.isInteger(o.per_group) &&
        Number(o.per_group) >= 1 &&
        Number(o.per_group) <= 50 &&
        Number.isInteger(o.duration_minutes) &&
        Number(o.duration_minutes) >= 5 &&
        Number(o.duration_minutes) <= 180
        ? null
        : 'Expected {"per_group": 1–50, "duration_minutes": 5–180}.';
    },
  },
  support: { hint: 'Support links: {"email": "…", "facebook": "…"}.' },
  ai_pricing: {
    hint: 'Private. USD per 1M tokens per model, used for AI cost estimates: {"usd_to_bdt": 122, "models": {"<model>": {"input": n, "output": n}}}.',
  },
};

export default function ConfigPage() {
  usePageTitle('App config');
  const q = useQuery({ queryKey: ['config'], queryFn: () => rpc<ConfigRow[]>('admin_list_config') });
  const [editing, setEditing] = useState<{ row: ConfigRow | null } | null>(null);
  return (
    <div>
      <PageHeader
        title="App config"
        description="Remote configuration read by the app at start-up. Public keys are readable by everyone (including signed-out clients); private keys only by the backend and admins."
        actions={
          <Button variant="primary" icon={<Plus className="size-4" />} onClick={() => setEditing({ row: null })}>
            Add key
          </Button>
        }
      />
      <Card pad={false}>
        {q.error ? <ErrorState error={q.error} onRetry={() => void q.refetch()} /> : null}
        {q.isLoading ? (
          <Spinner />
        ) : !q.data?.length ? (
          <EmptyState title="No config keys" />
        ) : (
          <TableWrap>
            <table className="table-base">
              <thead>
                <tr>
                  <th scope="col">Key</th>
                  <th scope="col">Value</th>
                  <th scope="col">Visibility</th>
                  <th scope="col">Updated</th>
                  <th scope="col">
                    <span className="sr-only">Edit</span>
                  </th>
                </tr>
              </thead>
              <tbody>
                {q.data.map((r) => (
                  <tr
                    key={r.key}
                    className="row-link"
                    tabIndex={0}
                    onClick={() => setEditing({ row: r })}
                    onKeyDown={(e) => e.key === 'Enter' && setEditing({ row: r })}
                  >
                    <td className="min-w-48">
                      <code className="font-semibold">{r.key}</code>
                      {r.description ? <p className="text-xs text-muted">{r.description}</p> : null}
                    </td>
                    <td className="max-w-md">
                      <code className="text-xs break-all text-fg-2">{truncate(JSON.stringify(r.value), 160)}</code>
                    </td>
                    <td>
                      {r.is_public ? (
                        <Badge tone="info" icon={<Eye className="size-3" />}>
                          public
                        </Badge>
                      ) : (
                        <Badge icon={<Lock className="size-3" />}>private</Badge>
                      )}
                    </td>
                    <td className="text-sm whitespace-nowrap text-fg-2" title={fmtDateTime(r.updated_at)}>
                      {fmtRelative(r.updated_at)}
                    </td>
                    <td className="text-right">
                      <Button
                        size="sm"
                        variant="ghost"
                        icon={<Pencil className="size-3.5" />}
                        onClick={(e) => {
                          e.stopPropagation();
                          setEditing({ row: r });
                        }}
                      >
                        Edit
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TableWrap>
        )}
      </Card>
      {editing ? <ConfigEditor row={editing.row} existing={q.data?.map((r) => r.key) ?? []} onClose={() => setEditing(null)} /> : null}
    </div>
  );
}

function ConfigEditor({ row, existing, onClose }: { row: ConfigRow | null; existing: string[]; onClose: () => void }) {
  const qc = useQueryClient();
  const toast = useToast();
  const [key, setKey] = useState(row?.key ?? '');
  const [text, setText] = useState(row ? prettyJson(row.value) : '""');
  const [description, setDescription] = useState(row?.description ?? '');
  const [isPublic, setIsPublic] = useState(row?.is_public ?? false);
  const [reviewing, setReviewing] = useState(false);
  const parsed = useMemo(() => parseJson(text), [text]);
  const known = KNOWN[row?.key ?? key];
  const shapeError = parsed.ok && known?.check ? known.check(parsed.value) : null;
  const keyError = row
    ? null
    : !/^[a-z][a-z0-9_]{1,63}$/.test(key)
      ? 'lowercase letters, digits and _'
      : existing.includes(key)
        ? 'This key already exists'
        : null;
  const changed =
    !row ||
    (parsed.ok && JSON.stringify(parsed.value) !== JSON.stringify(row.value)) ||
    description !== (row.description ?? '') ||
    isPublic !== row.is_public;

  const save = useMutation({
    mutationFn: () =>
      rpc<ConfigRow>('admin_set_config', {
        p_key: row?.key ?? key,
        p_value: parsed.ok ? parsed.value : null,
        p_description: description.trim() || null,
        p_is_public: isPublic,
        p_expected_updated_at: row?.updated_at ?? null,
      }),
    onSuccess: () => {
      toast.success(`${row?.key ?? key} saved.`);
      void qc.invalidateQueries({ queryKey: ['config'] });
      onClose();
    },
  });

  const canReview = parsed.ok && !shapeError && !keyError && changed;
  return (
    <Modal
      open
      onClose={onClose}
      size="lg"
      title={row ? `Edit ${row.key}` : 'Add config key'}
      description={known?.hint}
      footer={
        <>
          {save.error ? (
            <p role="alert" className="mr-auto text-sm text-danger">
              {describeError(save.error)}
            </p>
          ) : null}
          {reviewing ? (
            <>
              <Button variant="ghost" onClick={() => setReviewing(false)}>
                Back to editing
              </Button>
              <Button variant="primary" loading={save.isPending} onClick={() => save.mutate()}>
                Confirm and save
              </Button>
            </>
          ) : (
            <>
              <Button variant="ghost" onClick={onClose}>
                Cancel
              </Button>
              <Button variant="primary" disabled={!canReview} onClick={() => setReviewing(true)}>
                Review changes
              </Button>
            </>
          )}
        </>
      }
    >
      {reviewing ? (
        <div className="space-y-3">
          <p className="text-sm text-fg-2">
            Review the change to <code className="font-semibold">{row?.key ?? key}</code>. Apps pick it up on their next start.
          </p>
          <JsonDiff
            before={row ? { value: row.value, description: row.description, is_public: row.is_public } : {}}
            after={{ value: parsed.ok ? parsed.value : null, description: description.trim() || null, is_public: isPublic }}
          />
          {isPublic && !row?.is_public ? (
            <Notice tone="warning" icon={<EyeOff className="size-4" />}>
              This value becomes readable by anyone, including signed-out users. Never store secrets in config.
            </Notice>
          ) : null}
        </div>
      ) : (
        <div className="space-y-3">
          {!row ? (
            <Field label="Key" htmlFor="cf-key" error={key ? keyError : null}>
              <Input id="cf-key" value={key} onChange={(e) => setKey(e.target.value.trim())} placeholder="feature_flag_name" />
            </Field>
          ) : null}
          <Field label="Value (JSON)" htmlFor="cf-value" error={shapeError}>
            <JsonEditor id="cf-value" label="Value" rows={12} value={text} onChange={setText} />
          </Field>
          <Field label="Description" htmlFor="cf-desc">
            <Input id="cf-desc" value={description} maxLength={300} onChange={(e) => setDescription(e.target.value)} />
          </Field>
          <Switch
            checked={isPublic}
            onChange={setIsPublic}
            label="Public"
            description="Readable by the app without signing in. Keep secrets private."
          />
        </div>
      )}
    </Modal>
  );
}
