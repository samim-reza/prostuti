import { useState, type FormEvent } from 'react';
import { useToast } from '../components/feedback';
import { Modal } from '../components/Modal';
import { Button, Field, Input } from '../components/ui';
import { describeError } from '../lib/errors';
import { supabase } from '../lib/supabase';
import { useStaff } from './AuthProvider';

/** Verifies the current password (fresh sign-in), then sets the new one. */
export function ChangePasswordDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const staff = useStaff();
  const toast = useToast();
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [again, setAgain] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const tooShort = next.length > 0 && next.length < 8;
  const mismatch = again.length > 0 && again !== next;
  const same = next.length > 0 && next === current;
  const valid = current.length > 0 && next.length >= 8 && next === again && !same;

  function reset() {
    setCurrent('');
    setNext('');
    setAgain('');
    setError(null);
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!valid) return;
    setBusy(true);
    setError(null);
    try {
      const check = await supabase.auth.signInWithPassword({ email: staff.email, password: current });
      if (check.error) {
        setError('Your current password is incorrect.');
        return;
      }
      const { error: updateError } = await supabase.auth.updateUser({ password: next });
      if (updateError) {
        setError(describeError(updateError));
        return;
      }
      toast.success('Password changed.');
      reset();
      onClose();
    } catch (err) {
      setError(describeError(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal
      open={open}
      onClose={() => {
        reset();
        onClose();
      }}
      title="Change password"
      description={staff.email}
      size="sm"
    >
      <form onSubmit={submit} className="space-y-4" noValidate>
        <Field label="Current password" htmlFor="cp-current">
          <Input
            id="cp-current"
            type="password"
            autoComplete="current-password"
            value={current}
            onChange={(e) => setCurrent(e.target.value)}
          />
        </Field>
        <Field
          label="New password"
          htmlFor="cp-new"
          hint="At least 8 characters."
          error={tooShort ? 'At least 8 characters.' : same ? 'Choose a different password.' : null}
        >
          <Input
            id="cp-new"
            type="password"
            autoComplete="new-password"
            value={next}
            aria-invalid={tooShort || same}
            onChange={(e) => setNext(e.target.value)}
          />
        </Field>
        <Field label="Repeat new password" htmlFor="cp-again" error={mismatch ? 'Passwords do not match.' : null}>
          <Input
            id="cp-again"
            type="password"
            autoComplete="new-password"
            value={again}
            aria-invalid={mismatch}
            onChange={(e) => setAgain(e.target.value)}
          />
        </Field>
        {error ? (
          <p role="alert" className="text-sm text-danger">
            {error}
          </p>
        ) : null}
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" variant="primary" loading={busy} disabled={!valid}>
            Change password
          </Button>
        </div>
      </form>
    </Modal>
  );
}
