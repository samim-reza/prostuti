/** Formatting helpers. The product runs on Bangladesh time (UTC+6, no DST). */
export const BD_TZ = 'Asia/Dhaka';

const dateTimeFmt = new Intl.DateTimeFormat('en-GB', {
  timeZone: BD_TZ,
  day: 'numeric',
  month: 'short',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
});
const dateFmt = new Intl.DateTimeFormat('en-GB', { timeZone: 'UTC', day: 'numeric', month: 'short', year: 'numeric' });
const weekdayFmt = new Intl.DateTimeFormat('en-GB', { timeZone: 'UTC', weekday: 'short', day: 'numeric', month: 'short' });
const shortDayFmt = new Intl.DateTimeFormat('en-GB', { timeZone: 'UTC', day: 'numeric', month: 'short' });
const numberFmt = new Intl.NumberFormat('en-US');
const compactFmt = new Intl.NumberFormat('en-US', { notation: 'compact', maximumFractionDigits: 1 });
const relFmt = new Intl.RelativeTimeFormat('en', { numeric: 'auto' });
const bdDayFmt = new Intl.DateTimeFormat('en-CA', { timeZone: BD_TZ, year: 'numeric', month: '2-digit', day: '2-digit' });

/** "11 Oct 2026, 14:05" (Bangladesh time). */
export function fmtDateTime(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? '—' : `${dateTimeFmt.format(d)}`;
}

/** A calendar date ("2026-10-11") → "11 Oct 2026". */
export function fmtDate(day: string | null | undefined): string {
  if (!day) return '—';
  const d = new Date(`${day.slice(0, 10)}T00:00:00Z`);
  return Number.isNaN(d.getTime()) ? day : dateFmt.format(d);
}

export function fmtWeekday(day: string): string {
  return weekdayFmt.format(new Date(`${day.slice(0, 10)}T00:00:00Z`));
}

export function fmtShortDay(day: string): string {
  return shortDayFmt.format(new Date(`${day.slice(0, 10)}T00:00:00Z`));
}

/** "3 min ago", "in 2 days". */
export function fmtRelative(iso: string | null | undefined): string {
  if (!iso) return '—';
  const diff = (new Date(iso).getTime() - Date.now()) / 1000;
  if (Number.isNaN(diff)) return '—';
  const abs = Math.abs(diff);
  if (abs < 45) return 'just now';
  if (abs < 3600) return relFmt.format(Math.round(diff / 60), 'minute');
  if (abs < 86400) return relFmt.format(Math.round(diff / 3600), 'hour');
  if (abs < 86400 * 45) return relFmt.format(Math.round(diff / 86400), 'day');
  if (abs < 86400 * 365) return relFmt.format(Math.round(diff / (86400 * 30)), 'month');
  return relFmt.format(Math.round(diff / (86400 * 365)), 'year');
}

export function fmtNumber(n: number | string | null | undefined): string {
  if (n === null || n === undefined || n === '') return '—';
  const v = typeof n === 'string' ? Number(n) : n;
  return Number.isFinite(v) ? numberFmt.format(v) : '—';
}

export function fmtCompact(n: number | null | undefined): string {
  if (n === null || n === undefined || !Number.isFinite(n)) return '—';
  return Math.abs(n) < 1000 ? numberFmt.format(n) : compactFmt.format(n);
}

export function fmtUsd(n: number | string | null | undefined, digits = 2): string {
  const v = typeof n === 'string' ? Number(n) : (n ?? 0);
  if (!Number.isFinite(v)) return '—';
  if (v > 0 && v < 0.01) return '<$0.01';
  return `$${v.toFixed(digits)}`;
}

export function fmtBdt(n: number | string | null | undefined): string {
  const v = typeof n === 'string' ? Number(n) : (n ?? 0);
  if (!Number.isFinite(v)) return '—';
  return `৳${numberFmt.format(Math.round(v * 100) / 100)}`;
}

export function fmtPercent(part: number, whole: number, digits = 0): string {
  if (!whole) return '—';
  return `${((part / whole) * 100).toFixed(digits)}%`;
}

/** Today's date in Bangladesh as "YYYY-MM-DD". */
export function bdToday(): string {
  return bdDayFmt.format(new Date());
}

export function addDays(day: string, delta: number): string {
  const d = new Date(`${day}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + delta);
  return d.toISOString().slice(0, 10);
}

/** ISO timestamp → value for <input type="datetime-local"> (browser local time). */
export function toLocalInput(iso: string | null | undefined): string {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  const pad = (x: number) => String(x).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

/** <input type="datetime-local"> value → ISO timestamp (or null when empty). */
export function fromLocalInput(value: string): string | null {
  if (!value) return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

export function truncate(s: string | null | undefined, max: number): string {
  if (!s) return '';
  return s.length > max ? `${s.slice(0, max - 1)}…` : s;
}

/** True when the text is mostly Bangla script (for lang / font hints). */
export function isBangla(s: string | null | undefined): boolean {
  if (!s) return false;
  const bn = s.match(/[ঀ-৿]/g)?.length ?? 0;
  return bn > 0 && bn >= s.replace(/\s/g, '').length * 0.3;
}

export function pluralize(n: number, one: string, many = `${one}s`): string {
  return `${fmtNumber(n)} ${n === 1 ? one : many}`;
}
