import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Bell, Megaphone, Send, Users } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { useConfirm, useToast } from '../components/feedback';
import { Badge, Button, Card, ErrorState, Field, Input, Notice, PageHeader, Select, Spinner, Switch, Textarea } from '../components/ui';
import { useExamTypes } from '../lib/catalog';
import { describeError, toApiError } from '../lib/errors';
import { fmtDateTime, fmtNumber } from '../lib/format';
import { useDebounced, usePageTitle } from '../lib/hooks';
import { rpc } from '../lib/rpc';
import { supabase } from '../lib/supabase';
import type { AuditRow, BroadcastSegments } from '../lib/types';

const ROUTES = [
  { value: '', label: 'Nothing (just show the message)' },
  { value: '/notes', label: "Today's notes" },
  { value: '/daily-exam', label: 'Daily exam' },
  { value: '/leaderboard', label: 'Leaderboard' },
  { value: '/plan', label: 'Study plan' },
  { value: '/progress', label: 'Progress' },
  { value: '/exams/model-tests', label: 'Model tests' },
  { value: '/question-bank', label: 'Question bank' },
  { value: '/addons', label: 'Add-ons store' },
  { value: '/community', label: 'Community' },
  { value: 'custom', label: 'Custom path…' },
];

interface Segment {
  target_exam: string;
  district: string;
  locale: string;
  active_days: string;
}

export default function BroadcastPage() {
  usePageTitle('Broadcast');
  const qc = useQueryClient();
  const toast = useToast();
  const confirm = useConfirm();
  const examTypes = useExamTypes();
  const segments = useQuery({
    queryKey: ['broadcast-segments'],
    queryFn: () => rpc<BroadcastSegments>('admin_broadcast_segments'),
    staleTime: 60_000,
  });
  const history = useQuery({
    queryKey: ['broadcast-history'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('admin_audit_log')
        .select('id, actor_id, action, target_type, target_id, details, created_at, actor:profiles(username, full_name)')
        .eq('action', 'broadcast.send')
        .order('id', { ascending: false })
        .limit(20);
      if (error) throw toApiError(error);
      return (data ?? []) as unknown as AuditRow[];
    },
  });

  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [titleEn, setTitleEn] = useState('');
  const [bodyEn, setBodyEn] = useState('');
  const [routeChoice, setRouteChoice] = useState('');
  const [customRoute, setCustomRoute] = useState('');
  const [push, setPush] = useState(true);
  const [seg, setSeg] = useState<Segment>({ target_exam: '', district: '', locale: '', active_days: '30' });
  const [clientKey, setClientKey] = useState(() => crypto.randomUUID());

  const route = routeChoice === 'custom' ? customRoute.trim() : routeChoice;
  const segment = useMemo(() => {
    const s: Record<string, unknown> = {};
    if (seg.target_exam) s.target_exam = seg.target_exam;
    if (seg.district) s.district = seg.district;
    if (seg.locale) s.locale = seg.locale;
    if (seg.active_days) s.active_days = Number(seg.active_days);
    return s;
  }, [seg]);
  const settledSegment = useDebounced(segment, 250);
  const audience = useQuery({
    queryKey: ['broadcast-audience', settledSegment, push],
    queryFn: () =>
      rpc<{ recipients: number; pushes: number }>('admin_broadcast', {
        p_title: 'preview',
        p_body: 'preview',
        p_segment: settledSegment,
        p_send_push: push,
        p_dry_run: true,
      }),
  });

  const errors = {
    title: title.trim().length === 0 ? 'Required' : title.length > 120 ? 'At most 120 characters' : null,
    body: body.trim().length === 0 ? 'Required' : body.length > 1000 ? 'At most 1000 characters' : null,
    en: !!titleEn.trim() !== !!bodyEn.trim() ? 'Give both English title and body, or neither' : null,
    route: route && (!/^\/[A-Za-z0-9/_-]*(\?[A-Za-z0-9=&_-]*)?$/.test(route) || route.length > 200) ? 'An app path like /notes' : null,
  };
  const valid = !Object.values(errors).some(Boolean);

  const send = useMutation({
    mutationFn: () =>
      rpc<{ recipients: number; pushes: number }>('admin_broadcast', {
        p_title: title.trim(),
        p_body: body.trim(),
        p_title_en: titleEn.trim() || null,
        p_body_en: bodyEn.trim() || null,
        p_route: route || null,
        p_segment: segment,
        p_send_push: push,
        p_dry_run: false,
        p_client_key: clientKey,
      }),
    onSuccess: (r) => {
      toast.success(`Sent to ${fmtNumber(r.recipients)} users (${fmtNumber(r.pushes)} push notifications queued).`);
      setTitle('');
      setBody('');
      setTitleEn('');
      setBodyEn('');
      setClientKey(crypto.randomUUID());
      void qc.invalidateQueries({ queryKey: ['broadcast-history'] });
    },
  });
  useEffect(() => {
    if (send.isError) setClientKey(crypto.randomUUID());
  }, [send.isError]);

  async function submit() {
    const n = audience.data?.recipients ?? 0;
    const ok = await confirm({
      title: `Send to ${fmtNumber(n)} user${n === 1 ? '' : 's'}?`,
      message: (
        <>
          <p>
            Every recipient gets an in-app notification{push ? ' and, if they allow it, a push notification' : ''}. This cannot be recalled.
          </p>
          {n >= 1000 ? <p className="mt-2 font-medium">This is a large audience.</p> : null}
        </>
      ),
      confirmLabel: 'Send now',
      tone: 'danger',
      typeToConfirm: n >= 1000 ? 'SEND' : undefined,
    });
    if (ok) send.mutate();
  }

  return (
    <div>
      <PageHeader
        title="Broadcast"
        description="Send an in-app notification (and push) to everyone or a segment. Limited to 5 sends per hour per admin; every send is audited."
      />
      <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_22rem]">
        <div className="space-y-5">
          <Card title="Message">
            <div className="grid gap-4 md:grid-cols-2">
              <div className="space-y-3">
                <Field label="Title (বাংলা)" htmlFor="bc-title" error={title ? errors.title : null} hint={`${title.length}/120`}>
                  <Input id="bc-title" lang="bn" value={title} onChange={(e) => setTitle(e.target.value)} maxLength={120} />
                </Field>
                <Field label="Body (বাংলা)" htmlFor="bc-body" error={body ? errors.body : null} hint={`${body.length}/1000`}>
                  <Textarea id="bc-body" lang="bn" rows={4} value={body} onChange={(e) => setBody(e.target.value)} maxLength={1000} />
                </Field>
              </div>
              <div className="space-y-3">
                <Field label="Title (English, optional)" htmlFor="bc-title-en" error={errors.en}>
                  <Input id="bc-title-en" value={titleEn} onChange={(e) => setTitleEn(e.target.value)} maxLength={120} />
                </Field>
                <Field label="Body (English, optional)" htmlFor="bc-body-en" hint="Users with the app in English see this version.">
                  <Textarea id="bc-body-en" rows={4} value={bodyEn} onChange={(e) => setBodyEn(e.target.value)} maxLength={1000} />
                </Field>
              </div>
            </div>
            <div className="mt-4 grid gap-3 md:grid-cols-2">
              <Field label="Opens when tapped" htmlFor="bc-route" hint="Stored as data.route on the notification.">
                <Select id="bc-route" value={routeChoice} onChange={(e) => setRouteChoice(e.target.value)}>
                  {ROUTES.map((r) => (
                    <option key={r.value} value={r.value}>
                      {r.label}
                    </option>
                  ))}
                </Select>
              </Field>
              {routeChoice === 'custom' ? (
                <Field label="App path" htmlFor="bc-custom" error={errors.route}>
                  <Input id="bc-custom" value={customRoute} placeholder="/notes" onChange={(e) => setCustomRoute(e.target.value)} />
                </Field>
              ) : null}
            </div>
            <div className="mt-4">
              <Switch
                checked={push}
                onChange={setPush}
                label="Also send a push notification"
                description="Respects each user's announcement setting."
              />
            </div>
          </Card>

          <Card title="Audience">
            {segments.error ? <ErrorState compact error={segments.error} /> : null}
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <Field label="Target exam" htmlFor="bc-exam">
                <Select id="bc-exam" value={seg.target_exam} onChange={(e) => setSeg({ ...seg, target_exam: e.target.value })}>
                  <option value="">Everyone</option>
                  {(segments.data?.target_exams ?? examTypes.data?.map((t) => ({ code: t.code, name_en: t.name_en, users: 0 })) ?? []).map(
                    (t) => (
                      <option key={t.code} value={t.code}>
                        {t.name_en}
                        {segments.data ? ` (${fmtNumber(t.users)})` : ''}
                      </option>
                    ),
                  )}
                </Select>
              </Field>
              <Field label="District" htmlFor="bc-district">
                <Select id="bc-district" value={seg.district} onChange={(e) => setSeg({ ...seg, district: e.target.value })} lang="bn">
                  <option value="">All districts</option>
                  {segments.data?.districts.map((d) => (
                    <option key={d.district} value={d.district}>
                      {d.district} ({fmtNumber(d.users)})
                    </option>
                  ))}
                </Select>
              </Field>
              <Field label="App language" htmlFor="bc-locale">
                <Select id="bc-locale" value={seg.locale} onChange={(e) => setSeg({ ...seg, locale: e.target.value })}>
                  <option value="">Any</option>
                  <option value="bn">বাংলা ({fmtNumber(segments.data?.locales.bn ?? 0)})</option>
                  <option value="en">English ({fmtNumber(segments.data?.locales.en ?? 0)})</option>
                </Select>
              </Field>
              <Field label="Active within" htmlFor="bc-days" hint="Or joined within that window">
                <Select id="bc-days" value={seg.active_days} onChange={(e) => setSeg({ ...seg, active_days: e.target.value })}>
                  <option value="">Any time</option>
                  <option value="7">7 days</option>
                  <option value="30">30 days</option>
                  <option value="90">90 days</option>
                  <option value="365">1 year</option>
                </Select>
              </Field>
            </div>
            <div
              className="mt-4 flex flex-wrap items-center gap-3 rounded-lg bg-surface-2 px-3 py-2.5 text-sm"
              role="status"
              aria-live="polite"
            >
              <Users className="size-4 text-muted" aria-hidden />
              {audience.isLoading ? (
                <span className="text-muted">Counting…</span>
              ) : audience.error ? (
                <span className="text-danger">{describeError(audience.error)}</span>
              ) : (
                <span>
                  <strong>{fmtNumber(audience.data?.recipients ?? 0)}</strong> recipients · {fmtNumber(audience.data?.pushes ?? 0)} push
                  notifications
                  {segments.data ? <span className="text-muted"> (of {fmtNumber(segments.data.total)} users, banned excluded)</span> : null}
                </span>
              )}
            </div>
          </Card>

          {send.error ? <Notice tone="danger">{describeError(send.error)}</Notice> : null}
          <div className="flex justify-end">
            <Button
              variant="primary"
              icon={<Send className="size-4" />}
              disabled={!valid || !audience.data?.recipients}
              loading={send.isPending}
              onClick={() => void submit()}
            >
              Send broadcast
            </Button>
          </div>
        </div>

        <div className="space-y-5">
          <Card title="Preview">
            <div className="space-y-3">
              <PhonePreview title={title || 'শিরোনাম'} body={body || 'বার্তার মূল অংশ এখানে দেখা যাবে।'} lang="bn" />
              {titleEn || bodyEn ? <PhonePreview title={titleEn || 'Title'} body={bodyEn || 'Body'} lang="en" /> : null}
            </div>
          </Card>
          <Card title="Recent broadcasts" pad={false}>
            {history.error ? <ErrorState compact error={history.error} /> : null}
            {history.isLoading ? (
              <Spinner />
            ) : history.data?.length ? (
              <ul className="divide-y divide-line">
                {history.data.map((h) => (
                  <li key={h.id} className="px-4 py-2.5 text-sm">
                    <p className="font-medium" lang="bn">
                      {String(h.details.title ?? '')}
                    </p>
                    <p className="text-xs text-muted">
                      {fmtNumber(Number(h.details.recipients ?? 0))} recipients · {fmtDateTime(h.created_at)} · @{h.actor?.username ?? '—'}
                    </p>
                  </li>
                ))}
              </ul>
            ) : (
              <p className="p-4 text-sm text-muted">No broadcasts yet.</p>
            )}
          </Card>
        </div>
      </div>
    </div>
  );
}

function PhonePreview({ title, body, lang }: { title: string; body: string; lang: 'bn' | 'en' }) {
  return (
    <div className="rounded-2xl border border-line bg-surface-2 p-3" aria-label={`${lang === 'bn' ? 'Bangla' : 'English'} preview`}>
      <div className="flex items-start gap-2.5 rounded-xl bg-surface p-3 shadow-card">
        <span className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-brand text-brand-fg">
          <Bell className="size-4" aria-hidden />
        </span>
        <div className="min-w-0" lang={lang === 'bn' ? 'bn' : undefined}>
          <p className="flex items-center gap-1.5 text-xs text-muted" lang="en">
            Prostuti · now <Badge icon={<Megaphone className="size-3" />}>{lang}</Badge>
          </p>
          <p className="truncate text-sm font-semibold text-fg">{title}</p>
          <p className="line-clamp-3 text-sm text-fg-2">{body}</p>
        </div>
      </div>
    </div>
  );
}
