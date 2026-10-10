import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Ban, Gift, RotateCcw, ShieldCheck, Undo2 } from 'lucide-react';
import { useEffect, useState } from 'react';
import { useStaff } from '../../auth/AuthProvider';
import { RoleBadge } from '../../components/badges';
import { useConfirm, useToast } from '../../components/feedback';
import { Modal } from '../../components/Modal';
import {
  Avatar,
  Badge,
  Button,
  Card,
  CopyButton,
  ErrorState,
  Field,
  Input,
  KeyValue,
  Select,
  Spinner,
  TableWrap,
  Textarea,
} from '../../components/ui';
import { fmtDate, fmtDateTime, fmtNumber, fmtRelative } from '../../lib/format';
import { useAddons } from '../../lib/queries';
import { rpc } from '../../lib/rpc';
import type { Entitlement, Role, UserDetail } from '../../lib/types';

const STEPS = ['profile', 'interview', 'placement', 'plan', 'done'] as const;

export function UserDrawer({ userId, onClose }: { userId: string | null; onClose: () => void }) {
  const q = useQuery({
    queryKey: ['user', userId],
    queryFn: () => rpc<UserDetail>('admin_get_user', { p_user: userId }),
    enabled: !!userId,
  });
  const d = q.data;
  const name = d ? d.profile.full_name || d.profile.username || d.auth.email || 'User' : 'User';

  return (
    <Modal open={!!userId} onClose={onClose} variant="drawer" title={d ? name : 'User'} description={d?.auth.email ?? undefined}>
      {q.error ? <ErrorState error={q.error} onRetry={() => void q.refetch()} /> : null}
      {!d ? q.isLoading ? <Spinner /> : null : <UserDetailBody d={d} />}
    </Modal>
  );
}

function UserDetailBody({ d }: { d: UserDetail }) {
  const p = d.profile;
  const name = p.full_name || p.username || 'User';
  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center gap-3">
        <Avatar name={name} url={p.avatar_url} size={48} />
        <div className="min-w-0 flex-1">
          <p className="font-semibold text-fg" lang={/[ঀ-৿]/.test(name) ? 'bn' : undefined}>
            {name}
          </p>
          <p className="text-sm text-muted">@{p.username ?? '—'}</p>
          <div className="mt-1 flex flex-wrap gap-1">
            <RoleBadge role={p.role} />
            {p.is_banned ? <Badge tone="danger">banned</Badge> : null}
            <Badge tone={p.onboarding_step === 'done' ? 'success' : 'neutral'}>onboarding: {p.onboarding_step}</Badge>
          </div>
        </div>
        <div className="flex items-center gap-1 text-xs text-muted">
          <code className="truncate">{p.id}</code>
          <CopyButton text={p.id} label="Copy user id" />
        </div>
      </div>

      <Card title="Profile">
        <KeyValue
          items={[
            [
              'E-mail',
              <>
                {d.auth.email ?? '—'}{' '}
                {d.auth.email_confirmed_at ? <Badge tone="success">confirmed</Badge> : <Badge tone="warning">unconfirmed</Badge>}
              </>,
            ],
            ['Joined', `${fmtDateTime(p.created_at)} (${fmtRelative(p.created_at)})`],
            [
              'Last sign-in',
              d.auth.last_sign_in_at ? `${fmtDateTime(d.auth.last_sign_in_at)} (${fmtRelative(d.auth.last_sign_in_at)})` : '—',
            ],
            ['Last active', p.last_active_date ? fmtDate(p.last_active_date) : '—'],
            ['Target exams', p.target_exams.join(', ') || '—'],
            ['Target schedule', d.target_schedule ? `${d.target_schedule.title_en} · ${fmtDate(d.target_schedule.expected_date)}` : '—'],
            ['District', p.district ? <span lang="bn">{p.district}</span> : '—'],
            ['Occupation', p.occupation ?? '—'],
            ['Language', p.locale === 'en' ? 'English' : 'বাংলা'],
            ['Study time', `${p.daily_study_minutes} min/day`],
            ['Streak', `${p.streak_count} days (best ${p.longest_streak})`],
            ['Friends · posts', `${fmtNumber(p.friends_count)} · ${fmtNumber(p.posts_count)}`],
            ['Sign-in provider', d.auth.provider ?? '—'],
            ['Auth ban', d.auth.banned_until ? `until ${fmtDate(d.auth.banned_until)}` : 'none'],
          ]}
        />
      </Card>

      <Card title="Learning">
        <KeyValue
          items={[
            ['Exams submitted', fmtNumber(d.exams.submitted)],
            [
              'By kind',
              Object.entries(d.exams.by_kind)
                .map(([k, n]) => `${k} ${n}`)
                .join(' · ') || '—',
            ],
            ['Average score', d.exams.avg_score_pct !== null ? `${d.exams.avg_score_pct}%` : '—'],
            ['Last exam', d.exams.last_submitted_at ? fmtRelative(d.exams.last_submitted_at) : '—'],
            ['Answers given', fmtNumber(d.attempts)],
            ['Study plan', d.plan ? `v${d.plan.version} · exam ${fmtDate(d.plan.exam_date)} · ${d.plan.daily_minutes} min/day` : 'none'],
            ['Reports', `${d.reports.against_open} open against · ${d.reports.filed} filed`],
          ]}
        />
      </Card>

      <EntitlementsCard d={d} />
      <UserActions d={d} />

      {d.payments.length || d.promo_redemptions.length ? (
        <Card title="Payments & promo codes">
          <ul className="space-y-1 text-sm">
            {d.payments.map((pay) => (
              <li key={pay.id} className="flex justify-between gap-2">
                <span>
                  {pay.addon_code} · ৳{pay.amount_bdt} · {pay.provider}
                </span>
                <span className="text-muted">
                  <Badge tone={pay.status === 'success' ? 'success' : pay.status === 'failed' ? 'danger' : 'neutral'}>{pay.status}</Badge>{' '}
                  {fmtDate(pay.created_at)}
                </span>
              </li>
            ))}
            {d.promo_redemptions.map((r) => (
              <li key={r.code} className="flex justify-between gap-2">
                <span>
                  Promo <code>{r.code}</code>
                </span>
                <span className="text-muted">{fmtDateTime(r.redeemed_at)}</span>
              </li>
            ))}
          </ul>
        </Card>
      ) : null}

      {d.audit.length ? (
        <Card title="Admin history">
          <ul className="space-y-1.5 text-sm">
            {d.audit.map((a) => (
              <li key={a.id} className="flex flex-wrap justify-between gap-2">
                <span>
                  <code className="text-xs">{a.action}</code> by @{a.actor ?? 'unknown'}
                </span>
                <span className="text-xs text-muted">{fmtDateTime(a.created_at)}</span>
              </li>
            ))}
          </ul>
        </Card>
      ) : null}
    </div>
  );
}

function useUserMutation<TArgs>(userId: string, fn: (args: TArgs) => Promise<unknown>, success: string) {
  const qc = useQueryClient();
  const toast = useToast();
  return useMutation({
    mutationFn: fn,
    onSuccess: () => {
      toast.success(success);
      void qc.invalidateQueries({ queryKey: ['user', userId] });
      void qc.invalidateQueries({ queryKey: ['users'] });
    },
    onError: (e) => toast.error(e),
  });
}

function EntitlementsCard({ d }: { d: UserDetail }) {
  const confirm = useConfirm();
  const revoke = useUserMutation<Entitlement>(
    d.profile.id,
    (e) => rpc('admin_revoke_entitlement', { p_entitlement: e.id, p_reason: 'Revoked in admin console' }),
    'Entitlement revoked.',
  );
  return (
    <Card title="Entitlements" pad={false}>
      {d.entitlements.length === 0 ? (
        <p className="p-4 text-sm text-muted">No add-ons.</p>
      ) : (
        <TableWrap>
          <table className="table-base">
            <thead>
              <tr>
                <th scope="col">Add-on</th>
                <th scope="col">Source</th>
                <th scope="col">Period</th>
                <th scope="col">
                  <span className="sr-only">Actions</span>
                </th>
              </tr>
            </thead>
            <tbody>
              {d.entitlements.map((e) => (
                <tr key={e.id}>
                  <td>
                    <p className="font-medium">{e.addon_name ?? e.addon_code}</p>
                    {e.active ? (
                      <Badge tone="success">active</Badge>
                    ) : e.upcoming ? (
                      <Badge tone="info">upcoming</Badge>
                    ) : (
                      <Badge>ended</Badge>
                    )}
                  </td>
                  <td>{e.source}</td>
                  <td className="text-xs whitespace-nowrap text-fg-2">
                    {fmtDate(e.starts_at)} → {fmtDate(e.expires_at)}
                  </td>
                  <td className="text-right">
                    {e.active || e.upcoming ? (
                      <Button
                        size="sm"
                        variant="danger-ghost"
                        icon={<Undo2 className="size-3.5" />}
                        loading={revoke.isPending && revoke.variables?.id === e.id}
                        onClick={async () => {
                          const ok = await confirm({
                            title: 'Revoke entitlement?',
                            message: `${e.addon_name ?? e.addon_code} (${e.source}) ${e.upcoming ? 'will be removed' : 'ends now'} for this user.`,
                            confirmLabel: 'Revoke',
                            tone: 'danger',
                          });
                          if (ok) revoke.mutate(e);
                        }}
                      >
                        Revoke
                      </Button>
                    ) : null}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </TableWrap>
      )}
    </Card>
  );
}

function UserActions({ d }: { d: UserDetail }) {
  const staff = useStaff();
  const confirm = useConfirm();
  const self = staff.id === d.profile.id;
  const addons = useAddons();
  const [role, setRole] = useState<Role>(d.profile.role);
  const [addon, setAddon] = useState('');
  const [days, setDays] = useState('30');
  const [step, setStep] = useState<(typeof STEPS)[number]>('profile');
  const [banOpen, setBanOpen] = useState(false);
  const [reason, setReason] = useState('');

  useEffect(() => setRole(d.profile.role), [d.profile.role]);
  useEffect(() => {
    if (!addon && addons.data?.addons[0]) setAddon(addons.data.addons[0].code);
  }, [addon, addons.data]);

  const id = d.profile.id;
  const setRoleM = useUserMutation<Role>(id, (r) => rpc('admin_change_role', { p_user: id, p_role: r }), 'Role updated.');
  const banM = useUserMutation<{ banned: boolean; reason: string }>(
    id,
    (a) => rpc('admin_set_ban', { p_user: id, p_banned: a.banned, p_reason: a.reason || null }),
    d.profile.is_banned ? 'User unbanned.' : 'User banned and signed out.',
  );
  const grantM = useUserMutation<void>(
    id,
    () => rpc('admin_user_grant_addon', { p_user: id, p_addon: addon, p_days: Number(days) }),
    'Add-on granted.',
  );
  const stepM = useUserMutation<void>(id, () => rpc('admin_reset_onboarding', { p_user: id, p_step: step }), 'Onboarding step updated.');
  const daysValid = /^\d+$/.test(days) && Number(days) >= 1 && Number(days) <= 3650;

  return (
    <Card title="Actions">
      <div className="space-y-5">
        <div className="flex flex-wrap items-end gap-2">
          <Field
            label="Role"
            htmlFor="u-role"
            hint={self ? "You can't change your own role." : 'Moderators can review questions and reports.'}
            className="min-w-44 flex-1"
          >
            <Select id="u-role" value={role} disabled={self} onChange={(e) => setRole(e.target.value as Role)}>
              <option value="user">User</option>
              <option value="moderator">Moderator</option>
              <option value="admin">Admin</option>
            </Select>
          </Field>
          <Button
            icon={<ShieldCheck className="size-4" />}
            disabled={self || role === d.profile.role}
            loading={setRoleM.isPending}
            onClick={async () => {
              const ok = await confirm({
                title: `Make this user ${role}?`,
                message: role === 'admin' ? 'Admins can change every setting, grant add-ons and manage other staff.' : undefined,
                confirmLabel: 'Change role',
                tone: role === 'admin' ? 'danger' : 'primary',
              });
              if (ok) setRoleM.mutate(role);
            }}
          >
            Save role
          </Button>
        </div>

        <div className="flex flex-wrap items-end gap-2">
          <Field label="Grant add-on" htmlFor="u-addon" className="min-w-44 flex-1">
            <Select id="u-addon" value={addon} onChange={(e) => setAddon(e.target.value)} disabled={!addons.data}>
              {addons.data?.addons.map((a) => (
                <option key={a.code} value={a.code}>
                  {a.name_en}
                  {a.is_active ? '' : ' (inactive)'}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Days" htmlFor="u-days" className="w-24" error={daysValid ? null : '1–3650'}>
            <Input id="u-days" inputMode="numeric" value={days} aria-invalid={!daysValid} onChange={(e) => setDays(e.target.value)} />
          </Field>
          <Button
            icon={<Gift className="size-4" />}
            disabled={!addon || !daysValid}
            loading={grantM.isPending}
            onClick={() => grantM.mutate()}
          >
            Grant
          </Button>
        </div>

        <div className="flex flex-wrap items-end gap-2">
          <Field
            label="Onboarding step"
            htmlFor="u-step"
            hint={`Currently "${d.profile.onboarding_step}". The app resumes onboarding from this step.`}
            className="min-w-44 flex-1"
          >
            <Select id="u-step" value={step} onChange={(e) => setStep(e.target.value as (typeof STEPS)[number])}>
              {STEPS.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </Select>
          </Field>
          <Button icon={<RotateCcw className="size-4" />} loading={stepM.isPending} onClick={() => stepM.mutate()}>
            Set step
          </Button>
        </div>

        <div className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-danger/30 p-3">
          <div className="text-sm">
            <p className="font-medium text-fg">{d.profile.is_banned ? 'This user is banned' : 'Ban user'}</p>
            <p className="text-xs text-muted">
              {d.profile.is_banned
                ? 'Unbanning restores sign-in.'
                : 'Blocks sign-in, ends every session and stops notifications. Admins must be demoted first.'}
            </p>
          </div>
          {d.profile.is_banned ? (
            <Button icon={<Undo2 className="size-4" />} loading={banM.isPending} onClick={() => banM.mutate({ banned: false, reason: '' })}>
              Unban
            </Button>
          ) : (
            <Button
              variant="danger"
              icon={<Ban className="size-4" />}
              disabled={self || d.profile.role === 'admin'}
              onClick={() => setBanOpen(true)}
            >
              Ban…
            </Button>
          )}
        </div>
      </div>
      <Modal
        open={banOpen}
        onClose={() => setBanOpen(false)}
        title="Ban this user?"
        size="sm"
        footer={
          <>
            <Button variant="ghost" onClick={() => setBanOpen(false)}>
              Cancel
            </Button>
            <Button
              variant="danger"
              loading={banM.isPending}
              onClick={() =>
                banM.mutate(
                  { banned: true, reason },
                  {
                    onSuccess: () => {
                      setBanOpen(false);
                      setReason('');
                    },
                  },
                )
              }
            >
              Ban user
            </Button>
          </>
        }
      >
        <Field label="Reason (kept in the audit log)" htmlFor="ban-reason">
          <Textarea
            id="ban-reason"
            value={reason}
            maxLength={500}
            onChange={(e) => setReason(e.target.value)}
            placeholder="e.g. spam in community feed"
          />
        </Field>
      </Modal>
    </Card>
  );
}
