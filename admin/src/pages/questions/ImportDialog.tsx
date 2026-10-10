import { useQueryClient } from '@tanstack/react-query';
import { CheckCircle2, CopyX, FileJson, Upload, XCircle } from 'lucide-react';
import { useMemo, useRef, useState } from 'react';
import { useToast } from '../../components/feedback';
import { Modal } from '../../components/Modal';
import { Badge, Button, Checkbox, Field, Notice, Select, TableWrap } from '../../components/ui';
import { useSubjects, useTopics } from '../../lib/catalog';
import { describeError } from '../../lib/errors';
import { fmtNumber, truncate } from '../../lib/format';
import { rpc } from '../../lib/rpc';
import { describeSeedError, stemKey, validateSeed } from '../../lib/seed';

type RowState = 'new' | 'invalid' | 'duplicate' | 'file_duplicate';
interface Row {
  index: number;
  item: Record<string, unknown>;
  state: RowState;
  error: string | null;
  existingId: number | null;
}
interface ImportResult {
  total: number;
  inserted: { index: number; id: number }[];
  invalid: { index: number; error: string }[];
  duplicates: number[];
}

const MAX_FILE = 8 * 1024 * 1024;
const MAX_ITEMS = 10_000;

export function ImportDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const subjects = useSubjects();
  const topics = useTopics();
  const qc = useQueryClient();
  const toast = useToast();
  const fileRef = useRef<HTMLInputElement>(null);
  const [fileName, setFileName] = useState('');
  const [rows, setRows] = useState<Row[] | null>(null);
  const [parseError, setParseError] = useState<string | null>(null);
  const [checking, setChecking] = useState(false);
  const [status, setStatus] = useState<'published' | 'draft'>('draft');
  const [onlyProblems, setOnlyProblems] = useState(false);
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null);
  const [result, setResult] = useState<{ inserted: number; duplicates: number; invalid: number; failed: string | null } | null>(null);

  const counts = useMemo(() => {
    const c: Record<RowState, number> = { new: 0, invalid: 0, duplicate: 0, file_duplicate: 0 };
    rows?.forEach((r) => c[r.state]++);
    return c;
  }, [rows]);

  function reset() {
    setFileName('');
    setRows(null);
    setParseError(null);
    setResult(null);
    setProgress(null);
    if (fileRef.current) fileRef.current.value = '';
  }

  async function onFile(file: File) {
    reset();
    setFileName(file.name);
    if (file.size > MAX_FILE) {
      setParseError('The file is larger than 8 MB. Split it into smaller files.');
      return;
    }
    let data: unknown;
    try {
      data = JSON.parse(await file.text());
    } catch (e) {
      setParseError(`Not valid JSON: ${e instanceof Error ? e.message : String(e)}`);
      return;
    }
    if (!Array.isArray(data)) {
      setParseError('Expected a JSON array of questions (seed format).');
      return;
    }
    if (data.length === 0 || data.length > MAX_ITEMS) {
      setParseError(`The file must contain 1–${fmtNumber(MAX_ITEMS)} questions.`);
      return;
    }
    const subj = subjects.data ?? [];
    const tops = topics.data ?? [];
    const seen = new Set<string>();
    const parsed: Row[] = data.map((item, index) => {
      const error = validateSeed(item, subj, tops);
      const obj = (typeof item === 'object' && item !== null ? item : {}) as Record<string, unknown>;
      if (error) return { index, item: obj, state: 'invalid', error, existingId: null };
      const key = stemKey(String(obj.stem));
      if (seen.has(key)) return { index, item: obj, state: 'file_duplicate', error: null, existingId: null };
      seen.add(key);
      return { index, item: obj, state: 'new', error: null, existingId: null };
    });
    setRows(parsed);
    // Which stems already exist? Same normalisation as questions.stem_hash, done by the server.
    setChecking(true);
    try {
      const candidates = parsed.filter((r) => r.state === 'new');
      for (let i = 0; i < candidates.length; i += 1000) {
        const chunk = candidates.slice(i, i + 1000);
        const found = await rpc<{ index: number; id: number }[]>('admin_find_duplicate_questions', {
          p_stems: chunk.map((r) => String(r.item.stem)),
        });
        for (const f of found) {
          const row = chunk[f.index];
          if (row) {
            row.state = 'duplicate';
            row.existingId = f.id;
          }
        }
      }
      setRows([...parsed]);
    } catch (e) {
      setParseError(`Could not check for duplicates: ${describeError(e)}`);
    } finally {
      setChecking(false);
    }
  }

  async function runImport() {
    if (!rows) return;
    const toSend = rows.filter((r) => r.state === 'new');
    let inserted = 0;
    let duplicates = 0;
    let invalid = 0;
    let failed: string | null = null;
    setProgress({ done: 0, total: toSend.length });
    for (let i = 0; i < toSend.length; i += 500) {
      const chunk = toSend.slice(i, i + 500);
      try {
        const res = await rpc<ImportResult>('admin_import_questions', {
          p_items: chunk.map((r) => r.item),
          p_status: status,
          p_review_status: 'unverified',
        });
        inserted += res.inserted.length;
        duplicates += res.duplicates.length;
        invalid += res.invalid.length;
      } catch (e) {
        failed = describeError(e);
        break;
      }
      setProgress({ done: Math.min(i + 500, toSend.length), total: toSend.length });
    }
    setResult({ inserted, duplicates, invalid, failed });
    setProgress(null);
    void qc.invalidateQueries({ queryKey: ['questions'] });
    void qc.invalidateQueries({ queryKey: ['catalog', 'sources'] });
    if (!failed) toast.success(`Imported ${inserted} question${inserted === 1 ? '' : 's'}.`);
  }

  const visible = (rows ?? []).filter((r) => !onlyProblems || r.state !== 'new').slice(0, 300);
  const importing = progress !== null;

  return (
    <Modal
      open={open}
      onClose={() => {
        if (importing) return;
        reset();
        onClose();
      }}
      dismissible={!importing}
      size="xl"
      title="Import questions"
      description="A JSON array in the seed format (supabase/seed/questions/README.md). Existing questions are skipped."
      footer={
        result ? (
          <Button
            variant="primary"
            onClick={() => {
              reset();
              onClose();
            }}
          >
            Done
          </Button>
        ) : (
          <>
            <Button
              variant="ghost"
              disabled={importing}
              onClick={() => {
                reset();
                onClose();
              }}
            >
              Cancel
            </Button>
            <Button
              variant="primary"
              icon={<Upload className="size-4" />}
              disabled={!rows || checking || counts.new === 0}
              loading={importing}
              onClick={() => void runImport()}
            >
              {importing ? `Importing ${progress.done}/${progress.total}…` : `Import ${fmtNumber(counts.new)} new`}
            </Button>
          </>
        )
      }
    >
      <div className="space-y-4">
        {!result ? (
          <div className="flex flex-wrap items-end gap-3">
            <Field label="JSON file" htmlFor="imp-file" className="min-w-64 flex-1">
              <input
                ref={fileRef}
                id="imp-file"
                type="file"
                accept="application/json,.json"
                disabled={importing}
                onChange={(e) => {
                  const f = e.target.files?.[0];
                  if (f) void onFile(f);
                }}
                className="block w-full text-sm text-fg-2 file:mr-3 file:rounded-lg file:border file:border-line-strong file:bg-surface file:px-3 file:py-2 file:text-sm file:font-medium file:text-fg hover:file:bg-surface-2"
              />
            </Field>
            <Field label="Import as" htmlFor="imp-status" className="w-48">
              <Select
                id="imp-status"
                value={status}
                disabled={importing}
                onChange={(e) => setStatus(e.target.value as 'published' | 'draft')}
              >
                <option value="draft">Draft (review first)</option>
                <option value="published">Published</option>
              </Select>
            </Field>
          </div>
        ) : null}

        {parseError ? (
          <Notice tone="danger" icon={<XCircle className="size-4" />}>
            {parseError}
          </Notice>
        ) : null}

        {result ? (
          <div className="space-y-2">
            {result.failed ? <Notice tone="danger">Import stopped: {result.failed}</Notice> : null}
            <Notice tone="success" icon={<CheckCircle2 className="size-4" />}>
              {fmtNumber(result.inserted)} imported
              {result.duplicates ? ` · ${fmtNumber(result.duplicates)} skipped as duplicates` : ''}
              {result.invalid ? ` · ${fmtNumber(result.invalid)} rejected by the server` : ''}. Imported questions are marked unverified
              {status === 'draft' ? ' and saved as drafts' : ''}.
            </Notice>
          </div>
        ) : rows ? (
          <>
            <div className="flex flex-wrap items-center gap-2 text-sm">
              <FileJson className="size-4 text-muted" aria-hidden />
              <span className="font-medium">{fileName}</span>
              <span className="text-muted">· {fmtNumber(rows.length)} items</span>
              <Badge tone="success">{fmtNumber(counts.new)} new</Badge>
              <Badge tone="info">{fmtNumber(counts.duplicate)} already in bank</Badge>
              <Badge tone="neutral">{fmtNumber(counts.file_duplicate)} repeated in file</Badge>
              <Badge tone="danger">{fmtNumber(counts.invalid)} invalid</Badge>
              {checking ? <span className="text-xs text-muted">checking duplicates…</span> : null}
            </div>
            <Checkbox label="Show only skipped / invalid rows" checked={onlyProblems} onChange={setOnlyProblems} />
            <TableWrap className="max-h-[50dvh] rounded-lg border border-line">
              <table className="table-base">
                <thead>
                  <tr>
                    <th scope="col">#</th>
                    <th scope="col">Question</th>
                    <th scope="col">Subject</th>
                    <th scope="col">Result</th>
                  </tr>
                </thead>
                <tbody>
                  {visible.map((r) => (
                    <tr key={r.index}>
                      <td className="num text-xs text-muted">{r.index + 1}</td>
                      <td>
                        <span lang="bn">{truncate(String(r.item.stem ?? ''), 110) || <em className="text-muted">no stem</em>}</span>
                      </td>
                      <td className="text-xs whitespace-nowrap">{String(r.item.subject ?? '—')}</td>
                      <td className="text-xs">
                        {r.state === 'new' ? (
                          <Badge tone="success">new</Badge>
                        ) : r.state === 'duplicate' ? (
                          <Badge tone="info" icon={<CopyX className="size-3" />}>
                            exists #{r.existingId}
                          </Badge>
                        ) : r.state === 'file_duplicate' ? (
                          <Badge>repeated in file</Badge>
                        ) : (
                          <span className="text-danger">{describeSeedError(r.error ?? '')}</span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </TableWrap>
            {rows.length > visible.length && !onlyProblems ? (
              <p className="text-xs text-muted">Showing the first {visible.length} rows.</p>
            ) : null}
          </>
        ) : (
          <p className="text-sm text-muted">
            Pick a file to preview it. Every item is validated here and again on the server; duplicates (same text, ignoring spaces and
            case) are skipped, and missing sources are created automatically.
          </p>
        )}
      </div>
    </Modal>
  );
}
