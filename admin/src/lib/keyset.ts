import { useInfiniteQuery } from '@tanstack/react-query';
import { useMemo } from 'react';

/**
 * Keyset ("load more") pagination over an RPC. `cursorOf(lastRow)` builds the
 * next cursor; a short page means the end of the list. Never uses OFFSET.
 */
export function useKeyset<T, C>(opts: {
  key: readonly unknown[];
  pageSize: number;
  fetchPage: (cursor: C | null) => Promise<T[]>;
  cursorOf: (last: T) => C;
  enabled?: boolean;
}) {
  const { key, pageSize, fetchPage, cursorOf, enabled = true } = opts;
  const query = useInfiniteQuery({
    queryKey: key,
    queryFn: ({ pageParam }) => fetchPage(pageParam as C | null),
    initialPageParam: null as C | null,
    getNextPageParam: (last: T[]) => (last.length < pageSize || last.length === 0 ? undefined : cursorOf(last[last.length - 1]!)),
    enabled,
  });
  const items = useMemo(() => query.data?.pages.flat() ?? [], [query.data]);
  return { ...query, items };
}
