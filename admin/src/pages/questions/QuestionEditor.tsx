import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Plus, Trash2 } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { useToast } from '../../components/feedback';
import { Modal } from '../../components/Modal';
import { Button, Checkbox, cx, ErrorState, Field, IconButton, Input, Select, Spinner, Textarea } from '../../components/ui';
import { useSources, useSubjects, useTopics } from '../../lib/catalog';
import { describeError, toApiError } from '../../lib/errors';
import { rpc } from '../../lib/rpc';
import { SOURCE_KINDS, TRACKS, type QuestionDetail, type QuestionStatus, type ReviewStatus, type SourceKind } from '../../lib/types';

interface Draft {
  subject_id: string;
  topic_id: string;
  stem: string;
  options: string[];
  correct_index: number;
  explanation: string;
  difficulty: number;
  language: 'bn' | 'en';
  exam_tags: string[];
  year: string;
  sourceMode: 'none' | 'existing' | 'new';
  source_id: string;
  source_kind: SourceKind;
  source_name: string;
  source_ref: string;
  source_url: string;
  status: QuestionStatus;
  review_status: ReviewStatus;
}

const BLANK: Draft = {
  subject_id: '',
  topic_id: '',
  stem: '',
  options: ['', '', '', ''],
  correct_index: 0,
  explanation: '',
  difficulty: 2,
  language: 'bn',
  exam_tags: ['bcs'],
  year: '',
  sourceMode: 'none',
  source_id: '',
  source_kind: 'curated',
  source_name: '',
  source_ref: '',
  source_url: '',
  status: 'published',
  review_status: 'unverified',
};

function fromDetail(d: QuestionDetail): Draft {
  return {
    subject_id: String(d.subject_id),
    topic_id: d.topic_id ? String(d.topic_id) : '',
    stem: d.stem,
    options: [...d.options],
    correct_index: d.correct_index,
    explanation: d.explanation ?? '',
    difficulty: d.difficulty,
    language: d.language,
    exam_tags: [...d.exam_tags],
    year: d.year ? String(d.year) : '',
    sourceMode: d.source_id ? 'existing' : 'none',
    source_id: d.source_id ? String(d.source_id) : '',
    source_kind: d.source?.kind ?? 'curated',
    source_name: '',
    source_ref: d.source_ref ?? '',
    source_url: d.source_url ?? '',
    status: d.status,
    review_status: d.review_status,
  };
}

function validate(d: Draft): Record<string, string> {
  const e: Record<string, string> = {};
  if (!d.subject_id) e.subject_id = 'Pick a subject.';
  const stem = d.stem.trim();
  if (stem.length < 3 || stem.length > 2000) e.stem = 'The question must be 3–2000 characters.';
  const opts = d.options.map((o) => o.trim());
  if (opts.length < 2 || opts.length > 5) e.options = 'Give 2–5 options.';
  else if (opts.some((o) => !o)) e.options = 'Options cannot be empty.';
  else if (new Set(opts).size !== opts.length) e.options = 'Options must be distinct.';
  else if (opts.some((o) => o.length > 500)) e.options = 'Options are limited to 500 characters.';
  if (d.correct_index < 0 || d.correct_index >= opts.length) e.options = 'Mark the correct option.';
  if (d.explanation.length > 4000) e.explanation = 'At most 4000 characters.';
  if (d.year && (!/^\d{4}$/.test(d.year) || Number(d.year) < 1950 || Number(d.year) > 2100)) e.year = 'A 4-digit year.';
  if (d.source_url.trim() && !/^https?:\/\/[^\s/$.?#][^\s]*$/i.test(d.source_url.trim())) e.source_url = 'An http(s) link.';
  if (d.sourceMode === 'existing' && !d.source_id) e.source = 'Pick a source.';
  if (d.sourceMode === 'new' && !d.source_name.trim()) e.source = 'Name the new source.';
  if (d.source_ref.length > 300) e.source_ref = 'At most 300 characters.';
  return e;
}

function toPayload(d: Draft): Record<string, unknown> {
  return {
    subject_id: Number(d.subject_id),
    topic_id: d.topic_id ? Number(d.topic_id) : null,
    stem: d.stem.trim(),
    options: d.options.map((o) => o.trim()),
    correct_index: d.correct_index,
    explanation: d.explanation.trim() || null,
    difficulty: d.difficulty,
    language: d.language,
    exam_tags: d.exam_tags,
    year: d.year ? Number(d.year) : null,
    status: d.status,
    review_status: d.review_status,
    source_ref: d.source_ref.trim() || null,
    source_url: d.source_url.trim() || null,
    ...(d.sourceMode === 'existing'
      ? { source_id: Number(d.source_id) }
      : d.sourceMode === 'new'
        ? { source_kind: d.source_kind, source_name: d.source_name.trim() }
        : { source_id: null }),
  };
}

export function QuestionEditor({ id, onClose, onSaved }: { id: number | null; onClose: () => void; onSaved: (id: number) => void }) {
  const detail = useQuery({
    queryKey: ['question', id],
    queryFn: () => rpc<QuestionDetail>('admin_get_question', { p_id: id }),
    enabled: id !== null,
  });
  const [draft, setDraft] = useState<Draft | null>(id === null ? BLANK : null);
  useEffect(() => {
    if (id !== null && detail.data && !draft) setDraft(fromDetail(detail.data));
  }, [id, detail.data, draft]);

  return (
    <Modal open onClose={onClose} size="lg" title={id === null ? 'New question' : `Edit question #${id}`}>
      {detail.error ? <ErrorState error={detail.error} onRetry={() => void detail.refetch()} /> : null}
      {draft ? <EditorForm id={id} initial={draft} onClose={onClose} onSaved={onSaved} /> : <Spinner />}
    </Modal>
  );
}

function EditorForm({
  id,
  initial,
  onClose,
  onSaved,
}: {
  id: number | null;
  initial: Draft;
  onClose: () => void;
  onSaved: (id: number) => void;
}) {
  const qc = useQueryClient();
  const toast = useToast();
  const subjects = useSubjects();
  const topics = useTopics();
  const sources = useSources();
  const [d, setD] = useState<Draft>(initial);
  const [touched, setTouched] = useState(false);
  const errors = useMemo(() => validate(d), [d]);
  const shownErrors = touched ? errors : {};
  const set = <K extends keyof Draft>(k: K, v: Draft[K]) => setD((prev) => ({ ...prev, [k]: v }));
  const topicOptions = (topics.data ?? []).filter((t) => String(t.subject_id) === d.subject_id);

  const save = useMutation({
    mutationFn: () => rpc<{ id: number }>('admin_save_question', { p_id: id, p_question: toPayload(d) }),
    onSuccess: (res) => {
      toast.success(id === null ? `Question #${res.id} created.` : 'Question saved.');
      void qc.invalidateQueries({ queryKey: ['questions'] });
      void qc.invalidateQueries({ queryKey: ['question', res.id] });
      if (d.sourceMode === 'new') void qc.invalidateQueries({ queryKey: ['catalog', 'sources'] });
      onSaved(res.id);
    },
  });
  const saveError = save.error ? toApiError(save.error) : null;

  return (
    <form
      noValidate
      onSubmit={(e) => {
        e.preventDefault();
        setTouched(true);
        if (Object.keys(errors).length === 0) save.mutate();
      }}
      className="space-y-4"
    >
      <div className="grid gap-3 sm:grid-cols-2">
        <Field label="Subject" htmlFor="qe-subject" error={shownErrors.subject_id}>
          <Select id="qe-subject" value={d.subject_id} onChange={(e) => setD({ ...d, subject_id: e.target.value, topic_id: '' })}>
            <option value="">Choose…</option>
            {subjects.data?.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name_en} · {s.name_bn}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Topic" htmlFor="qe-topic" hint="Empty → the subject's general topic.">
          <Select id="qe-topic" value={d.topic_id} disabled={!d.subject_id} onChange={(e) => set('topic_id', e.target.value)}>
            <option value="">General</option>
            {topicOptions.map((t) => (
              <option key={t.id} value={t.id}>
                {t.name_en} · {t.name_bn}
              </option>
            ))}
          </Select>
        </Field>
      </div>

      <Field label="Question" htmlFor="qe-stem" error={shownErrors.stem}>
        <Textarea
          id="qe-stem"
          rows={3}
          lang={d.language === 'bn' ? 'bn' : undefined}
          value={d.stem}
          aria-invalid={!!shownErrors.stem}
          onChange={(e) => set('stem', e.target.value)}
        />
      </Field>

      <fieldset className="space-y-2">
        <legend className="mb-1 text-[0.8125rem] font-medium text-fg-2">Options (select the correct one)</legend>
        {d.options.map((o, i) => (
          <div key={i} className="flex items-center gap-2">
            <input
              type="radio"
              name="correct"
              aria-label={`Option ${i + 1} is correct`}
              className="size-4 accent-[var(--brand)]"
              checked={d.correct_index === i}
              onChange={() => set('correct_index', i)}
            />
            <Input
              aria-label={`Option ${i + 1}`}
              lang={d.language === 'bn' ? 'bn' : undefined}
              value={o}
              className={cx(d.correct_index === i && 'border-success')}
              onChange={(e) =>
                set(
                  'options',
                  d.options.map((x, j) => (j === i ? e.target.value : x)),
                )
              }
            />
            <IconButton
              label={`Remove option ${i + 1}`}
              size="sm"
              disabled={d.options.length <= 2}
              onClick={() =>
                setD({
                  ...d,
                  options: d.options.filter((_, j) => j !== i),
                  correct_index: d.correct_index === i ? 0 : d.correct_index > i ? d.correct_index - 1 : d.correct_index,
                })
              }
            >
              <Trash2 className="size-4" />
            </IconButton>
          </div>
        ))}
        {shownErrors.options ? (
          <p className="text-xs text-danger" role="alert">
            {shownErrors.options}
          </p>
        ) : null}
        {d.options.length < 5 ? (
          <Button size="sm" variant="ghost" icon={<Plus className="size-3.5" />} onClick={() => set('options', [...d.options, ''])}>
            Add option
          </Button>
        ) : null}
      </fieldset>

      <Field label="Explanation" htmlFor="qe-expl" error={shownErrors.explanation}>
        <Textarea
          id="qe-expl"
          rows={3}
          value={d.explanation}
          onChange={(e) => set('explanation', e.target.value)}
          lang={/[ঀ-৿]/.test(d.explanation) ? 'bn' : undefined}
        />
      </Field>

      <div className="grid gap-3 sm:grid-cols-4">
        <Field label="Difficulty" htmlFor="qe-diff">
          <Select id="qe-diff" value={d.difficulty} onChange={(e) => set('difficulty', Number(e.target.value))}>
            {[1, 2, 3, 4, 5].map((n) => (
              <option key={n} value={n}>
                {n} {n === 1 ? '(easy)' : n === 5 ? '(hard)' : ''}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Language" htmlFor="qe-lang">
          <Select id="qe-lang" value={d.language} onChange={(e) => set('language', e.target.value as 'bn' | 'en')}>
            <option value="bn">Bangla</option>
            <option value="en">English</option>
          </Select>
        </Field>
        <Field label="Year" htmlFor="qe-year" error={shownErrors.year}>
          <Input id="qe-year" inputMode="numeric" placeholder="e.g. 2023" value={d.year} onChange={(e) => set('year', e.target.value)} />
        </Field>
        <fieldset>
          <legend className="mb-1.5 text-[0.8125rem] font-medium text-fg-2">Tracks</legend>
          <div className="flex flex-wrap gap-x-3 gap-y-1.5 pt-1">
            {TRACKS.map((t) => (
              <Checkbox
                key={t.code}
                label={t.label}
                checked={d.exam_tags.includes(t.code)}
                onChange={(on) => set('exam_tags', on ? [...d.exam_tags, t.code] : d.exam_tags.filter((x) => x !== t.code))}
              />
            ))}
          </div>
        </fieldset>
      </div>

      <fieldset className="space-y-3 rounded-lg border border-line p-3">
        <legend className="px-1 text-[0.8125rem] font-medium text-fg-2">Source</legend>
        <div className="grid gap-3 sm:grid-cols-3">
          <Field label="Provenance" htmlFor="qe-smode" error={shownErrors.source}>
            <Select id="qe-smode" value={d.sourceMode} onChange={(e) => set('sourceMode', e.target.value as Draft['sourceMode'])}>
              <option value="none">No source</option>
              <option value="existing">Existing source</option>
              <option value="new">New source…</option>
            </Select>
          </Field>
          {d.sourceMode === 'existing' ? (
            <Field label="Source" htmlFor="qe-source" className="sm:col-span-2">
              <Select id="qe-source" value={d.source_id} onChange={(e) => set('source_id', e.target.value)}>
                <option value="">Choose…</option>
                {SOURCE_KINDS.map((k) => {
                  const group = sources.data?.filter((s) => s.kind === k.value) ?? [];
                  return group.length ? (
                    <optgroup key={k.value} label={k.label}>
                      {group.map((s) => (
                        <option key={s.id} value={s.id}>
                          {s.name}
                          {s.year ? ` (${s.year})` : ''}
                        </option>
                      ))}
                    </optgroup>
                  ) : null;
                })}
              </Select>
            </Field>
          ) : d.sourceMode === 'new' ? (
            <>
              <Field label="Kind" htmlFor="qe-skind">
                <Select id="qe-skind" value={d.source_kind} onChange={(e) => set('source_kind', e.target.value as SourceKind)}>
                  {SOURCE_KINDS.map((k) => (
                    <option key={k.value} value={k.value}>
                      {k.label}
                    </option>
                  ))}
                </Select>
              </Field>
              <Field label="Name" htmlFor="qe-sname">
                <Input
                  id="qe-sname"
                  value={d.source_name}
                  maxLength={200}
                  onChange={(e) => set('source_name', e.target.value)}
                  placeholder="e.g. ৪৪তম বিসিএস প্রিলিমিনারি"
                />
              </Field>
            </>
          ) : null}
        </div>
        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="Reference shown to learners" htmlFor="qe-sref" error={shownErrors.source_ref} hint="e.g. ৪৪তম বিসিএস প্রিলিমিনারি">
            <Input id="qe-sref" lang="bn" value={d.source_ref} onChange={(e) => set('source_ref', e.target.value)} />
          </Field>
          <Field label="Source link" htmlFor="qe-surl" error={shownErrors.source_url}>
            <Input
              id="qe-surl"
              type="url"
              value={d.source_url}
              placeholder="https://…"
              onChange={(e) => set('source_url', e.target.value)}
            />
          </Field>
        </div>
      </fieldset>

      <div className="grid gap-3 sm:grid-cols-2">
        <Field label="Status" htmlFor="qe-status" hint="Only published questions reach learners.">
          <Select id="qe-status" value={d.status} onChange={(e) => set('status', e.target.value as QuestionStatus)}>
            <option value="published">Published</option>
            <option value="draft">Draft</option>
            <option value="archived">Archived</option>
            <option value="rejected">Rejected</option>
          </Select>
        </Field>
        <Field label="Review" htmlFor="qe-review">
          <Select id="qe-review" value={d.review_status} onChange={(e) => set('review_status', e.target.value as ReviewStatus)}>
            <option value="unverified">Unverified</option>
            <option value="verified">Verified</option>
            <option value="flagged">Flagged</option>
          </Select>
        </Field>
      </div>

      {saveError ? (
        <p role="alert" className="rounded-lg bg-danger-soft px-3 py-2 text-sm text-danger">
          {describeError(saveError)}
        </p>
      ) : null}
      {touched && Object.keys(errors).length ? (
        <p className="text-sm text-danger" role="alert">
          Fix the highlighted fields.
        </p>
      ) : null}

      <div className="sticky bottom-0 -mx-5 -mb-4 flex justify-end gap-2 border-t border-line bg-surface px-5 py-3">
        <Button variant="ghost" onClick={onClose}>
          Cancel
        </Button>
        <Button type="submit" variant="primary" loading={save.isPending}>
          {id === null ? 'Create question' : 'Save changes'}
        </Button>
      </div>
    </form>
  );
}
