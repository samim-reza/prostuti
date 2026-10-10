/** Shapes returned by the admin RPCs (supabase/migrations/*admin_console.sql). */

export type Role = 'user' | 'moderator' | 'admin';
export type QuestionStatus = 'draft' | 'published' | 'rejected' | 'archived';
export type ReviewStatus = 'unverified' | 'verified' | 'flagged';
export type SourceKind = 'previous_exam' | 'book' | 'newspaper' | 'website' | 'ai_generated' | 'curated';
export type TrackCode = 'bcs' | 'bank' | 'govt';

export const TRACKS: { code: TrackCode; label: string }[] = [
  { code: 'bcs', label: 'BCS' },
  { code: 'bank', label: 'Bank' },
  { code: 'govt', label: 'Others' },
];
export const trackLabel = (code: string): string => TRACKS.find((t) => t.code === code)?.label ?? code;

export const SOURCE_KINDS: { value: SourceKind; label: string }[] = [
  { value: 'previous_exam', label: 'Previous exam' },
  { value: 'book', label: 'Book' },
  { value: 'newspaper', label: 'Newspaper' },
  { value: 'website', label: 'Website' },
  { value: 'ai_generated', label: 'AI generated' },
  { value: 'curated', label: 'Curated' },
];

export interface Subject {
  id: number;
  code: string;
  name_bn: string;
  name_en: string;
  bcs_marks: number;
  sort: number;
}
export interface Topic {
  id: number;
  subject_id: number;
  code: string;
  name_bn: string;
  name_en: string;
  is_general: boolean;
  sort: number;
}
export interface Source {
  id: number;
  kind: SourceKind;
  name: string;
  year: number | null;
  publisher: string | null;
  url: string | null;
  exam_type: string | null;
}
export interface ExamType {
  code: string;
  name_bn: string;
  name_en: string;
  sort: number;
}

export interface ConsoleStats {
  generated_at: string;
  bd_today: string;
  users: {
    total: number;
    new_7d: number;
    new_today: number;
    active_today: number;
    active_7d: number;
    banned: number;
    staff: number;
  };
  exams_today: { submitted: number; by_kind: Record<string, number> };
  questions: { status: QuestionStatus; review_status: ReviewStatus; count: number }[];
  reports: { open: number; by_type: Record<string, number> };
  today: {
    notes: { published: number; draft: number; archived: number; missing_en: number };
    daily_exam: { id: number; status: string; title_bn: string; question_count: number; submissions: number } | null;
  };
  ai_7d: {
    calls: number;
    cache_hits: number;
    prompt_tokens: number;
    completion_tokens: number;
    cost_usd: number;
    usd_to_bdt: number | null;
  };
  series: { day: string; signups: number; exams: number; ai_calls: number; ai_cost_usd: number }[];
  client_errors_24h: { events: number; groups: number; fatal: number; users: number } | null;
  pipeline: {
    cron: {
      job: string;
      schedule: string;
      active: boolean;
      status: string | null;
      started_at: string | null;
      ended_at: string | null;
      message: string | null;
    }[];
    recent_runs: { key: string; created_at: string }[];
    news_sources: { total: number; enabled: number; failing: number; last_fetched_at: string | null };
    unprocessed_articles: number;
    pending_replans: number;
    pending_push: number;
  };
}

export interface UserRow {
  id: string;
  username: string | null;
  full_name: string | null;
  email: string | null;
  avatar_url: string | null;
  role: Role;
  is_banned: boolean;
  district: string | null;
  target_exams: string[];
  onboarding_step: string;
  last_active_date: string | null;
  streak_count: number;
  exams_taken: number;
  locale: string;
  created_at: string;
  last_sign_in_at: string | null;
}

export interface Entitlement {
  id: number;
  addon_code: string;
  addon_name: string | null;
  source: 'trial' | 'purchase' | 'promo' | 'admin';
  starts_at: string;
  expires_at: string;
  active: boolean;
  upcoming: boolean;
  created_at: string;
}

export interface UserDetail {
  profile: UserRow & {
    bio: string | null;
    occupation: string | null;
    education: Record<string, unknown>;
    daily_study_minutes: number;
    longest_streak: number;
    friends_count: number;
    posts_count: number;
    target_schedule_id: number | null;
    updated_at: string;
  };
  auth: {
    email: string | null;
    created_at: string | null;
    last_sign_in_at: string | null;
    email_confirmed_at: string | null;
    banned_until: string | null;
    provider: string | null;
  };
  target_schedule: { id: number; title_en: string; title_bn: string; expected_date: string } | null;
  entitlements: Entitlement[];
  exams: {
    submitted: number;
    in_progress: number;
    last_submitted_at: string | null;
    avg_score_pct: number | null;
    by_kind: Record<string, number>;
  };
  attempts: number;
  plan: { id: string; exam_date: string; start_date: string; version: number; daily_minutes: number } | null;
  reports: { against_open: number; filed: number };
  promo_redemptions: { code: string; redeemed_at: string }[];
  payments: { id: string; addon_code: string; amount_bdt: number; provider: string; status: string; created_at: string }[];
  audit: { id: number; action: string; details: Record<string, unknown>; created_at: string; actor: string | null }[];
}

export interface QuestionRow {
  id: number;
  subject_id: number;
  topic_id: number | null;
  stem: string;
  options: string[];
  correct_index: number;
  explanation: string | null;
  difficulty: number;
  language: 'bn' | 'en';
  source_id: number | null;
  source_kind: SourceKind | null;
  source_name: string | null;
  source_ref: string | null;
  source_url: string | null;
  exam_tags: string[];
  year: number | null;
  status: QuestionStatus;
  review_status: ReviewStatus;
  times_answered: number;
  times_correct: number;
  fact_id: number | null;
  created_at: string;
  open_reports: number;
}

export interface QuestionDetail extends Omit<QuestionRow, 'source_kind' | 'source_name' | 'open_reports'> {
  created_by: string | null;
  has_embedding: boolean;
  subject: { id: number; code: string; name_bn: string; name_en: string } | null;
  topic: { id: number; code: string; name_bn: string; name_en: string } | null;
  source: Source | null;
  fact: {
    id: number;
    fact: string;
    fact_en: string | null;
    status: string;
    first_seen_date: string;
    superseded_by: number | null;
    source_links: { url?: string; title?: string; source?: string }[];
  } | null;
  created_by_user: { id: string; username: string | null; full_name: string | null } | null;
  answer_stats: { selected_index: number | null; count: number }[];
  reports: { open: number; total: number };
  daily_exam_dates: string[];
  ai_explanation: string | null;
}

export interface ReportRow {
  id: number;
  target_type: 'post' | 'comment' | 'user' | 'message' | 'question';
  target_id: string;
  reason: string;
  details: string | null;
  status: 'open' | 'actioned' | 'dismissed';
  created_at: string;
  reporter: { id: string; username: string | null; full_name: string | null };
  preview: string | null;
}

export interface ReportTarget {
  target_type: ReportRow['target_type'];
  target_id: string;
  content: Record<string, unknown> | null;
  author: {
    id: string;
    username: string | null;
    full_name: string | null;
    avatar_url: string | null;
    is_banned: boolean;
    role: Role;
  } | null;
  reports: {
    id: number;
    reason: string;
    details: string | null;
    status: string;
    created_at: string;
    reviewed_at: string | null;
    reporter: { id: string; username: string | null; full_name: string | null };
  }[];
}

export interface KeyFact {
  fact: string;
  tag?: string;
}
export interface ProbableQuestion {
  q: string;
  a: string;
}
export interface NoteRow {
  id: number;
  note_date: string;
  category: string;
  title: string;
  summary: string;
  title_en: string | null;
  summary_en: string | null;
  key_facts: KeyFact[];
  key_facts_en: KeyFact[];
  probable_questions: ProbableQuestion[];
  probable_questions_en: ProbableQuestion[];
  importance: number;
  source_links: { url?: string; title?: string; source?: string }[];
  status: 'draft' | 'published' | 'archived';
  model: string | null;
  fact_count: number;
  created_at: string;
}
export interface NoteDay {
  date: string;
  published: number;
  draft: number;
  archived: number;
  daily_exam: { id: number; status: string; question_count: number } | null;
}

export interface DailyExam {
  id: number;
  exam_date: string;
  title_bn: string;
  title_en: string | null;
  status: string;
  duration_minutes: number;
  negative_mark: number;
  created_at: string;
  question_ids: number[];
  questions: {
    id: number;
    stem: string;
    options: string[];
    correct_index: number;
    explanation: string | null;
    status: QuestionStatus;
    review_status: ReviewStatus;
    source_ref: string | null;
    source_url: string | null;
    subject_id: number;
    times_answered: number;
    times_correct: number;
  }[];
  submissions: { count: number; avg_score: number | null; max_score: number | null; avg_time_seconds: number | null };
}

export interface NewsSource {
  id: number;
  name: string;
  homepage: string | null;
  rss_url: string;
  language: 'bn' | 'en';
  region: 'BD' | 'INT';
  category_hint: string | null;
  priority: number;
  enabled: boolean;
  last_fetched_at: string | null;
  last_error: string | null;
  fail_count: number;
  created_at: string;
  articles_24h: number;
  articles_7d: number;
}

export interface Schedule {
  id: number;
  exam_type: string;
  exam_type_name: string | null;
  title_bn: string;
  title_en: string;
  stage: string;
  expected_date: string;
  is_confirmed: boolean;
  source_url: string | null;
  notes: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
  active_plans: number;
  target_users: number;
  is_default: boolean;
}

export interface ExamTrack {
  code: TrackCode;
  name_bn: string;
  name_en: string;
  description_bn: string | null;
  description_en: string | null;
  sizes: number[];
  full_marks: number;
  negative_mark: number;
  seconds_per_question: number;
  distribution: Record<string, number>;
  sort: number;
  is_active: boolean;
  updated_at?: string;
  available: Record<string, number>;
}

export interface Addon {
  code: string;
  name_bn: string;
  name_en: string;
  description_bn: string | null;
  description_en: string | null;
  features: string[];
  price_bdt: number;
  period_days: number;
  trial_days: number;
  badge: string | null;
  color: string | null;
  icon: string | null;
  is_active: boolean;
  sort: number;
  created_at: string;
  active: Record<string, number>;
  revenue_30d_bdt: number;
}
export interface Feature {
  code: string;
  name_bn: string;
  name_en: string;
  description_bn: string | null;
  description_en: string | null;
  is_free: boolean;
  free_daily_quota: number | null;
  sort: number;
}

export interface Promo {
  code: string;
  addon_code: string;
  addon_name: string | null;
  days: number;
  max_redemptions: number | null;
  redeemed_count: number;
  expires_at: string | null;
  is_active: boolean;
  created_at: string;
  state: 'live' | 'inactive' | 'expired' | 'exhausted';
}

export interface ConfigRow {
  key: string;
  value: unknown;
  description: string | null;
  is_public: boolean;
  updated_at: string;
}

export interface BroadcastSegments {
  total: number;
  districts: { district: string; users: number }[];
  target_exams: { code: string; name_en: string; users: number }[];
  locales: Record<string, number>;
}

export interface ErrorGroup {
  fingerprint: string;
  events: number;
  reports: number;
  users: number;
  first_seen: string;
  last_seen: string;
  fatal: boolean;
  platforms: string[] | null;
  versions: string[] | null;
  error: string;
  route: string | null;
  app_version: string | null;
}
export interface ErrorEvent {
  id: number;
  created_at: string;
  last_seen_at: string;
  occurrences: number;
  user_id: string | null;
  username: string | null;
  app_version: string | null;
  build_number: string | null;
  platform: string | null;
  os: string | null;
  locale: string | null;
  route: string | null;
  context: string | null;
  error: string;
  stack: string | null;
  fatal: boolean;
  fingerprint: string;
}

export interface AiUsageSummary {
  from: string;
  pricing: { usd_to_bdt?: number; models?: Record<string, { input: number; output: number }> };
  by_day: { day: string; calls: number; cache_hits: number; prompt_tokens: number; completion_tokens: number; cost_usd: number }[];
  by_function: {
    function_name: string;
    model: string | null;
    calls: number;
    cache_hits: number;
    prompt_tokens: number;
    completion_tokens: number;
    avg_latency_ms: number | null;
    cost_usd: number;
  }[];
  unpriced_models: string[];
}
export interface AiUsageRow {
  id: number;
  user_id: string | null;
  function_name: string;
  model: string | null;
  prompt_tokens: number | null;
  completion_tokens: number | null;
  cache: string | null;
  latency_ms: number | null;
  created_at: string;
}

export interface AuditRow {
  id: number;
  actor_id: string | null;
  action: string;
  target_type: string | null;
  target_id: string | null;
  details: Record<string, unknown>;
  created_at: string;
  actor: { username: string | null; full_name: string | null } | null;
}
