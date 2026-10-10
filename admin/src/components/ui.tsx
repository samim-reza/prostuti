import { AlertTriangle, Check, Copy, Inbox, Loader2, RefreshCw } from 'lucide-react';
import {
  forwardRef,
  useId,
  useState,
  type ButtonHTMLAttributes,
  type InputHTMLAttributes,
  type ReactNode,
  type SelectHTMLAttributes,
  type TextareaHTMLAttributes,
} from 'react';
import { NavLink } from 'react-router';
import { describeError } from '../lib/errors';
import { fmtCompact } from '../lib/format';

export function cx(...parts: (string | false | null | undefined)[]): string {
  return parts.filter(Boolean).join(' ');
}

/* ------------------------------------------------------------------ Buttons */

type Variant = 'primary' | 'secondary' | 'ghost' | 'danger' | 'danger-ghost';
type Size = 'sm' | 'md';

const VARIANTS: Record<Variant, string> = {
  primary: 'bg-brand text-brand-fg hover:bg-brand-strong border border-transparent shadow-sm',
  secondary: 'bg-surface text-fg border border-line-strong hover:bg-surface-2',
  ghost: 'bg-transparent text-fg-2 border border-transparent hover:bg-surface-2 hover:text-fg',
  danger: 'bg-danger text-white border border-transparent hover:opacity-90 dark:text-[#1a0508]',
  'danger-ghost': 'bg-transparent text-danger border border-transparent hover:bg-danger-soft',
};
const SIZES: Record<Size, string> = {
  sm: 'h-8 px-2.5 text-[0.8125rem] gap-1.5 rounded-lg',
  md: 'h-10 px-3.5 text-sm gap-2 rounded-lg',
};

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  size?: Size;
  loading?: boolean;
  icon?: ReactNode;
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  { variant = 'secondary', size = 'md', loading = false, icon, className, children, disabled, type = 'button', ...rest },
  ref,
) {
  return (
    <button
      ref={ref}
      type={type}
      disabled={disabled || loading}
      aria-busy={loading || undefined}
      className={cx(
        'inline-flex shrink-0 items-center justify-center font-medium whitespace-nowrap transition-colors select-none',
        'disabled:cursor-not-allowed disabled:opacity-55',
        VARIANTS[variant],
        SIZES[size],
        className,
      )}
      {...rest}
    >
      {loading ? <Loader2 className="size-4 animate-spin" aria-hidden /> : icon}
      {children}
    </button>
  );
});

export function IconButton({
  label,
  children,
  className,
  size = 'md',
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & { label: string; size?: Size }) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      className={cx(
        'inline-flex shrink-0 items-center justify-center rounded-lg text-fg-2 transition-colors hover:bg-surface-2 hover:text-fg disabled:opacity-50',
        size === 'sm' ? 'size-8' : 'size-10',
        className,
      )}
      {...rest}
    >
      {children}
    </button>
  );
}

/* ------------------------------------------------------------------ Form controls */

const CONTROL =
  'rounded-lg border border-line-strong bg-surface px-3 text-sm text-fg placeholder:text-muted ' +
  'focus:border-focus focus:outline-none focus:ring-2 focus:ring-focus/25 disabled:opacity-60 ' +
  'aria-[invalid=true]:border-danger';

/** Full width unless the caller sets an explicit width (utility classes don't merge). */
function control(className: string | undefined, extra: string): string {
  const c = className ?? '';
  const base = /(^|\s)h-/.test(c) ? extra.replace(/(^|\s)h-\S+/g, '') : extra;
  return cx(CONTROL, base, /(^|\s)w-/.test(c) ? null : 'w-full', className);
}

export const Input = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement>>(function Input({ className, ...rest }, ref) {
  return <input ref={ref} className={control(className, 'h-10')} {...rest} />;
});

export const Textarea = forwardRef<HTMLTextAreaElement, TextareaHTMLAttributes<HTMLTextAreaElement>>(function Textarea(
  { className, rows = 3, ...rest },
  ref,
) {
  return <textarea ref={ref} rows={rows} className={control(className, 'py-2 leading-relaxed')} {...rest} />;
});

export const Select = forwardRef<HTMLSelectElement, SelectHTMLAttributes<HTMLSelectElement>>(function Select(
  { className, children, ...rest },
  ref,
) {
  return (
    <select ref={ref} className={control(className, 'h-10 pr-8')} {...rest}>
      {children}
    </select>
  );
});

export function Field({
  label,
  hint,
  error,
  children,
  className,
  htmlFor,
}: {
  label: ReactNode;
  hint?: ReactNode;
  error?: string | null;
  children: ReactNode;
  className?: string;
  htmlFor?: string;
}) {
  return (
    <div className={cx('flex flex-col gap-1.5', className)}>
      <label htmlFor={htmlFor} className="text-[0.8125rem] font-medium text-fg-2">
        {label}
      </label>
      {children}
      {error ? (
        <p className="text-xs text-danger" role="alert">
          {error}
        </p>
      ) : hint ? (
        <p className="text-xs text-muted">{hint}</p>
      ) : null}
    </div>
  );
}

export function Checkbox({
  label,
  checked,
  onChange,
  disabled,
  className,
}: {
  label: ReactNode;
  checked: boolean;
  onChange: (v: boolean) => void;
  disabled?: boolean;
  className?: string;
}) {
  return (
    <label className={cx('inline-flex cursor-pointer items-center gap-2 text-sm text-fg-2', disabled && 'opacity-60', className)}>
      <input
        type="checkbox"
        className="size-4 rounded border-line-strong accent-[var(--brand)]"
        checked={checked}
        disabled={disabled}
        onChange={(e) => onChange(e.target.checked)}
      />
      {label}
    </label>
  );
}

export function Switch({
  checked,
  onChange,
  label,
  disabled,
  description,
}: {
  checked: boolean;
  onChange: (v: boolean) => void;
  label: ReactNode;
  disabled?: boolean;
  description?: ReactNode;
}) {
  const id = useId();
  return (
    <div className="flex items-start gap-3">
      <button
        id={id}
        type="button"
        role="switch"
        aria-checked={checked}
        disabled={disabled}
        onClick={() => onChange(!checked)}
        className={cx(
          'relative mt-0.5 inline-flex h-6 w-11 shrink-0 items-center rounded-full border transition-colors disabled:opacity-50',
          checked ? 'border-brand bg-brand' : 'border-line-strong bg-surface-3',
        )}
      >
        <span
          className={cx(
            'inline-block size-4.5 rounded-full bg-white shadow transition-transform',
            checked ? 'translate-x-5.5' : 'translate-x-0.5',
          )}
        />
      </button>
      <label htmlFor={id} className="cursor-pointer text-sm">
        <span className="font-medium text-fg">{label}</span>
        {description ? <span className="block text-xs text-muted">{description}</span> : null}
      </label>
    </div>
  );
}

/* ------------------------------------------------------------------ Display */

export type Tone = 'neutral' | 'brand' | 'success' | 'warning' | 'danger' | 'info';
const TONES: Record<Tone, string> = {
  neutral: 'bg-surface-3 text-fg-2',
  brand: 'bg-brand-soft text-brand-strong dark:text-brand',
  success: 'bg-success-soft text-success',
  warning: 'bg-warning-soft text-warning',
  danger: 'bg-danger-soft text-danger',
  info: 'bg-info-soft text-info',
};

export function Badge({
  tone = 'neutral',
  children,
  className,
  icon,
}: {
  tone?: Tone;
  children: ReactNode;
  className?: string;
  icon?: ReactNode;
}) {
  return (
    <span
      className={cx(
        'inline-flex items-center gap-1 rounded-md px-1.5 py-0.5 text-xs font-medium whitespace-nowrap',
        TONES[tone],
        className,
      )}
    >
      {icon}
      {children}
    </span>
  );
}

export function Card({
  children,
  className,
  title,
  actions,
  pad = true,
}: {
  children: ReactNode;
  className?: string;
  title?: ReactNode;
  actions?: ReactNode;
  pad?: boolean;
}) {
  return (
    <section className={cx('card', className)}>
      {title || actions ? (
        <header className="flex flex-wrap items-center justify-between gap-2 border-b border-line px-4 py-3">
          {title ? <h2 className="text-sm font-semibold text-fg">{title}</h2> : <span />}
          {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
        </header>
      ) : null}
      <div className={pad ? 'p-4' : undefined}>{children}</div>
    </section>
  );
}

export function Spinner({ label = 'Loading', className }: { label?: string; className?: string }) {
  return (
    <div role="status" className={cx('flex items-center justify-center gap-2 py-10 text-sm text-muted', className)}>
      <Loader2 className="size-5 animate-spin" aria-hidden />
      <span>{label}…</span>
    </div>
  );
}

export function Skeleton({ className }: { className?: string }) {
  return <div className={cx('animate-pulse rounded-md bg-surface-3', className)} aria-hidden />;
}

export function EmptyState({ title, children, icon }: { title: ReactNode; children?: ReactNode; icon?: ReactNode }) {
  return (
    <div className="flex flex-col items-center justify-center gap-2 px-4 py-12 text-center">
      <div className="text-muted">{icon ?? <Inbox className="size-8" aria-hidden />}</div>
      <p className="font-medium text-fg">{title}</p>
      {children ? <div className="max-w-md text-sm text-muted">{children}</div> : null}
    </div>
  );
}

export function ErrorState({ error, onRetry, compact }: { error: unknown; onRetry?: () => void; compact?: boolean }) {
  return (
    <div
      role="alert"
      className={cx(
        'flex flex-wrap items-start gap-3 rounded-lg border border-danger/30 bg-danger-soft text-sm text-danger',
        compact ? 'px-3 py-2' : 'm-4 px-4 py-3',
      )}
    >
      <AlertTriangle className="mt-0.5 size-4 shrink-0" aria-hidden />
      <p className="min-w-0 flex-1 break-words">{describeError(error)}</p>
      {onRetry ? (
        <Button size="sm" variant="secondary" icon={<RefreshCw className="size-3.5" />} onClick={onRetry}>
          Retry
        </Button>
      ) : null}
    </div>
  );
}

export function Notice({ tone = 'info', children, icon }: { tone?: Tone; children: ReactNode; icon?: ReactNode }) {
  return (
    <div className={cx('flex items-start gap-2.5 rounded-lg px-3 py-2.5 text-sm', TONES[tone])}>
      {icon ? <span className="mt-0.5 shrink-0">{icon}</span> : null}
      <div className="min-w-0 flex-1">{children}</div>
    </div>
  );
}

export function PageHeader({ title, description, actions }: { title: string; description?: ReactNode; actions?: ReactNode }) {
  return (
    <div className="mb-5 flex flex-wrap items-end justify-between gap-3">
      <div className="min-w-0">
        <h1 className="text-xl font-semibold tracking-tight text-fg sm:text-2xl">{title}</h1>
        {description ? <p className="mt-1 max-w-3xl text-sm text-muted">{description}</p> : null}
      </div>
      {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
    </div>
  );
}

export function TabLinks({ tabs }: { tabs: { to: string; label: string; end?: boolean }[] }) {
  return (
    <nav aria-label="Sections" className="mb-5 flex gap-1 overflow-x-auto shadow-[inset_0_-1px_0_var(--line)]">
      {tabs.map((t) => (
        <NavLink
          key={t.to}
          to={t.to}
          end={t.end}
          className={({ isActive }) =>
            cx(
              'border-b-2 px-3 py-2 text-sm font-medium whitespace-nowrap transition-colors',
              isActive ? 'border-brand text-fg' : 'border-transparent text-muted hover:text-fg',
            )
          }
        >
          {t.label}
        </NavLink>
      ))}
    </nav>
  );
}

export function Segmented<T extends string>({
  value,
  onChange,
  options,
  label,
}: {
  value: T;
  onChange: (v: T) => void;
  options: { value: T; label: string }[];
  label: string;
}) {
  return (
    <div role="radiogroup" aria-label={label} className="inline-flex rounded-lg border border-line-strong bg-surface p-0.5">
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          role="radio"
          aria-checked={value === o.value}
          onClick={() => onChange(o.value)}
          className={cx(
            'rounded-md px-2.5 py-1 text-[0.8125rem] font-medium transition-colors',
            value === o.value ? 'bg-brand-soft text-brand-strong dark:text-brand' : 'text-muted hover:text-fg',
          )}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

export function Stat({
  label,
  value,
  sub,
  tone,
  icon,
}: {
  label: string;
  value: number | string | null | undefined;
  sub?: ReactNode;
  tone?: Tone;
  icon?: ReactNode;
}) {
  const shown = typeof value === 'number' ? fmtCompact(value) : (value ?? '—');
  return (
    <div className="card flex min-w-0 flex-col gap-1 p-4">
      <div className="flex items-center justify-between gap-2 text-[0.8125rem] text-muted">
        <span className="truncate">{label}</span>
        {icon ? (
          <span className={cx('shrink-0', tone === 'danger' ? 'text-danger' : tone === 'warning' ? 'text-warning' : 'text-muted')}>
            {icon}
          </span>
        ) : null}
      </div>
      <div className="text-2xl font-semibold tracking-tight text-fg">{shown}</div>
      {sub ? <div className="text-xs text-muted">{sub}</div> : null}
    </div>
  );
}

export function KeyValue({ items }: { items: [ReactNode, ReactNode][] }) {
  return (
    <dl className="grid grid-cols-[minmax(7rem,auto)_1fr] gap-x-4 gap-y-2 text-sm">
      {items.map(([k, v], i) => (
        <div key={i} className="contents">
          <dt className="text-muted">{k}</dt>
          <dd className="min-w-0 break-words text-fg">{v ?? '—'}</dd>
        </div>
      ))}
    </dl>
  );
}

export function LoadMore({
  hasMore,
  loading,
  onClick,
  count,
}: {
  hasMore: boolean;
  loading: boolean;
  onClick: () => void;
  count?: number;
}) {
  if (!hasMore && count === undefined) return null;
  return (
    <div className="flex items-center justify-between gap-2 border-t border-line px-4 py-3 text-xs text-muted">
      <span>{count !== undefined ? `${count} loaded` : ''}</span>
      {hasMore ? (
        <Button size="sm" variant="secondary" loading={loading} onClick={onClick}>
          Load more
        </Button>
      ) : (
        <span>End of list</span>
      )}
    </div>
  );
}

export function CopyButton({ text, label = 'Copy' }: { text: string; label?: string }) {
  const [done, setDone] = useState(false);
  return (
    <IconButton
      size="sm"
      label={done ? 'Copied' : label}
      onClick={() => {
        void navigator.clipboard?.writeText(text).then(() => {
          setDone(true);
          window.setTimeout(() => setDone(false), 1500);
        });
      }}
    >
      {done ? <Check className="size-4 text-success" /> : <Copy className="size-4" />}
    </IconButton>
  );
}

export function Avatar({ name, url, size = 32 }: { name: string; url?: string | null; size?: number }) {
  const [broken, setBroken] = useState(false);
  const initials = name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase())
    .join('');
  if (url && !broken) {
    return (
      <img
        src={url}
        alt=""
        width={size}
        height={size}
        loading="lazy"
        onError={() => setBroken(true)}
        className="shrink-0 rounded-full bg-surface-3 object-cover"
        style={{ width: size, height: size }}
      />
    );
  }
  return (
    <span
      aria-hidden
      className="inline-flex shrink-0 items-center justify-center rounded-full bg-brand-soft text-xs font-semibold text-brand-strong dark:text-brand"
      style={{ width: size, height: size }}
    >
      {initials || '?'}
    </span>
  );
}

/** Renders text with the right language hint so Bangla gets the Bangla font. */
export function Text({ children, className, lang }: { children: string | null | undefined; className?: string; lang?: 'bn' | 'en' }) {
  const isBn = lang ? lang === 'bn' : /[ঀ-৿]/.test(children ?? '');
  return (
    <span lang={isBn ? 'bn' : undefined} className={className}>
      {children}
    </span>
  );
}

export function TableWrap({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={cx('overflow-x-auto', className)}>{children}</div>;
}
