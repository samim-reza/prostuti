import { useMutation } from '@tanstack/react-query';
import { useMemo, useState } from 'react';
import { useToast } from '../../components/feedback';
import { JsonEditor, parseJson } from '../../components/json';
import { Modal } from '../../components/Modal';
import { Button, Field, Input, Select, Textarea } from '../../components/ui';
import { describeError } from '../../lib/errors';
import { rpc } from '../../lib/rpc';
import type { NoteRow } from '../../lib/types';

const CATEGORIES = [
  'bangladesh',
  'international',
  'economy',
  'science_tech',
  'sports',
  'environment',
  'awards_people',
  'organizations',
  'days_events',
  'misc',
];

type JsonKey = 'key_facts' | 'key_facts_en' | 'probable_questions' | 'probable_questions_en';
const JSON_FIELDS: { key: JsonKey; label: string; shape: string }[] = [
  { key: 'key_facts', label: 'Key facts (বাংলা)', shape: '[{"fact": "…", "tag": "…"}]' },
  { key: 'key_facts_en', label: 'Key facts (English)', shape: '[{"fact": "…"}]' },
  { key: 'probable_questions', label: 'Probable questions (বাংলা)', shape: '[{"q": "…", "a": "…"}]' },
  { key: 'probable_questions_en', label: 'Probable questions (English)', shape: '[{"q": "…", "a": "…"}]' },
];

function shapeError(key: JsonKey, value: unknown): string | null {
  if (!Array.isArray(value)) return 'Must be an array.';
  const facts = key.startsWith('key_facts');
  for (const item of value) {
    if (typeof item !== 'object' || item === null) return 'Every item must be an object.';
    const o = item as Record<string, unknown>;
    if (facts && typeof o.fact !== 'string') return 'Every item needs a "fact" string.';
    if (!facts && (typeof o.q !== 'string' || typeof o.a !== 'string')) return 'Every item needs "q" and "a" strings.';
  }
  return null;
}

/** Edits one daily note; only changed fields are sent (admin_update_note). */
export function NoteEditor({ note, onClose, onSaved }: { note: NoteRow; onClose: () => void; onSaved: () => void }) {
  const toast = useToast();
  const [title, setTitle] = useState(note.title);
  const [summary, setSummary] = useState(note.summary);
  const [titleEn, setTitleEn] = useState(note.title_en ?? '');
  const [summaryEn, setSummaryEn] = useState(note.summary_en ?? '');
  const [category, setCategory] = useState(note.category);
  const [importance, setImportance] = useState(note.importance);
  const [status, setStatus] = useState(note.status);
  const [json, setJson] = useState<Record<JsonKey, string>>({
    key_facts: JSON.stringify(note.key_facts, null, 2),
    key_facts_en: JSON.stringify(note.key_facts_en, null, 2),
    probable_questions: JSON.stringify(note.probable_questions, null, 2),
    probable_questions_en: JSON.stringify(note.probable_questions_en, null, 2),
  });

  const jsonErrors = useMemo(() => {
    const out: Partial<Record<JsonKey, string>> = {};
    for (const f of JSON_FIELDS) {
      const parsed = parseJson(json[f.key]);
      if (!parsed.ok) out[f.key] = parsed.error;
      else {
        const e = shapeError(f.key, parsed.value);
        if (e) out[f.key] = e;
      }
    }
    return out;
  }, [json]);

  const patch = useMemo(() => {
    const p: Record<string, unknown> = {};
    if (title.trim() !== note.title) p.title = title.trim();
    if (summary.trim() !== note.summary) p.summary = summary.trim();
    if (titleEn.trim() !== (note.title_en ?? '')) p.title_en = titleEn.trim();
    if (summaryEn.trim() !== (note.summary_en ?? '')) p.summary_en = summaryEn.trim();
    if (category !== note.category) p.category = category;
    if (importance !== note.importance) p.importance = importance;
    if (status !== note.status) p.status = status;
    for (const f of JSON_FIELDS) {
      const parsed = parseJson(json[f.key]);
      if (parsed.ok && JSON.stringify(parsed.value) !== JSON.stringify(note[f.key])) p[f.key] = parsed.value;
    }
    return p;
  }, [title, summary, titleEn, summaryEn, category, importance, status, json, note]);

  const invalid = !title.trim() || !summary.trim() || Object.keys(jsonErrors).length > 0;
  const save = useMutation({
    mutationFn: () => rpc('admin_update_note', { p_id: note.id, p_patch: patch }),
    onSuccess: () => {
      toast.success('Note saved.');
      onSaved();
      onClose();
    },
  });

  return (
    <Modal
      open
      onClose={onClose}
      size="xl"
      title={`Edit note #${note.id}`}
      description={`${note.note_date} · changes apply immediately (today's notes are live in the app).`}
      footer={
        <>
          {save.error ? (
            <p className="mr-auto text-sm text-danger" role="alert">
              {describeError(save.error)}
            </p>
          ) : null}
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button
            variant="primary"
            disabled={invalid || Object.keys(patch).length === 0}
            loading={save.isPending}
            onClick={() => save.mutate()}
          >
            Save {Object.keys(patch).length ? `(${Object.keys(patch).length} change${Object.keys(patch).length === 1 ? '' : 's'})` : ''}
          </Button>
        </>
      }
    >
      <div className="space-y-4">
        <div className="grid gap-3 sm:grid-cols-3">
          <Field label="Category" htmlFor="ne-cat">
            <Select id="ne-cat" value={category} onChange={(e) => setCategory(e.target.value)}>
              {CATEGORIES.map((c) => (
                <option key={c} value={c}>
                  {c.replace('_', ' ')}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Importance" htmlFor="ne-imp">
            <Select id="ne-imp" value={importance} onChange={(e) => setImportance(Number(e.target.value))}>
              {[1, 2, 3, 4, 5].map((n) => (
                <option key={n} value={n}>
                  {n}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Status" htmlFor="ne-status">
            <Select id="ne-status" value={status} onChange={(e) => setStatus(e.target.value as NoteRow['status'])}>
              <option value="published">Published</option>
              <option value="draft">Draft</option>
              <option value="archived">Archived (unpublished)</option>
            </Select>
          </Field>
        </div>
        <div className="grid gap-4 md:grid-cols-2">
          <div className="space-y-3">
            <Field label="Title (বাংলা)" htmlFor="ne-title" error={title.trim() ? null : 'Required'}>
              <Input id="ne-title" lang="bn" value={title} maxLength={300} onChange={(e) => setTitle(e.target.value)} />
            </Field>
            <Field label="Summary (বাংলা)" htmlFor="ne-summary" error={summary.trim() ? null : 'Required'}>
              <Textarea id="ne-summary" lang="bn" rows={6} maxLength={5000} value={summary} onChange={(e) => setSummary(e.target.value)} />
            </Field>
          </div>
          <div className="space-y-3">
            <Field label="Title (English)" htmlFor="ne-title-en">
              <Input id="ne-title-en" value={titleEn} maxLength={300} onChange={(e) => setTitleEn(e.target.value)} />
            </Field>
            <Field label="Summary (English)" htmlFor="ne-summary-en">
              <Textarea id="ne-summary-en" rows={6} maxLength={5000} value={summaryEn} onChange={(e) => setSummaryEn(e.target.value)} />
            </Field>
          </div>
        </div>
        <details className="rounded-lg border border-line p-3">
          <summary className="cursor-pointer text-sm font-medium">Key facts & probable questions (JSON)</summary>
          <div className="mt-3 grid gap-4 md:grid-cols-2">
            {JSON_FIELDS.map((f) => (
              <Field
                key={f.key}
                label={f.label}
                htmlFor={`ne-${f.key}`}
                hint={jsonErrors[f.key] ? undefined : f.shape}
                error={jsonErrors[f.key] && parseJson(json[f.key]).ok ? jsonErrors[f.key] : null}
              >
                <JsonEditor
                  id={`ne-${f.key}`}
                  label={f.label}
                  rows={8}
                  value={json[f.key]}
                  onChange={(v) => setJson((prev) => ({ ...prev, [f.key]: v }))}
                />
              </Field>
            ))}
          </div>
        </details>
      </div>
    </Modal>
  );
}
