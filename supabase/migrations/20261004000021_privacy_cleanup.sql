-- ============================================================================
-- 0021 · Privacy cleanup
-- AI usage rows keep their cost accounting after an account is deleted, but
-- no longer point at the person (the privacy policy promises deletion).
-- ============================================================================

update public.ai_usage_log l set user_id = null
 where l.user_id is not null and not exists (select 1 from auth.users u where u.id = l.user_id);

alter table public.ai_usage_log drop constraint if exists ai_usage_log_user_id_fkey;
alter table public.ai_usage_log
  add constraint ai_usage_log_user_id_fkey foreign key (user_id) references auth.users (id) on delete set null;
create index if not exists ai_usage_log_user_idx on public.ai_usage_log (user_id) where user_id is not null;
