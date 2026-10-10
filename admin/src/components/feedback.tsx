import { AlertTriangle, CheckCircle2, Info, X, XCircle } from 'lucide-react';
import { createContext, useCallback, useContext, useMemo, useRef, useState, type ReactNode } from 'react';
import { describeError } from '../lib/errors';
import { Modal } from './Modal';
import { Button, cx, Input } from './ui';

/* ------------------------------------------------------------------ Toasts */

type ToastKind = 'success' | 'error' | 'info';
interface ToastItem {
  id: number;
  kind: ToastKind;
  message: string;
}
interface ToastApi {
  success: (message: string) => void;
  error: (errorOrMessage: unknown) => void;
  info: (message: string) => void;
}

const ToastContext = createContext<ToastApi | null>(null);

/* ------------------------------------------------------------------ Confirm */

export interface ConfirmOptions {
  title: string;
  message?: ReactNode;
  confirmLabel?: string;
  tone?: 'danger' | 'primary';
  /** Requires typing this text before the confirm button enables (destructive actions). */
  typeToConfirm?: string;
}
type ConfirmFn = (opts: ConfirmOptions) => Promise<boolean>;
const ConfirmContext = createContext<ConfirmFn | null>(null);

export function FeedbackProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<ToastItem[]>([]);
  const seq = useRef(0);

  const push = useCallback((kind: ToastKind, message: string) => {
    const id = ++seq.current;
    setToasts((t) => [...t.slice(-3), { id, kind, message }]);
    window.setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), kind === 'error' ? 8000 : 4000);
  }, []);

  const api = useMemo<ToastApi>(
    () => ({
      success: (m) => push('success', m),
      info: (m) => push('info', m),
      error: (e) => push('error', typeof e === 'string' ? e : describeError(e)),
    }),
    [push],
  );

  const [pending, setPending] = useState<(ConfirmOptions & { resolve: (v: boolean) => void }) | null>(null);
  const [typed, setTyped] = useState('');
  const confirm = useCallback<ConfirmFn>(
    (opts) =>
      new Promise<boolean>((resolve) => {
        setTyped('');
        setPending({ ...opts, resolve });
      }),
    [],
  );
  const settle = (v: boolean) => {
    pending?.resolve(v);
    setPending(null);
  };
  const blocked = !!pending?.typeToConfirm && typed.trim() !== pending.typeToConfirm;

  return (
    <ToastContext.Provider value={api}>
      <ConfirmContext.Provider value={confirm}>
        {children}
        <Modal
          open={!!pending}
          onClose={() => settle(false)}
          title={pending?.title ?? ''}
          size="sm"
          footer={
            <>
              <Button variant="ghost" onClick={() => settle(false)}>
                Cancel
              </Button>
              <Button variant={pending?.tone === 'danger' ? 'danger' : 'primary'} disabled={blocked} onClick={() => settle(true)}>
                {pending?.confirmLabel ?? 'Confirm'}
              </Button>
            </>
          }
        >
          <div className="space-y-3 text-sm text-fg-2">
            {pending?.message ? <div>{pending.message}</div> : null}
            {pending?.typeToConfirm ? (
              <label className="block space-y-1.5">
                <span>
                  Type <code className="rounded bg-surface-3 px-1 py-0.5 text-fg">{pending.typeToConfirm}</code> to confirm.
                </span>
                <Input value={typed} onChange={(e) => setTyped(e.target.value)} autoFocus aria-label="Confirmation text" />
              </label>
            ) : null}
          </div>
        </Modal>
        <div
          aria-live="polite"
          className="pointer-events-none fixed inset-x-0 bottom-0 z-50 flex flex-col items-center gap-2 p-4 sm:items-end"
        >
          {toasts.map((t) => (
            <div
              key={t.id}
              role={t.kind === 'error' ? 'alert' : 'status'}
              className={cx(
                'pointer-events-auto flex w-full max-w-sm items-start gap-2.5 rounded-xl border bg-surface px-3.5 py-3 text-sm shadow-card',
                t.kind === 'error' ? 'border-danger/40' : 'border-line',
              )}
            >
              {t.kind === 'success' ? (
                <CheckCircle2 className="mt-0.5 size-4 shrink-0 text-success" aria-hidden />
              ) : t.kind === 'error' ? (
                <XCircle className="mt-0.5 size-4 shrink-0 text-danger" aria-hidden />
              ) : (
                <Info className="mt-0.5 size-4 shrink-0 text-info" aria-hidden />
              )}
              <p className="min-w-0 flex-1 break-words text-fg">{t.message}</p>
              <button
                type="button"
                aria-label="Dismiss"
                className="text-muted hover:text-fg"
                onClick={() => setToasts((all) => all.filter((x) => x.id !== t.id))}
              >
                <X className="size-4" />
              </button>
            </div>
          ))}
        </div>
      </ConfirmContext.Provider>
    </ToastContext.Provider>
  );
}

export function useToast(): ToastApi {
  const ctx = useContext(ToastContext);
  if (!ctx) throw new Error('useToast outside FeedbackProvider');
  return ctx;
}

export function useConfirm(): ConfirmFn {
  const ctx = useContext(ConfirmContext);
  if (!ctx) throw new Error('useConfirm outside FeedbackProvider');
  return ctx;
}

export function WarningText({ children }: { children: ReactNode }) {
  return (
    <p className="flex items-start gap-2 text-warning">
      <AlertTriangle className="mt-0.5 size-4 shrink-0" aria-hidden />
      <span>{children}</span>
    </p>
  );
}
