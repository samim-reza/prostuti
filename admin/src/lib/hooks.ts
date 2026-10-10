import { useEffect, useState } from 'react';

/** The value, settled for `ms` milliseconds (search boxes). */
export function useDebounced<T>(value: T, ms = 300): T {
  const [settled, setSettled] = useState(value);
  useEffect(() => {
    const t = window.setTimeout(() => setSettled(value), ms);
    return () => window.clearTimeout(t);
  }, [value, ms]);
  return settled;
}

/** document.title for the current page. */
export function usePageTitle(title: string): void {
  useEffect(() => {
    document.title = title ? `${title} · Prostuti Admin` : 'Prostuti Admin';
  }, [title]);
}
