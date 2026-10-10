import type { Session } from '@supabase/supabase-js';
import { useQueryClient } from '@tanstack/react-query';
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { toApiError } from '../lib/errors';
import { supabase } from '../lib/supabase';
import type { Role } from '../lib/types';

export interface StaffProfile {
  id: string;
  email: string;
  username: string | null;
  full_name: string | null;
  avatar_url: string | null;
  role: Extract<Role, 'admin' | 'moderator'>;
}

type Notice = 'not_staff' | 'banned' | 'session_expired' | 'profile_error';

type AuthState =
  { status: 'loading' } | { status: 'signed_out'; notice?: Notice } | { status: 'ready'; session: Session; profile: StaffProfile };

interface AuthApi {
  state: AuthState;
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthApi | null>(null);

/**
 * Session + staff check. The console UI only hides what a role can't use;
 * every RPC re-checks is_admin() / is_staff() in Postgres.
 */
export function AuthProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<AuthState>({ status: 'loading' });
  const queryClient = useQueryClient();
  const checking = useRef<string | null>(null);

  const evaluate = useCallback(
    async (session: Session | null) => {
      if (!session) {
        setState((prev) => (prev.status === 'signed_out' ? prev : { status: 'signed_out' }));
        queryClient.clear();
        return;
      }
      const token = session.access_token;
      if (checking.current === token) return;
      checking.current = token;
      const { data, error } = await supabase
        .from('profiles')
        .select('id, username, full_name, avatar_url, role, is_banned')
        .eq('id', session.user.id)
        .maybeSingle();
      checking.current = null;
      if (error) {
        const err = toApiError(error);
        await supabase.auth.signOut({ scope: 'local' });
        setState({ status: 'signed_out', notice: err.code === 'network_error' ? 'profile_error' : 'session_expired' });
        return;
      }
      const row = data as {
        id: string;
        username: string | null;
        full_name: string | null;
        avatar_url: string | null;
        role: Role;
        is_banned: boolean;
      } | null;
      if (!row || (row.role !== 'admin' && row.role !== 'moderator')) {
        await supabase.auth.signOut({ scope: 'local' });
        setState({ status: 'signed_out', notice: 'not_staff' });
        return;
      }
      if (row.is_banned) {
        await supabase.auth.signOut({ scope: 'local' });
        setState({ status: 'signed_out', notice: 'banned' });
        return;
      }
      setState({
        status: 'ready',
        session,
        profile: {
          id: row.id,
          email: session.user.email ?? '',
          username: row.username,
          full_name: row.full_name,
          avatar_url: row.avatar_url,
          role: row.role,
        },
      });
    },
    [queryClient],
  );

  useEffect(() => {
    let active = true;
    void supabase.auth.getSession().then(({ data }) => {
      if (active) void evaluate(data.session);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((event, session) => {
      // Never await Supabase calls inside this callback (it holds the auth lock).
      window.setTimeout(() => {
        if (!active) return;
        if (event === 'SIGNED_OUT') {
          setState((prev) => (prev.status === 'signed_out' ? prev : { status: 'signed_out' }));
          queryClient.clear();
        } else if (event === 'SIGNED_IN' || event === 'USER_UPDATED' || event === 'INITIAL_SESSION') {
          void evaluate(session);
        } else if (event === 'TOKEN_REFRESHED' && session) {
          setState((prev) => (prev.status === 'ready' ? { ...prev, session } : prev));
        }
      }, 0);
    });
    // Re-check the role when the tab becomes visible again: a demoted or
    // banned staff member loses the console without waiting for a reload.
    const onVisible = () => {
      if (document.visibilityState !== 'visible') return;
      void supabase.auth.getSession().then(({ data }) => {
        checking.current = null;
        if (active && data.session) void evaluate(data.session);
      });
    };
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      active = false;
      sub.subscription.unsubscribe();
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [evaluate, queryClient]);

  const api = useMemo<AuthApi>(
    () => ({
      state,
      signIn: async (email, password) => {
        const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
        if (error) throw toApiError(error);
      },
      signOut: async () => {
        await supabase.auth.signOut({ scope: 'local' });
        queryClient.clear();
        setState({ status: 'signed_out' });
      },
    }),
    [state, queryClient],
  );

  return <AuthContext.Provider value={api}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthApi {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth outside AuthProvider');
  return ctx;
}

/** The signed-in staff profile (only valid inside the authenticated shell). */
export function useStaff(): StaffProfile {
  const { state } = useAuth();
  if (state.status !== 'ready') throw new Error('useStaff without a staff session');
  return state.profile;
}

export function useIsAdmin(): boolean {
  return useStaff().role === 'admin';
}
