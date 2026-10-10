import { X } from 'lucide-react';
import { useEffect, useId, useRef, type ReactNode } from 'react';
import { cx, IconButton } from './ui';

/**
 * Accessible modal built on <dialog>: the browser traps focus, makes the
 * page inert, closes on Escape and restores focus afterwards.
 * `variant="drawer"` slides in from the right (detail panels).
 */
export function Modal({
  open,
  onClose,
  title,
  description,
  children,
  footer,
  size = 'md',
  variant = 'dialog',
  dismissible = true,
}: {
  open: boolean;
  onClose: () => void;
  title: ReactNode;
  description?: ReactNode;
  children: ReactNode;
  footer?: ReactNode;
  size?: 'sm' | 'md' | 'lg' | 'xl';
  variant?: 'dialog' | 'drawer';
  dismissible?: boolean;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const titleId = useId();

  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) d.showModal();
    if (!open && d.open) d.close();
  }, [open]);

  const width = { sm: 'max-w-md', md: 'max-w-xl', lg: 'max-w-3xl', xl: 'max-w-5xl' }[size];
  const drawer = variant === 'drawer';

  return (
    <dialog
      ref={ref}
      aria-labelledby={titleId}
      onCancel={(e) => {
        e.preventDefault();
        if (dismissible) onClose();
      }}
      onClick={(e) => {
        if (dismissible && e.target === ref.current) onClose();
      }}
      className={cx(
        'overflow-hidden bg-surface p-0 text-fg shadow-card backdrop:bg-black/50',
        drawer
          ? cx('m-0 ml-auto h-dvh max-h-dvh w-full border-l border-line', size === 'xl' ? 'max-w-4xl' : 'max-w-2xl')
          : cx('m-auto max-h-[min(92dvh,900px)] w-[calc(100%-1.5rem)] rounded-2xl border border-line', width),
      )}
    >
      {open ? (
        <div className={cx('flex flex-col', drawer ? 'h-dvh' : 'max-h-[calc(min(92dvh,900px)-2px)]')}>
          <header className="flex items-start justify-between gap-3 border-b border-line px-5 py-4">
            <div className="min-w-0">
              <h2 id={titleId} className="text-base font-semibold text-fg">
                {title}
              </h2>
              {description ? <p className="mt-0.5 text-sm text-muted">{description}</p> : null}
            </div>
            {dismissible ? (
              <IconButton label="Close" size="sm" onClick={onClose}>
                <X className="size-4.5" />
              </IconButton>
            ) : null}
          </header>
          <div className="min-h-0 flex-1 overflow-y-auto px-5 py-4">{children}</div>
          {footer ? (
            <footer className="flex flex-wrap items-center justify-end gap-2 border-t border-line bg-surface-2/60 px-5 py-3">
              {footer}
            </footer>
          ) : null}
        </div>
      ) : null}
    </dialog>
  );
}
