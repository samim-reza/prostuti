import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { AlertTriangle, CheckCircle2, Save } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { useToast } from '../components/feedback';
import {
  Badge,
  Button,
  Card,
  cx,
  EmptyState,
  ErrorState,
  Field,
  Input,
  Notice,
  PageHeader,
  Spinner,
  Switch,
  TableWrap,
  Textarea,
} from '../components/ui';
import { useSubjects } from '../lib/catalog';
import { describeError } from '../lib/errors';
import { fmtDateTime, fmtNumber } from '../lib/format';
import { usePageTitle } from '../lib/hooks';
import { rpc } from '../lib/rpc';
import { trackLabel, type ExamTrack } from '../lib/types';

export default function TracksPage() {
  usePageTitle('Exam tracks');
  const q = useQuery({ queryKey: ['tracks'], queryFn: () => rpc<ExamTrack[]>('admin_list_exam_tracks') });
  return (
    <div>
      <PageHeader
        title="Exam tracks"
        description='Model-test patterns per track. A question belongs to a track when its tags contain the track code ("govt" is shown as "Others" in the app).'
      />
      {q.error ? <ErrorState error={q.error} onRetry={() => void q.refetch()} /> : null}
      {q.isLoading ? (
        <Spinner />
      ) : !q.data?.length ? (
        <Card>
          <EmptyState title="No exam tracks">Exam tracks arrive with migration 0016.</EmptyState>
        </Card>
      ) : (
        <div className="space-y-5">
          {q.data.map((t) => (
            <TrackEditor key={t.code} track={t} />
          ))}
        </div>
      )}
    </div>
  );
}

function TrackEditor({ track }: { track: ExamTrack }) {
  const qc = useQueryClient();
  const toast = useToast();
  const subjects = useSubjects();
  const [nameBn, setNameBn] = useState(track.name_bn);
  const [nameEn, setNameEn] = useState(track.name_en);
  const [descBn, setDescBn] = useState(track.description_bn ?? '');
  const [descEn, setDescEn] = useState(track.description_en ?? '');
  const [sizes, setSizes] = useState(track.sizes.join(', '));
  const [fullMarks, setFullMarks] = useState(String(track.full_marks));
  const [neg, setNeg] = useState(String(track.negative_mark));
  const [secs, setSecs] = useState(String(track.seconds_per_question));
  const [active, setActive] = useState(track.is_active);
  const [dist, setDist] = useState<Record<string, string>>(() =>
    Object.fromEntries(Object.entries(track.distribution).map(([k, v]) => [k, String(v)])),
  );

  useEffect(() => {
    setDist(Object.fromEntries(Object.entries(track.distribution).map(([k, v]) => [k, String(v)])));
  }, [track.distribution]);

  const parsedSizes = sizes
    .split(/[,\s]+/)
    .filter(Boolean)
    .map((x) => Number(x));
  const full = Number(fullMarks);
  const sum = Object.values(dist).reduce((s, v) => s + (Number(v) || 0), 0);
  const errors = useMemo(() => {
    const e: Record<string, string> = {};
    if (!nameBn.trim() || !nameEn.trim()) e.name = 'Both names are required.';
    if (!parsedSizes.length || parsedSizes.length > 6 || parsedSizes.some((n) => !Number.isInteger(n) || n < 5 || n > 300))
      e.sizes = '1–6 whole numbers between 5 and 300.';
    else if (new Set(parsedSizes).size !== parsedSizes.length) e.sizes = 'Sizes must be distinct.';
    if (!Number.isInteger(full) || full < 10 || full > 300) e.full = '10–300.';
    const n = Number(neg);
    if (!/^\d(\.\d{1,2})?$/.test(neg) || n > 1) e.neg = '0–1, two decimals.';
    const s = Number(secs);
    if (!Number.isInteger(s) || s < 10 || s > 180) e.secs = '10–180 seconds.';
    if (Object.entries(dist).some(([, v]) => v !== '' && (!/^\d+$/.test(v) || Number(v) < 1)))
      e.dist = 'Marks must be whole numbers ≥ 1 (empty = not included).';
    else if (sum !== full) e.dist = `Distribution sums to ${sum}, but full marks is ${Number.isFinite(full) ? full : '?'}.`;
    return e;
  }, [nameBn, nameEn, parsedSizes, full, neg, secs, dist, sum]);

  const save = useMutation({
    mutationFn: () =>
      rpc<ExamTrack>('admin_save_exam_track', {
        p_code: track.code,
        p_track: {
          name_bn: nameBn.trim(),
          name_en: nameEn.trim(),
          description_bn: descBn.trim() || null,
          description_en: descEn.trim() || null,
          sizes: parsedSizes,
          full_marks: full,
          negative_mark: Number(neg),
          seconds_per_question: Number(secs),
          distribution: Object.fromEntries(
            Object.entries(dist)
              .filter(([, v]) => v !== '')
              .map(([k, v]) => [k, Number(v)]),
          ),
          is_active: active,
        },
      }),
    onSuccess: () => {
      toast.success(`${track.name_en} saved.`);
      void qc.invalidateQueries({ queryKey: ['tracks'] });
    },
  });
  const valid = Object.keys(errors).length === 0;
  const avgSecsTotal = parsedSizes.length ? Math.max(...parsedSizes) * (Number(secs) || 0) : 0;

  return (
    <Card
      title={
        <span className="flex items-center gap-2">
          {track.name_en} <Badge>{trackLabel(track.code)}</Badge> {active ? null : <Badge tone="warning">inactive</Badge>}
        </span>
      }
      actions={
        <Button
          variant="primary"
          size="sm"
          icon={<Save className="size-3.5" />}
          disabled={!valid}
          loading={save.isPending}
          onClick={() => save.mutate()}
        >
          Save
        </Button>
      }
    >
      <div className="grid gap-5 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)]">
        <div className="space-y-3">
          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="Name (বাংলা)" htmlFor={`t-${track.code}-nbn`} error={errors.name}>
              <Input id={`t-${track.code}-nbn`} lang="bn" value={nameBn} onChange={(e) => setNameBn(e.target.value)} />
            </Field>
            <Field label="Name (English)" htmlFor={`t-${track.code}-nen`}>
              <Input id={`t-${track.code}-nen`} value={nameEn} onChange={(e) => setNameEn(e.target.value)} />
            </Field>
          </div>
          <Field label="Description (বাংলা)" htmlFor={`t-${track.code}-dbn`}>
            <Textarea
              id={`t-${track.code}-dbn`}
              lang="bn"
              rows={2}
              maxLength={500}
              value={descBn}
              onChange={(e) => setDescBn(e.target.value)}
            />
          </Field>
          <Field label="Description (English)" htmlFor={`t-${track.code}-den`}>
            <Textarea id={`t-${track.code}-den`} rows={2} maxLength={500} value={descEn} onChange={(e) => setDescEn(e.target.value)} />
          </Field>
          <div className="grid gap-3 sm:grid-cols-2">
            <Field
              label="Model-test sizes"
              htmlFor={`t-${track.code}-sizes`}
              error={errors.sizes}
              hint="Questions per test, e.g. 25, 50, 100, 200"
            >
              <Input id={`t-${track.code}-sizes`} value={sizes} onChange={(e) => setSizes(e.target.value)} />
            </Field>
            <Field label="Full marks" htmlFor={`t-${track.code}-full`} error={errors.full} hint="Distribution must add up to this">
              <Input id={`t-${track.code}-full`} inputMode="numeric" value={fullMarks} onChange={(e) => setFullMarks(e.target.value)} />
            </Field>
            <Field label="Negative mark per wrong answer" htmlFor={`t-${track.code}-neg`} error={errors.neg}>
              <Input id={`t-${track.code}-neg`} inputMode="decimal" value={neg} onChange={(e) => setNeg(e.target.value)} />
            </Field>
            <Field
              label="Seconds per question"
              htmlFor={`t-${track.code}-secs`}
              error={errors.secs}
              hint={avgSecsTotal ? `Largest test: ${Math.round(avgSecsTotal / 60)} min` : undefined}
            >
              <Input id={`t-${track.code}-secs`} inputMode="numeric" value={secs} onChange={(e) => setSecs(e.target.value)} />
            </Field>
          </div>
          <Switch checked={active} onChange={setActive} label="Active" description="Inactive tracks are hidden in the app." />
          {save.error ? (
            <p role="alert" className="text-sm text-danger">
              {describeError(save.error)}
            </p>
          ) : null}
          {track.updated_at ? <p className="text-xs text-muted">Last updated {fmtDateTime(track.updated_at)}</p> : null}
        </div>

        <div>
          <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
            <p className="text-[0.8125rem] font-medium text-fg-2">Marks per subject</p>
            <p
              className={cx('flex items-center gap-1.5 text-sm font-medium', sum === full ? 'text-success' : 'text-danger')}
              role="status"
              aria-live="polite"
            >
              {sum === full ? <CheckCircle2 className="size-4" aria-hidden /> : <AlertTriangle className="size-4" aria-hidden />}
              {sum} / {Number.isFinite(full) ? full : '?'}
            </p>
          </div>
          <TableWrap className="rounded-lg border border-line">
            <table className="table-base [&_td]:align-middle [&_th]:align-middle">
              <thead>
                <tr>
                  <th scope="col">Subject</th>
                  <th scope="col" className="w-28">
                    Marks
                  </th>
                  <th scope="col" className="text-right">
                    Share
                  </th>
                  <th scope="col" className="text-right">
                    Questions in track
                  </th>
                </tr>
              </thead>
              <tbody>
                {(subjects.data ?? []).map((s) => {
                  const v = dist[s.code] ?? '';
                  const marks = Number(v) || 0;
                  const avail = track.available[s.code] ?? 0;
                  const largest = parsedSizes.length ? Math.max(...parsedSizes) : 0;
                  const need = full > 0 ? Math.ceil((marks / full) * largest) : 0;
                  return (
                    <tr key={s.code}>
                      <th scope="row">
                        {s.name_en}
                        <span className="block text-xs font-normal text-muted" lang="bn">
                          {s.name_bn}
                        </span>
                      </th>
                      <td>
                        <Input
                          aria-label={`${s.name_en} marks`}
                          inputMode="numeric"
                          className="h-8 w-20"
                          value={v}
                          placeholder="—"
                          onChange={(e) => setDist((prev) => ({ ...prev, [s.code]: e.target.value.trim() }))}
                        />
                      </td>
                      <td className="num text-right text-xs text-muted">{marks && full ? `${Math.round((marks / full) * 100)}%` : ''}</td>
                      <td className="num text-right text-xs">
                        <span className={marks && avail < need ? 'text-warning' : 'text-fg-2'}>{fmtNumber(avail)}</span>
                        {marks && avail < need ? <span className="block text-warning">needs ~{need}</span> : null}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </TableWrap>
          {errors.dist ? (
            <Notice tone="danger" icon={<AlertTriangle className="size-4" />}>
              {errors.dist}
            </Notice>
          ) : null}
        </div>
      </div>
    </Card>
  );
}
