import { useId, useState } from 'react';
import { cx } from './ui';

/**
 * Single-series column chart (one hue, no legend: the title names the series).
 * Marks: ≤ 24px columns, 4px rounded data-end, square at the baseline, 2px
 * gaps; hairline baseline; hover/focus tooltip on each column; a table view
 * for the same numbers so nothing is hover-only.
 */
export function ColumnChart({
  title,
  data,
  format = (v) => String(v),
  labelFormat = (l) => l,
  height = 140,
}: {
  title: string;
  data: { label: string; value: number }[];
  format?: (v: number) => string;
  labelFormat?: (l: string) => string;
  height?: number;
}) {
  const [active, setActive] = useState<number | null>(null);
  const tableId = useId();
  const max = Math.max(0, ...data.map((d) => d.value));
  const peak = data.reduce((best, d, i) => (d.value > (data[best]?.value ?? -1) ? i : best), 0);
  const total = data.reduce((s, d) => s + d.value, 0);
  const shown = active ?? (data.length ? data.length - 1 : null);
  const current = shown !== null ? data[shown] : undefined;

  return (
    <figure className="min-w-0">
      <figcaption className="mb-2 flex items-baseline justify-between gap-2">
        <span className="text-sm font-medium text-fg">{title}</span>
        <span className="text-xs text-muted">
          {current ? (
            <>
              <span className="font-semibold text-fg">{format(current.value)}</span> · {labelFormat(current.label)}
            </>
          ) : null}
        </span>
      </figcaption>
      <div className="rounded-lg px-1 pt-2" style={{ background: 'var(--chart-surface)' }}>
        <div className="relative flex items-end gap-[2px]" style={{ height }} role="list" aria-label={`${title}, total ${format(total)}`}>
          {/* recessive gridline at the peak */}
          {max > 0 ? (
            <div className="pointer-events-none absolute inset-x-0 top-0 border-t" style={{ borderColor: 'var(--chart-grid)' }}>
              <span className="absolute -top-2.5 right-0 bg-[var(--chart-surface)] pl-1 text-[0.6875rem] text-[var(--chart-muted)] num">
                {format(max)}
              </span>
            </div>
          ) : null}
          {data.map((d, i) => {
            const h = max > 0 ? Math.max(d.value > 0 ? 3 : 0, (d.value / max) * (height - 18)) : 0;
            return (
              <button
                key={d.label}
                type="button"
                role="listitem"
                aria-label={`${labelFormat(d.label)}: ${format(d.value)}`}
                onPointerEnter={() => setActive(i)}
                onPointerLeave={() => setActive(null)}
                onFocus={() => setActive(i)}
                onBlur={() => setActive(null)}
                className="group flex h-full min-w-0 flex-1 cursor-default items-end justify-center focus:outline-none"
              >
                <span
                  className={cx('block w-full max-w-6 rounded-t-[4px] transition-opacity', active !== null && active !== i && 'opacity-55')}
                  style={{ height: h, background: 'var(--chart-series)' }}
                />
              </button>
            );
          })}
        </div>
        <div
          className="flex justify-between border-t px-0.5 py-1 text-[0.6875rem] text-[var(--chart-muted)]"
          style={{ borderColor: 'var(--chart-axis)' }}
        >
          <span>{data[0] ? labelFormat(data[0].label) : ''}</span>
          {data.length > 2 && data[peak] && max > 0 ? <span className="hidden sm:inline">peak {labelFormat(data[peak].label)}</span> : null}
          <span>{data.length > 1 ? labelFormat(data[data.length - 1]!.label) : ''}</span>
        </div>
      </div>
      <details className="mt-1.5 text-xs text-muted">
        <summary className="cursor-pointer select-none hover:text-fg" aria-controls={tableId}>
          Show as table
        </summary>
        <table id={tableId} className="table-base mt-2">
          <thead>
            <tr>
              <th scope="col">Day</th>
              <th scope="col" className="text-right">
                Value
              </th>
            </tr>
          </thead>
          <tbody>
            {data.map((d) => (
              <tr key={d.label}>
                <td>{labelFormat(d.label)}</td>
                <td className="num text-right">{format(d.value)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </details>
    </figure>
  );
}

/**
 * Horizontal bars where one row is the point (emphasis form): the highlighted
 * row wears the accent, the rest stay neutral gray. Values are direct labels.
 */
export function EmphasisBars({
  rows,
  ariaLabel,
}: {
  rows: { label: string; value: number; emphasis?: boolean; note?: string }[];
  ariaLabel: string;
}) {
  const max = Math.max(1, ...rows.map((r) => r.value));
  const total = rows.reduce((s, r) => s + r.value, 0);
  return (
    <ul className="space-y-1.5" aria-label={ariaLabel}>
      {rows.map((r) => (
        <li key={r.label} className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-3 gap-y-1 text-sm">
          <span className="min-w-0 truncate text-fg-2" lang={/[ঀ-৿]/.test(r.label) ? 'bn' : undefined}>
            {r.label}
            {r.note ? <span className="ml-1.5 text-xs text-muted">{r.note}</span> : null}
          </span>
          <span className="num text-xs text-fg">
            {r.value} <span className="text-muted">({total ? Math.round((r.value / total) * 100) : 0}%)</span>
          </span>
          <span className="col-span-2 block h-2 rounded-full" style={{ background: 'var(--chart-grid)' }}>
            <span
              className="block h-2 rounded-full"
              style={{ width: `${(r.value / max) * 100}%`, background: r.emphasis ? 'var(--chart-series)' : 'var(--chart-dim)' }}
            />
          </span>
        </li>
      ))}
    </ul>
  );
}
