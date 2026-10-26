-- 읽음 확인 — whether the parent has seen what their child wrote.
--
-- This is what is left of the reassurance 위치 확인 was going to sell, and it
-- is the better half of it: `어머니가 2시에 내 메시지를 읽으셨다` is decent
-- evidence that a parent is all right, and unlike a location it is something
-- **they did**, not something taken from them. Nothing is collected and
-- nothing is tracked; a message they opened says so.
--
-- One direction only. The parent is never shown whether their child has read
-- *them*: a senior watching an unread mark on a message to a busy adult is
-- the unkindest thing this app could put on a screen, and it is not a thing
-- they asked for.

alter table public.messages
  add column if not exists read_at timestamptz;

-- Marks everything the *other* side sent as read, up to now.
--
-- Takes no message ids: the caller marks the conversation, not a message, so
-- there is no way to claim a read on something that was never shown. The
-- sender's own rows are excluded by the `is null` tests rather than by trust.
create or replace function public.mark_conversation_read(
  p_senior_profile_id uuid
)
returns int
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  marked int := 0;
  is_device boolean;
begin
  if not (
    public.guardian_manages(p_senior_profile_id)
    or public.device_owns(p_senior_profile_id)
  ) then
    raise exception 'not allowed to read this conversation';
  end if;

  is_device := public.device_owns(p_senior_profile_id);

  update public.messages m
     set read_at = now()
   where m.senior_profile_id = p_senior_profile_id
     and m.read_at is null
     -- The parent marks what guardians sent; a guardian marks what the
     -- parent sent. Neither can mark their own.
     and case
           when is_device then m.sender_guardian_id is not null
           else m.sender_device_id is not null
         end;

  get diagnostics marked = row_count;
  return marked;
end;
$$;

revoke all on function public.mark_conversation_read(uuid) from public, anon;
grant execute on function public.mark_conversation_read(uuid) to authenticated;
