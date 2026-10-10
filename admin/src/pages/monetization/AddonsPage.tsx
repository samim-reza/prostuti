import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Pencil, Plus } from 'lucide-react';
import { useState } from 'react';
import { useToast } from '../../components/feedback';
import { Modal } from '../../components/Modal';
import {
  Badge,
  Button,
  Card,
  Checkbox,
  EmptyState,
  ErrorState,
  Field,
  Input,
  PageHeader,
  Spinner,
  Switch,
  TableWrap,
  Textarea,
} from '../../components/ui';
import { describeError } from '../../lib/errors';
import { fmtBdt, fmtNumber } from '../../lib/format';
import { usePageTitle } from '../../lib/hooks';
import { useAddons } from '../../lib/queries';
import { rpc } from '../../lib/rpc';
import type { Addon, Feature } from '../../lib/types';

export default function AddonsPage() {
  usePageTitle('Add-ons');
  const q = useAddons();
  const [editing, setEditing] = useState<{ addon: Addon | null } | null>(null);
  const [featureEdit, setFeatureEdit] = useState<Feature | null>(null);

  return (
    <div>
      <PageHeader
        title="Add-ons"
        description="Every premium capability is a feature; add-ons bundle features with a price. Changes apply without an app release."
        actions={
          <Button variant="primary" icon={<Plus className="size-4" />} onClick={() => setEditing({ addon: null })}>
            New add-on
          </Button>
        }
      />
      {q.error ? <ErrorState error={q.error} onRetry={() => void q.refetch()} /> : null}
      {q.isLoading ? (
        <Spinner />
      ) : q.data ? (
        <div className="space-y-6">
          <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
            {q.data.addons.map((a) => {
              const active = Object.values(a.active).reduce((s, n) => s + n, 0);
              return (
                <Card key={a.code} className={a.is_active ? undefined : 'opacity-70'}>
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="size-3 shrink-0 rounded-full" style={{ background: a.color ?? 'var(--muted)' }} aria-hidden />
                        <p className="truncate font-semibold">{a.name_en}</p>
                      </div>
                      <p className="text-sm text-muted" lang="bn">
                        {a.name_bn}
                      </p>
                    </div>
                    <Button size="sm" variant="ghost" icon={<Pencil className="size-3.5" />} onClick={() => setEditing({ addon: a })}>
                      Edit
                    </Button>
                  </div>
                  <p className="mt-3 text-2xl font-semibold">
                    {fmtBdt(a.price_bdt)} <span className="text-sm font-normal text-muted">/ {a.period_days} days</span>
                  </p>
                  <div className="mt-2 flex flex-wrap gap-1">
                    {a.is_active ? <Badge tone="success">on sale</Badge> : <Badge>inactive</Badge>}
                    {a.trial_days ? <Badge tone="info">{a.trial_days}-day trial</Badge> : null}
                    {a.badge ? <Badge tone="brand">{a.badge}</Badge> : null}
                    <code className="text-xs text-muted">{a.code}</code>
                  </div>
                  <ul className="mt-3 flex flex-wrap gap-1">
                    {a.features.map((f) => (
                      <li key={f}>
                        <Badge>{q.data.features.find((x) => x.code === f)?.name_en ?? f}</Badge>
                      </li>
                    ))}
                  </ul>
                  <p className="mt-3 text-xs text-muted">
                    {fmtNumber(active)} active entitlement{active === 1 ? '' : 's'}
                    {Object.keys(a.active).length
                      ? ` (${Object.entries(a.active)
                          .map(([k, n]) => `${k} ${n}`)
                          .join(', ')})`
                      : ''}{' '}
                    · revenue 30 d {fmtBdt(a.revenue_30d_bdt)}
                  </p>
                </Card>
              );
            })}
          </div>

          <Card title="Features" pad={false}>
            <TableWrap>
              <table className="table-base">
                <thead>
                  <tr>
                    <th scope="col">Feature</th>
                    <th scope="col">Access</th>
                    <th scope="col">Free daily quota</th>
                    <th scope="col">In add-ons</th>
                    <th scope="col">
                      <span className="sr-only">Edit</span>
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {q.data.features.map((f) => (
                    <tr key={f.code}>
                      <td>
                        <p className="font-medium">{f.name_en}</p>
                        <p className="text-xs text-muted">
                          <code>{f.code}</code> · <span lang="bn">{f.name_bn}</span>
                        </p>
                      </td>
                      <td>{f.is_free ? <Badge tone="success">free</Badge> : <Badge tone="brand">paid</Badge>}</td>
                      <td className="text-sm">{f.is_free ? '—' : f.free_daily_quota ? `${f.free_daily_quota} / day free` : 'none'}</td>
                      <td className="text-xs text-fg-2">
                        {q.data.addons
                          .filter((a) => a.features.includes(f.code))
                          .map((a) => a.name_en)
                          .join(', ') || '—'}
                      </td>
                      <td className="text-right">
                        <Button size="sm" variant="ghost" icon={<Pencil className="size-3.5" />} onClick={() => setFeatureEdit(f)}>
                          Edit
                        </Button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </TableWrap>
          </Card>
        </div>
      ) : (
        <EmptyState title="No add-ons" />
      )}
      {editing && q.data ? <AddonEditor addon={editing.addon} features={q.data.features} onClose={() => setEditing(null)} /> : null}
      {featureEdit ? <FeatureEditor feature={featureEdit} onClose={() => setFeatureEdit(null)} /> : null}
    </div>
  );
}

function AddonEditor({ addon, features, onClose }: { addon: Addon | null; features: Feature[]; onClose: () => void }) {
  const qc = useQueryClient();
  const toast = useToast();
  const [code, setCode] = useState(addon?.code ?? '');
  const [d, setD] = useState({
    name_bn: addon?.name_bn ?? '',
    name_en: addon?.name_en ?? '',
    description_bn: addon?.description_bn ?? '',
    description_en: addon?.description_en ?? '',
    features: addon?.features ?? [],
    price_bdt: String(addon?.price_bdt ?? ''),
    period_days: String(addon?.period_days ?? 30),
    trial_days: String(addon?.trial_days ?? 0),
    badge: addon?.badge ?? '',
    color: addon?.color ?? '#006A4E',
    icon: addon?.icon ?? '',
    is_active: addon?.is_active ?? false,
    sort: String(addon?.sort ?? 0),
  });
  const errors = {
    code: !addon && !/^[a-z][a-z0-9_]{1,39}$/.test(code) ? 'lowercase letters, digits and _ (2–40)' : null,
    name: !d.name_bn.trim() || !d.name_en.trim() ? 'Both names are required' : null,
    features: d.features.length === 0 ? 'Pick at least one feature' : null,
    price: !/^\d{1,6}(\.\d{1,2})?$/.test(d.price_bdt) ? 'A price in taka' : null,
    period: !/^\d+$/.test(d.period_days) || Number(d.period_days) < 1 || Number(d.period_days) > 3650 ? '1–3650' : null,
    trial: !/^\d+$/.test(d.trial_days) || Number(d.trial_days) > 90 ? '0–90' : null,
    color: d.color && !/^#[0-9A-Fa-f]{6}$/.test(d.color) ? '#RRGGBB' : null,
    icon: d.icon && !/^[a-z0-9_]{1,40}$/.test(d.icon) ? 'Material icon name, e.g. quiz' : null,
  };
  const save = useMutation({
    mutationFn: () =>
      rpc<Addon>('admin_save_addon', {
        p_code: addon?.code ?? code,
        p_create: !addon,
        p_addon: {
          ...d,
          price_bdt: Number(d.price_bdt),
          period_days: Number(d.period_days),
          trial_days: Number(d.trial_days),
          sort: Number(d.sort) || 0,
          badge: d.badge.trim() || null,
          icon: d.icon.trim() || null,
          color: d.color || null,
        },
      }),
    onSuccess: () => {
      toast.success(addon ? 'Add-on saved.' : 'Add-on created.');
      void qc.invalidateQueries({ queryKey: ['addons'] });
      onClose();
    },
  });
  const invalid = Object.values(errors).some(Boolean);
  return (
    <Modal
      open
      onClose={onClose}
      size="lg"
      title={addon ? `Edit ${addon.name_en}` : 'New add-on'}
      description={addon ? 'Price and period changes apply to new purchases; running entitlements keep their dates.' : undefined}
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
          <Button variant="primary" disabled={invalid} loading={save.isPending} onClick={() => save.mutate()}>
            Save
          </Button>
        </>
      }
    >
      <div className="space-y-3">
        {!addon ? (
          <Field label="Code" htmlFor="ad-code" error={errors.code} hint="Permanent identifier, e.g. exam_pro">
            <Input id="ad-code" value={code} onChange={(e) => setCode(e.target.value.trim())} />
          </Field>
        ) : null}
        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="Name (বাংলা)" htmlFor="ad-nbn" error={errors.name}>
            <Input id="ad-nbn" lang="bn" value={d.name_bn} maxLength={80} onChange={(e) => setD({ ...d, name_bn: e.target.value })} />
          </Field>
          <Field label="Name (English)" htmlFor="ad-nen">
            <Input id="ad-nen" value={d.name_en} maxLength={80} onChange={(e) => setD({ ...d, name_en: e.target.value })} />
          </Field>
          <Field label="Description (বাংলা)" htmlFor="ad-dbn">
            <Textarea
              id="ad-dbn"
              lang="bn"
              rows={2}
              maxLength={500}
              value={d.description_bn}
              onChange={(e) => setD({ ...d, description_bn: e.target.value })}
            />
          </Field>
          <Field label="Description (English)" htmlFor="ad-den">
            <Textarea
              id="ad-den"
              rows={2}
              maxLength={500}
              value={d.description_en}
              onChange={(e) => setD({ ...d, description_en: e.target.value })}
            />
          </Field>
        </div>
        <fieldset>
          <legend className="mb-1.5 text-[0.8125rem] font-medium text-fg-2">Features</legend>
          <div className="grid gap-1.5 sm:grid-cols-2">
            {features.map((f) => (
              <Checkbox
                key={f.code}
                label={
                  <span>
                    {f.name_en} {f.is_free ? <Badge tone="success">free</Badge> : null}
                  </span>
                }
                checked={d.features.includes(f.code)}
                onChange={(on) => setD({ ...d, features: on ? [...d.features, f.code] : d.features.filter((x) => x !== f.code) })}
              />
            ))}
          </div>
          {errors.features ? <p className="mt-1 text-xs text-danger">{errors.features}</p> : null}
        </fieldset>
        <div className="grid gap-3 sm:grid-cols-4">
          <Field label="Price (৳)" htmlFor="ad-price" error={errors.price}>
            <Input id="ad-price" inputMode="decimal" value={d.price_bdt} onChange={(e) => setD({ ...d, price_bdt: e.target.value })} />
          </Field>
          <Field label="Period (days)" htmlFor="ad-period" error={errors.period}>
            <Input id="ad-period" inputMode="numeric" value={d.period_days} onChange={(e) => setD({ ...d, period_days: e.target.value })} />
          </Field>
          <Field label="Trial (days)" htmlFor="ad-trial" error={errors.trial} hint="Granted at sign-up">
            <Input id="ad-trial" inputMode="numeric" value={d.trial_days} onChange={(e) => setD({ ...d, trial_days: e.target.value })} />
          </Field>
          <Field label="Sort" htmlFor="ad-sort">
            <Input id="ad-sort" inputMode="numeric" value={d.sort} onChange={(e) => setD({ ...d, sort: e.target.value })} />
          </Field>
        </div>
        <div className="grid gap-3 sm:grid-cols-3">
          <Field label="Badge" htmlFor="ad-badge" hint="e.g. সেরা মূল্য">
            <Input id="ad-badge" lang="bn" value={d.badge} maxLength={30} onChange={(e) => setD({ ...d, badge: e.target.value })} />
          </Field>
          <Field label="Colour" htmlFor="ad-color" error={errors.color}>
            <div className="flex gap-2">
              <input
                type="color"
                aria-label="Pick colour"
                value={/^#[0-9A-Fa-f]{6}$/.test(d.color) ? d.color : '#006A4E'}
                onChange={(e) => setD({ ...d, color: e.target.value.toUpperCase() })}
                className="h-10 w-12 shrink-0 cursor-pointer rounded-lg border border-line-strong bg-surface"
              />
              <Input id="ad-color" value={d.color} onChange={(e) => setD({ ...d, color: e.target.value })} />
            </div>
          </Field>
          <Field label="Icon" htmlFor="ad-icon" error={errors.icon}>
            <Input id="ad-icon" value={d.icon} onChange={(e) => setD({ ...d, icon: e.target.value })} />
          </Field>
        </div>
        <Switch
          checked={d.is_active}
          onChange={(v) => setD({ ...d, is_active: v })}
          label="On sale"
          description="Inactive add-ons are hidden from the store (existing entitlements keep working)."
        />
      </div>
    </Modal>
  );
}

function FeatureEditor({ feature, onClose }: { feature: Feature; onClose: () => void }) {
  const qc = useQueryClient();
  const toast = useToast();
  const [isFree, setIsFree] = useState(feature.is_free);
  const [quota, setQuota] = useState(feature.free_daily_quota === null ? '' : String(feature.free_daily_quota));
  const [nameBn, setNameBn] = useState(feature.name_bn);
  const [nameEn, setNameEn] = useState(feature.name_en);
  const quotaErr = quota !== '' && (!/^\d+$/.test(quota) || Number(quota) > 1000) ? '0–1000 or empty' : null;
  const save = useMutation({
    mutationFn: () =>
      rpc('admin_save_feature', {
        p_code: feature.code,
        p_patch: { is_free: isFree, free_daily_quota: quota === '' ? null : Number(quota), name_bn: nameBn.trim(), name_en: nameEn.trim() },
      }),
    onSuccess: () => {
      toast.success('Feature saved.');
      void qc.invalidateQueries({ queryKey: ['addons'] });
      onClose();
    },
  });
  return (
    <Modal
      open
      onClose={onClose}
      size="sm"
      title={`Feature: ${feature.code}`}
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
          <Button
            variant="primary"
            disabled={!!quotaErr || !nameBn.trim() || !nameEn.trim()}
            loading={save.isPending}
            onClick={() => save.mutate()}
          >
            Save
          </Button>
        </>
      }
    >
      <div className="space-y-3">
        <Field label="Name (বাংলা)" htmlFor="fe-nbn">
          <Input id="fe-nbn" lang="bn" value={nameBn} onChange={(e) => setNameBn(e.target.value)} />
        </Field>
        <Field label="Name (English)" htmlFor="fe-nen">
          <Input id="fe-nen" value={nameEn} onChange={(e) => setNameEn(e.target.value)} />
        </Field>
        <Switch checked={isFree} onChange={setIsFree} label="Free for everyone" description="Free features ignore add-ons entirely." />
        <Field
          label="Free uses per day (paid features)"
          htmlFor="fe-quota"
          error={quotaErr}
          hint="Empty = no free uses. Counted per Bangladesh day."
        >
          <Input id="fe-quota" inputMode="numeric" value={quota} disabled={isFree} onChange={(e) => setQuota(e.target.value.trim())} />
        </Field>
      </div>
    </Modal>
  );
}
