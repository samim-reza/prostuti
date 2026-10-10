import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { AlertTriangle, ExternalLink, Pencil, Plus, Star, Trash2 } from 'lucide-react';
import { useState } from 'react';
import { useConfirm, useToast } from '../components/feedback';
import { Modal } from '../components/Modal';
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
  Select,
  Spinner,
  Switch,
  TableWrap,
  Textarea,
} from '../components/ui';
import { useExamTypes } from '../lib/catalog';
import { describeError } from '../lib/errors';
import { bdToday, fmtDate, fmtNumber, fmtRelative } from '../lib/format';
import { usePageTitle } from '../lib/hooks';
import { rpc } from '../lib/rpc';
import type { Schedule } from '../lib/types';

interface Draft {
  exam_type: string;
  title_bn: string;
  title_en: string;
  stage: string;
  expected_date: string;
  is_confirmed: boolean;
  source_url: string;
  notes: string;
  is_active: boolean;
}

export default function SchedulesPage() {
  usePageTitle('Exam schedules');
  const qc = useQueryClient();
  const toast = useToast();
  const confirm = useConfirm();
  const [editing, setEditing] = useState<{ schedule: Schedule | null } | null>(null);
  const q = useQuery({ queryKey: ['schedules'], queryFn: () => rpc<Schedule[]>('admin_list_schedules') });
  const del = useMutation({
    mutationFn: (id: number) => rpc('admin_delete_schedule', { p_id: id }),
    onSuccess: () => {
      toast.success('Schedule deleted.');
      void qc.invalidateQueries({ queryKey: ['schedules'] });
    },
    onError: (e) => toast.error(e),
  });

  return (
    <div>
      <PageHeader
        title="Exam schedules"
        description="Upcoming exam dates that study plans count down to. Dates are approximate until the recruiting body confirms them."
        actions={
          <Button variant="primary" icon={<Plus className="size-4" />} onClick={() => setEditing({ schedule: null })}>
            Add schedule
          </Button>
        }
      />
      <Notice tone="info" icon={<AlertTriangle className="size-4" />}>
        Changing an expected date re-plans every active study plan for that exam and notifies those learners.
      </Notice>
      <Card pad={false} className="mt-4">
        {q.error ? <ErrorState error={q.error} onRetry={() => void q.refetch()} /> : null}
        {q.isLoading ? (
          <Spinner />
        ) : !q.data?.length ? (
          <EmptyState title="No exam schedules" />
        ) : (
          <TableWrap>
            <table className="table-base">
              <thead>
                <tr>
                  <th scope="col">Exam</th>
                  <th scope="col">Expected date</th>
                  <th scope="col">Status</th>
                  <th scope="col" className="text-right">
                    Active plans
                  </th>
                  <th scope="col" className="text-right">
                    Targeting users
                  </th>
                  <th scope="col">
                    <span className="sr-only">Actions</span>
                  </th>
                </tr>
              </thead>
              <tbody>
                {q.data.map((s) => (
                  <tr key={s.id} className={s.is_active ? undefined : 'opacity-60'}>
                    <td className="min-w-64">
                      <p className="font-medium">
                        {s.title_en}{' '}
                        {s.is_default ? (
                          <Badge tone="brand" icon={<Star className="size-3" />}>
                            default
                          </Badge>
                        ) : null}
                      </p>
                      <p className="text-sm text-muted" lang="bn">
                        {s.title_bn}
                      </p>
                      <p className="text-xs text-muted">
                        {s.exam_type_name ?? s.exam_type} · {s.stage}
                        {s.source_url ? (
                          <>
                            {' · '}
                            <a
                              href={s.source_url}
                              target="_blank"
                              rel="noreferrer noopener"
                              className="inline-flex items-center gap-0.5 text-info hover:underline"
                            >
                              source <ExternalLink className="size-3" />
                            </a>
                          </>
                        ) : null}
                      </p>
                    </td>
                    <td className="whitespace-nowrap">
                      <p className="font-medium">{fmtDate(s.expected_date)}</p>
                      <p className="text-xs text-muted">
                        {s.expected_date < bdToday() ? 'passed' : fmtRelative(`${s.expected_date}T00:00:00+06:00`)}
                      </p>
                    </td>
                    <td>
                      <div className="flex flex-col items-start gap-1">
                        {s.is_confirmed ? <Badge tone="success">confirmed</Badge> : <Badge tone="warning">approximate</Badge>}
                        {s.is_active ? null : <Badge>inactive</Badge>}
                      </div>
                    </td>
                    <td className="num text-right">{fmtNumber(s.active_plans)}</td>
                    <td className="num text-right">{fmtNumber(s.target_users)}</td>
                    <td className="text-right whitespace-nowrap">
                      <Button size="sm" variant="ghost" icon={<Pencil className="size-3.5" />} onClick={() => setEditing({ schedule: s })}>
                        Edit
                      </Button>
                      <Button
                        size="sm"
                        variant="danger-ghost"
                        icon={<Trash2 className="size-3.5" />}
                        disabled={s.is_default || s.active_plans > 0}
                        title={s.is_default || s.active_plans > 0 ? 'In use: deactivate instead' : undefined}
                        loading={del.isPending && del.variables === s.id}
                        onClick={async () => {
                          const ok = await confirm({
                            title: `Delete "${s.title_en}"?`,
                            message: 'Users targeting it fall back to no target schedule.',
                            confirmLabel: 'Delete',
                            tone: 'danger',
                          });
                          if (ok) del.mutate(s.id);
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
      </Card>
      {editing ? <ScheduleEditor schedule={editing.schedule} onClose={() => setEditing(null)} /> : null}
    </div>
  );
}

function ScheduleEditor({ schedule, onClose }: { schedule: Schedule | null; onClose: () => void }) {
  const qc = useQueryClient();
  const toast = useToast();
  const confirm = useConfirm();
  const types = useExamTypes();
  const [d, setD] = useState<Draft>(
    schedule
      ? {
          exam_type: schedule.exam_type,
          title_bn: schedule.title_bn,
          title_en: schedule.title_en,
          stage: schedule.stage,
          expected_date: schedule.expected_date,
          is_confirmed: schedule.is_confirmed,
          source_url: schedule.source_url ?? '',
          notes: schedule.notes ?? '',
          is_active: schedule.is_active,
        }
      : {
          exam_type: 'bcs',
          title_bn: '',
          title_en: '',
          stage: 'preliminary',
          expected_date: '',
          is_confirmed: false,
          source_url: '',
          notes: '',
          is_active: true,
        },
  );
  const dateChanged = !!schedule && d.expected_date !== schedule.expected_date;
  const errors = {
    title_bn: d.title_bn.trim().length < 2 ? 'Required' : null,
    title_en: d.title_en.trim().length < 2 ? 'Required' : null,
    expected_date: !/^\d{4}-\d{2}-\d{2}$/.test(d.expected_date) ? 'Pick a date' : null,
    source_url: d.source_url.trim() && !/^https?:\/\/\S+$/i.test(d.source_url.trim()) ? 'An http(s) URL' : null,
  };
  const save = useMutation({
    mutationFn: () =>
      rpc<{ id: number; date_changed: boolean; replanned_plans: number }>('admin_save_schedule', {
        p_id: schedule?.id ?? null,
        p_schedule: {
          ...d,
          title_bn: d.title_bn.trim(),
          title_en: d.title_en.trim(),
          source_url: d.source_url.trim() || null,
          notes: d.notes.trim() || null,
        },
      }),
    onSuccess: (r) => {
      toast.success(
        r.date_changed
          ? `Saved. ${r.replanned_plans} study plan${r.replanned_plans === 1 ? '' : 's'} queued for re-planning.`
          : 'Schedule saved.',
      );
      void qc.invalidateQueries({ queryKey: ['schedules'] });
      onClose();
    },
  });

  async function submit() {
    if (dateChanged && schedule && schedule.active_plans > 0) {
      const ok = await confirm({
        title: 'Change the exam date?',
        message: (
          <>
            {fmtNumber(schedule.active_plans)} active study plan{schedule.active_plans === 1 ? '' : 's'} will be re-planned for{' '}
            {fmtDate(d.expected_date)} and those learners get a notification. This cannot be undone automatically.
          </>
        ),
        confirmLabel: 'Change date and re-plan',
        tone: 'danger',
      });
      if (!ok) return;
    }
    save.mutate();
  }

  return (
    <Modal
      open
      onClose={onClose}
      title={schedule ? 'Edit exam schedule' : 'Add exam schedule'}
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
          <Button variant="primary" disabled={Object.values(errors).some(Boolean)} loading={save.isPending} onClick={() => void submit()}>
            Save
          </Button>
        </>
      }
    >
      <div className="space-y-3">
        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="Exam type" htmlFor="sc-type">
            <Select id="sc-type" value={d.exam_type} onChange={(e) => setD({ ...d, exam_type: e.target.value })}>
              {types.data?.map((t) => (
                <option key={t.code} value={t.code}>
                  {t.name_en}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Stage" htmlFor="sc-stage">
            <Input id="sc-stage" value={d.stage} maxLength={40} onChange={(e) => setD({ ...d, stage: e.target.value })} />
          </Field>
        </div>
        <Field label="Title (English)" htmlFor="sc-ten" error={errors.title_en}>
          <Input id="sc-ten" value={d.title_en} maxLength={200} onChange={(e) => setD({ ...d, title_en: e.target.value })} />
        </Field>
        <Field label="Title (বাংলা)" htmlFor="sc-tbn" error={errors.title_bn}>
          <Input id="sc-tbn" lang="bn" value={d.title_bn} maxLength={200} onChange={(e) => setD({ ...d, title_bn: e.target.value })} />
        </Field>
        <Field label="Expected date" htmlFor="sc-date" error={errors.expected_date}>
          <Input id="sc-date" type="date" value={d.expected_date} onChange={(e) => setD({ ...d, expected_date: e.target.value })} />
        </Field>
        {dateChanged ? (
          <Notice tone="warning" icon={<AlertTriangle className="size-4" />}>
            {schedule?.active_plans
              ? `${fmtNumber(schedule.active_plans)} active study plan${schedule.active_plans === 1 ? '' : 's'} will be re-planned and notified.`
              : 'No active study plans target this exam yet.'}
          </Notice>
        ) : null}
        <Field label="Source URL" htmlFor="sc-url" error={errors.source_url}>
          <Input
            id="sc-url"
            type="url"
            value={d.source_url}
            onChange={(e) => setD({ ...d, source_url: e.target.value })}
            placeholder="Circular or news link"
          />
        </Field>
        <Field label="Notes (internal)" htmlFor="sc-notes">
          <Textarea id="sc-notes" rows={2} maxLength={1000} value={d.notes} onChange={(e) => setD({ ...d, notes: e.target.value })} />
        </Field>
        <div className="grid gap-3 sm:grid-cols-2">
          <Switch
            checked={d.is_confirmed}
            onChange={(v) => setD({ ...d, is_confirmed: v })}
            label="Confirmed date"
            description="Shown as official in the app."
          />
          <Switch
            checked={d.is_active}
            onChange={(v) => setD({ ...d, is_active: v })}
            label="Active"
            description="Inactive schedules are hidden from learners."
          />
        </div>
      </div>
    </Modal>
  );
}
