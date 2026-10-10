import { useQuery } from '@tanstack/react-query';
import { rpc } from './rpc';
import type { Addon, Feature } from './types';

/** Add-ons + features with live entitlement counts (admin). */
export function useAddons() {
  return useQuery({
    queryKey: ['addons'],
    queryFn: () => rpc<{ addons: Addon[]; features: Feature[] }>('admin_list_addons'),
    staleTime: 60_000,
  });
}
