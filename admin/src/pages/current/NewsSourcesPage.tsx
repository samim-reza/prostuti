import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { AlertTriangle, ExternalLink, Pencil, Plus } from 'lucide-react';
import { useState } from 'react';
import { useToast } from '../../components/feedback';
import { Modal } from '../../components/Modal';
import {
  Badge,
  Button,
  Card,
  EmptyState,
  ErrorState,
  Field,
  Input,
  PageHeader,
  Select,
  Spinner,
  Switch,
  TableWrap,
  TabLinks,
} from '../../components/ui';
import { describeError } from '../../lib/errors';
import { fmtDateTime, fmtNumber, fmtRelative } from '../../lib/format';
import { usePageTitle } from '../../lib/hooks';
import { rpc } from '../../lib/rpc';
import type { NewsSource } from '../../lib/types';
import { CA_TABS } from './tabs';

interface SourceDraft {
  name: string;
  rss_url: string;
  homepage: string;
  language: 'bn' | 'en';
  region: 'BD' | 'INT';
  category_hint: string;
  priority: number;
  enabled: boolean;
}

function toPayload(s: NewsSource | SourceDraft): SourceDraft {
  return {
    name: s.name,
    rss_url: s.rss_url,
    homepage: s.homepage ?? '',
    language: s.language,
    region: s.region,
    category_hint: s.category_hint ?? '',
    priority: s.priority,
    enabled: s.enabled,
  };
}

export default function NewsSourcesPage() {
  usePageTitle('News sources');
  const qc = useQueryClient();
  const toast = useToast();
  const [editing, setEditing] = useState<{ id: number | null; draft: SourceDraft } | null>(null);
  const q = useQuery({ queryKey: ['news-sources'], queryFn: () => rpc<NewsSource[]>('admin_list_news_sources') });

  const toggle = useMutation({
    mutationFn: (s: NewsSource) =>
      rpc<NewsSource>('admin_save_news_source', { p_id: s.id, p_source: { ...toPayload(s), enabled: !s.enabled } }),
    onSuccess: (s) => {
      toast.success(`${s.name} ${s.enabled ? 'enabled' : 'disabled'}.`);
      void qc.invalidateQueries({ queryKey: ['news-sources'] });
    },
    onError: (e) => toast.error(e),
  });

  return (
    <div>
      <PageHeader
        title="Current affairs"
        description="RSS feeds read every 3 hours. Failing feeds back off automatically (2ⁿ hours, max 24 h); editing a feed resets its back-off."
        actions={
          <Button
            variant="primary"
            icon={<Plus className="size-4" />}
            onClick={() =>
              setEditing({
                id: null,
                draft: { name: '', rss_url: '', homepage: '', language: 'bn', region: 'BD', category_hint: '', priority: 5, enabled: true },
              })
            }
          >
            Add source
          </Button>
        }
      />
      <TabLinks tabs={CA_TABS} />
      <Card pad={false}>
        {q.error ? <ErrorState error={q.error} onRetry={() => void q.refetch()} /> : null}
        {q.isLoading ? (
          <Spinner />
        ) : !q.data?.length ? (
          <EmptyState title="No news sources" />
        ) : (
          <TableWrap>
            <table className="table-base">
              <thead>
                <tr>
                  <th scope="col">Enabled</th>
                  <th scope="col">Source</th>
                  <th scope="col">Lang · region</th>
                  <th scope="col" className="text-right">
                    Priority
                  </th>
                  <th scope="col" className="text-right">
                    Articles 24 h / 7 d
                  </th>
                  <th scope="col">Last fetch</th>
                  <th scope="col">Health</th>
                  <th scope="col">
                    <span className="sr-only">Edit</span>
                  </th>
                </tr>
              </thead>
              <tbody>
                {q.data.map((s) => (
                  <tr key={s.id}>
                    <td>
                      <Switch
                        checked={s.enabled}
                        disabled={toggle.isPending && toggle.variables?.id === s.id}
                        onChange={() => toggle.mutate(s)}
                        label={<span className="sr-only">{s.name} enabled</span>}
                      />
                    </td>
                    <td className="min-w-56">
                      <p className="font-medium" lang={/[ঀ-৿]/.test(s.name) ? 'bn' : undefined}>
                        {s.name}
                      </p>
                      <a
                        href={s.rss_url}
                        target="_blank"
                        rel="noreferrer noopener"
                        className="inline-flex max-w-xs items-center gap-1 truncate text-xs text-info hover:underline"
                      >
                        {s.rss_url} <ExternalLink className="size-3 shrink-0" />
                      </a>
                    </td>
                    <td className="text-sm whitespace-nowrap">
                      {s.language} · {s.region}
                      {s.category_hint ? <span className="block text-xs text-muted">{s.category_hint}</span> : null}
                    </td>
                    <td className="num text-right">{s.priority}</td>
                    <td className="num text-right">
                      {fmtNumber(s.articles_24h)} / {fmtNumber(s.articles_7d)}
                    </td>
                    <td className="text-sm whitespace-nowrap" title={fmtDateTime(s.last_fetched_at)}>
                      {fmtRelative(s.last_fetched_at)}
                    </td>
                    <td className="max-w-64">
                      {s.fail_count > 0 ? (
                        <div>
                          <Badge tone="warning" icon={<AlertTriangle className="size-3" />}>
                            {s.fail_count} failure{s.fail_count === 1 ? '' : 's'}
                          </Badge>
                          {s.last_error ? (
                            <p className="mt-1 truncate text-xs text-muted" title={s.last_error}>
                              {s.last_error}
                            </p>
                          ) : null}
                        </div>
                      ) : (
                        <Badge tone="success">healthy</Badge>
                      )}
                    </td>
                    <td className="text-right">
                      <Button
                        size="sm"
                        variant="ghost"
                        icon={<Pencil className="size-3.5" />}
                        onClick={() => setEditing({ id: s.id, draft: toPayload(s) })}
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
      {editing ? <SourceEditor id={editing.id} initial={editing.draft} onClose={() => setEditing(null)} /> : null}
    </div>
  );
}

function SourceEditor({ id, initial, onClose }: { id: number | null; initial: SourceDraft; onClose: () => void }) {
  const qc = useQueryClient();
  const toast = useToast();
  const [d, setD] = useState(initial);
  const urlOk = (u: string) => /^https?:\/\/[^\s/$.?#][^\s]*$/i.test(u.trim());
  const errors = {
    name: d.name.trim().length < 2 ? 'At least 2 characters.' : null,
    rss_url: !urlOk(d.rss_url) ? 'An http(s) feed URL.' : null,
    homepage: d.homepage.trim() && !urlOk(d.homepage) ? 'An http(s) URL.' : null,
  };
  const save = useMutation({
    mutationFn: () =>
      rpc<NewsSource>('admin_save_news_source', {
        p_id: id,
        p_source: {
          ...d,
          name: d.name.trim(),
          rss_url: d.rss_url.trim(),
          homepage: d.homepage.trim() || null,
          category_hint: d.category_hint.trim() || null,
        },
      }),
    onSuccess: () => {
      toast.success(id === null ? 'Source added.' : 'Source saved.');
      void qc.invalidateQueries({ queryKey: ['news-sources'] });
      onClose();
    },
  });
  const invalid = Object.values(errors).some(Boolean);
  return (
    <Modal
      open
      onClose={onClose}
      title={id === null ? 'Add news source' : `Edit ${initial.name}`}
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
        <Field label="Name" htmlFor="ns-name" error={errors.name}>
          <Input id="ns-name" value={d.name} maxLength={100} onChange={(e) => setD({ ...d, name: e.target.value })} />
        </Field>
        <Field label="RSS feed URL" htmlFor="ns-rss" error={errors.rss_url}>
          <Input
            id="ns-rss"
            type="url"
            value={d.rss_url}
            onChange={(e) => setD({ ...d, rss_url: e.target.value })}
            placeholder="https://example.com/feed"
          />
        </Field>
        <Field label="Homepage" htmlFor="ns-home" error={errors.homepage}>
          <Input id="ns-home" type="url" value={d.homepage} onChange={(e) => setD({ ...d, homepage: e.target.value })} />
        </Field>
        <div className="grid gap-3 sm:grid-cols-3">
          <Field label="Language" htmlFor="ns-lang">
            <Select id="ns-lang" value={d.language} onChange={(e) => setD({ ...d, language: e.target.value as 'bn' | 'en' })}>
              <option value="bn">Bangla</option>
              <option value="en">English</option>
            </Select>
          </Field>
          <Field label="Region" htmlFor="ns-region">
            <Select id="ns-region" value={d.region} onChange={(e) => setD({ ...d, region: e.target.value as 'BD' | 'INT' })}>
              <option value="BD">Bangladesh</option>
              <option value="INT">International</option>
            </Select>
          </Field>
          <Field label="Priority" htmlFor="ns-prio" hint="1–10, higher first">
            <Select id="ns-prio" value={d.priority} onChange={(e) => setD({ ...d, priority: Number(e.target.value) })}>
              {Array.from({ length: 10 }, (_, i) => i + 1).map((n) => (
                <option key={n} value={n}>
                  {n}
                </option>
              ))}
            </Select>
          </Field>
        </div>
        <Field label="Category hint" htmlFor="ns-cat" hint="Optional, e.g. economy">
          <Input id="ns-cat" value={d.category_hint} maxLength={50} onChange={(e) => setD({ ...d, category_hint: e.target.value })} />
        </Field>
        <Switch
          checked={d.enabled}
          onChange={(v) => setD({ ...d, enabled: v })}
          label="Enabled"
          description="Disabled feeds are skipped by ingest-news."
        />
      </div>
    </Modal>
  );
}
