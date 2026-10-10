import { Lock, ShieldAlert } from 'lucide-react';
import { useState, type FormEvent } from 'react';
import { Button, Field, Input, Notice } from '../components/ui';
import { describeError } from '../lib/errors';
import { usePageTitle } from '../lib/hooks';
import { useAuth } from './AuthProvider';

const NOTICES: Record<string, string> = {
  not_staff: 'This account is not a staff account. Only moderators and admins can use the console. Ask an admin to change your role.',
  banned: 'This account is banned.',
  session_expired: 'Your session has expired. Please sign in again.',
  profile_error: "Couldn't check your account. Check your connection and sign in again.",
};

export function LoginPage() {
  usePageTitle('Sign in');
  const { state, signIn } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const notice = state.status === 'signed_out' && state.notice ? NOTICES[state.notice] : null;

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await signIn(email, password);
    } catch (err) {
      setError(describeError(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="flex min-h-dvh items-center justify-center bg-bg px-4 py-10">
      <div className="w-full max-w-sm">
        <div className="mb-6 flex flex-col items-center gap-3 text-center">
          <img src="/favicon.svg" alt="" width={56} height={56} className="rounded-2xl shadow-card" />
          <div>
            <h1 className="text-xl font-semibold text-fg">
              Prostuti Admin{' '}
              <span lang="bn" className="text-muted">
                · প্রস্তুতি
              </span>
            </h1>
            <p className="text-sm text-muted">Staff sign-in</p>
          </div>
        </div>
        <form onSubmit={submit} className="card space-y-4 p-5 shadow-card" noValidate>
          {notice ? (
            <Notice tone="warning" icon={<ShieldAlert className="size-4" />}>
              {notice}
            </Notice>
          ) : null}
          <Field label="E-mail" htmlFor="email">
            <Input
              id="email"
              type="email"
              autoComplete="username"
              inputMode="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              autoFocus
            />
          </Field>
          <Field label="Password" htmlFor="password">
            <Input
              id="password"
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </Field>
          {error ? (
            <p role="alert" className="text-sm text-danger">
              {error}
            </p>
          ) : null}
          <Button
            type="submit"
            variant="primary"
            className="w-full"
            loading={busy}
            disabled={!email || !password}
            icon={<Lock className="size-4" />}
          >
            Sign in
          </Button>
          <p className="text-center text-xs text-muted">Forgot your password? Reset it from the Prostuti app, then sign in here.</p>
        </form>
      </div>
    </main>
  );
}
