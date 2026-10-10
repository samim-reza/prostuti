import { useMemo } from 'react';
import { diffLines, prettyJson } from '../lib/diff';
import { Button, cx, Textarea } from './ui';

export type JsonParse = { ok: true; value: unknown } | { ok: false; error: string };

export function parseJson(text: string): JsonParse {
  if (text.trim() === '') return { ok: false, error: 'Value is empty' };
  try {
    return { ok: true, value: JSON.parse(text) as unknown };
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : 'Invalid JSON' };
  }
}

/** Textarea for JSON with live validation and a "Format" button. */
export function JsonEditor({
  value,
  onChange,
  rows = 10,
  id,
  label,
}: {
  value: string;
  onChange: (v: string) => void;
  rows?: number;
  id?: string;
  label: string;
}) {
  const parsed = useMemo(() => parseJson(value), [value]);
  return (
    <div className="space-y-1.5">
      <Textarea
        id={id}
        aria-label={label}
        aria-invalid={!parsed.ok}
        value={value}
        rows={rows}
        spellCheck={false}
        onChange={(e) => onChange(e.target.value)}
        className="font-mono text-[0.8125rem]"
      />
      <div className="flex items-center justify-between gap-2 text-xs">
        <span className={parsed.ok ? 'text-success' : 'text-danger'} role={parsed.ok ? undefined : 'alert'}>
          {parsed.ok ? 'Valid JSON' : parsed.error}
        </span>
        <Button size="sm" variant="ghost" disabled={!parsed.ok} onClick={() => parsed.ok && onChange(prettyJson(parsed.value))}>
          Format
        </Button>
      </div>
    </div>
  );
}

/** Unified line diff of two JSON values. */
export function JsonDiff({ before, after }: { before: unknown; after: unknown }) {
  const lines = useMemo(() => diffLines(prettyJson(before), prettyJson(after)), [before, after]);
  const changed = lines.some((l) => l.kind !== 'same');
  if (!changed) return <p className="text-sm text-muted">No changes.</p>;
  return (
    <pre
      className="max-h-80 overflow-auto rounded-lg border border-line bg-surface-2 p-2 text-[0.8125rem] leading-relaxed"
      aria-label="Changes"
    >
      {lines.map((l, i) => (
        <div
          key={i}
          className={cx(
            'px-2 whitespace-pre-wrap',
            l.kind === 'add' && 'bg-success-soft text-success',
            l.kind === 'del' && 'bg-danger-soft text-danger line-through decoration-danger/40',
          )}
        >
          <span aria-hidden className="mr-2 inline-block w-3 select-none">
            {l.kind === 'add' ? '+' : l.kind === 'del' ? '−' : ' '}
          </span>
          {l.text}
        </div>
      ))}
    </pre>
  );
}
