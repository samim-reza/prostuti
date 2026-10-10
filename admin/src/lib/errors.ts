/**
 * Every backend failure becomes an ApiError with the machine code the RPC
 * raised (`raise exception 'promo_in_use' using errcode = 'PT409'`), so the UI
 * can show a human sentence instead of SQL.
 */
export class ApiError extends Error {
  readonly code: string;
  readonly sqlState: string | null;
  readonly detail: string | null;
  readonly hint: string | null;

  constructor(message: string, opts: { code: string; sqlState?: string | null; detail?: string | null; hint?: string | null }) {
    super(message);
    this.name = 'ApiError';
    this.code = opts.code;
    this.sqlState = opts.sqlState ?? null;
    this.detail = opts.detail ?? null;
    this.hint = opts.hint ?? null;
  }

  get isForbidden(): boolean {
    return this.sqlState === 'PT403' || this.sqlState === '42501' || this.code === 'forbidden';
  }

  get isClientError(): boolean {
    return !!this.sqlState && /^(PT4|22|23|42|P0)/.test(this.sqlState);
  }
}

interface PostgrestLike {
  message?: unknown;
  code?: unknown;
  details?: unknown;
  hint?: unknown;
}

function str(v: unknown): string | null {
  return typeof v === 'string' && v.length > 0 ? v : null;
}

export function toApiError(e: unknown): ApiError {
  if (e instanceof ApiError) return e;
  if (e instanceof TypeError && /fetch|network/i.test(e.message)) {
    return new ApiError('network_error', { code: 'network_error' });
  }
  if (e && typeof e === 'object') {
    const p = e as PostgrestLike;
    const message = str(p.message) ?? 'unknown_error';
    return new ApiError(message, {
      code: message,
      sqlState: str(p.code),
      detail: str(p.details),
      hint: str(p.hint),
    });
  }
  return new ApiError(String(e), { code: 'unknown_error' });
}

const MESSAGES: Record<string, string> = {
  forbidden: "You don't have permission to do this.",
  not_authenticated: 'Your session has expired. Sign in again.',
  network_error: "Can't reach the server. Check your connection and try again.",
  cannot_change_own_role: "You can't change your own role. Ask another admin.",
  cannot_ban_self: "You can't ban yourself.",
  cannot_ban_admin: 'Admins must be demoted before they can be banned.',
  cannot_ban_staff: "Staff accounts can't be banned from a report. Change their role first.",
  duplicate_question: 'A question with the same text already exists.',
  duplicate_feed: 'A news source with this RSS URL already exists.',
  duplicate_broadcast: 'This broadcast has already been sent.',
  config_conflict: 'Someone else changed this value since you opened it. Reload and review before saving.',
  promo_exists: 'A promo code with this name already exists (codes are case-insensitive).',
  promo_in_use: 'This code has been redeemed, so it cannot be deleted. Deactivate it instead.',
  addon_exists: 'An add-on with this code already exists.',
  schedule_in_use: 'This schedule is in use (active study plans or the default schedule). Deactivate it instead.',
  entitlement_not_active: 'That entitlement has already ended.',
  exam_tracks_missing: 'Exam tracks are not installed on this database yet (migration 0016).',
  rate_limited: 'Too many requests.',
  question_not_found: 'Question not found. It may have been deleted.',
  user_not_found: 'User not found.',
  report_not_found: 'Report not found.',
  note_not_found: 'Note not found. It may have been deleted.',
  schedule_not_found: 'Schedule not found.',
  promo_not_found: 'Promo code not found.',
  addon_not_found: 'Add-on not found.',
  feature_not_found: 'Feature not found.',
  track_not_found: 'Exam track not found.',
  source_not_found: 'News source not found.',
  entitlement_not_found: 'Entitlement not found.',
  invalid_stage: 'Unknown pipeline stage.',
  'Invalid login credentials': 'Wrong e-mail or password.',
  'Email not confirmed': 'This e-mail address has not been confirmed yet.',
};

/** A sentence that is safe to show to staff. */
export function describeError(e: unknown): string {
  const err = toApiError(e);
  if (err.sqlState === 'PGRST301' || /jwt expired/i.test(err.message)) {
    return 'Your session has expired. Sign in again.';
  }
  if (err.code === 'rate_limited' || err.sqlState === 'PT429') {
    const seconds = err.hint?.match(/retry_after:(\d+)/)?.[1];
    return seconds ? `Too many requests. Try again in ${seconds}s.` : 'Too many requests. Try again shortly.';
  }
  if (err.code === 'duplicate_question' && err.detail) {
    return `A question with the same text already exists (#${err.detail}).`;
  }
  const known = MESSAGES[err.code];
  if (known) return err.hint && err.code !== 'rate_limited' ? `${known} ${err.hint}` : known;
  if (err.code.startsWith('invalid_') || err.sqlState === 'PT400') {
    const what = err.code.replace(/^invalid_/, '').replace(/_/g, ' ');
    return err.detail ? `Invalid ${what}: ${err.detail}` : `Invalid ${what}.`;
  }
  if (err.code.endsWith('_not_found') || err.sqlState === 'PT404') return 'Not found. It may have been deleted.';
  return err.detail ? `${err.message} (${err.detail})` : err.message;
}
