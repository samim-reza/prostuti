-- ============================================================================
-- 0014 · Soft-deleted messages must not linger in the inbox preview.
-- When the latest message of a conversation is deleted (deleted_at set), the
-- conversation preview is replaced by a neutral marker.
-- ============================================================================

create or replace function public.messages_after_soft_delete()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  if new.deleted_at is not null and old.deleted_at is null then
    update public.conversations c
       set last_message_preview = '🚫'
     where c.id = new.conversation_id
       and not exists (select 1 from public.messages m
                        where m.conversation_id = new.conversation_id
                          and m.created_at > new.created_at);
  end if;
  return new;
end $$;

drop trigger if exists messages_after_soft_delete on public.messages;
create trigger messages_after_soft_delete after update of deleted_at on public.messages
  for each row execute function public.messages_after_soft_delete();
