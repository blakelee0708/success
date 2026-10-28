-- 자녀에게 가는 푸시 알림.
--
-- The exact opposite of the rule FCM follows for the senior, and for the same
-- reason. A status-bar entry is the one place a parent who cannot find their
-- own contacts app will not look, so their messages are drawn full screen by
-- the app. Their child is an adult with an ordinary phone on which this is
-- one app among many: a card could only ever appear once they had already
-- opened it, which is both late and redundant. What reaches them when it
-- matters is a notification, and until now that was the one thing in
-- `## The guardian gets a count, not a card` listed as not built.
--
-- **One direction only: the parent's message to their family.** A guardian's
-- own message already arrives on the parent's screen the moment they pick the
-- phone up, and notifying the other sibling about what you just typed is
-- noise.

alter table public.guardian_accounts
  add column if not exists push_token text;

comment on column public.guardian_accounts.push_token is
  'FCM registration token for this guardian''s phone. Rewritten on every '
  'dashboard open because a token rotates.';

-- ---------------------------------------------------------------------------
-- Registering
-- ---------------------------------------------------------------------------

-- Its own call rather than a column on something else, because the guardian's
-- half has no equivalent of the senior's check-in to ride on. It is cheap and
-- idempotent, so the dashboard simply makes it on every open — which is what
-- keeps it fresh, and a token **rotates**: a reinstall, a restore onto a new
-- handset, and occasionally for Firebase's own reasons.
create or replace function public.register_guardian_push_token(p_token text)
returns void
language plpgsql
security definer
set search_path to 'public', 'auth'
as $$
declare
  account uuid := public.current_guardian_account_id();
begin
  if account is null then
    raise exception '보호자 계정이 없어요.' using errcode = '42501';
  end if;
  -- Null never overwrites, the same rule the battery follows: a phone that
  -- could not fetch a token must not wipe the address the last one left.
  update public.guardian_accounts
     set push_token = coalesce(nullif(btrim(p_token), ''), push_token)
   where id = account;
end;
$$;

revoke all on function public.register_guardian_push_token(text) from public;
grant execute on function public.register_guardian_push_token(text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- The gate in front of the notification
-- ---------------------------------------------------------------------------

-- Same split as 소리 울리기: every question about *whether* this may be sent
-- is answered here, and the Edge Function in front of FCM only sends.
--
-- Called by the parent's own phone right after it sends a message. It names
-- the message rather than carrying its text, so nothing can push a line the
-- conversation does not contain.
create or replace function public.notify_family_message(p_message_id uuid)
returns table (push_token text, title text, body text)
language plpgsql
security definer
set search_path to 'public', 'auth'
as $$
declare
  msg public.messages;
  sender text;
begin
  select * into msg from public.messages where id = p_message_id;
  if msg.id is null then
    raise exception '메시지를 찾을 수 없어요.' using errcode = '42501';
  end if;

  -- The caller must be the phone the message was sent from. Not a guardian,
  -- not another device: a guardian who could call this would be able to make
  -- every sibling's phone buzz with a line they wrote themselves.
  if not public.device_owns(msg.senior_profile_id)
     or msg.sender_device_id is null then
    raise exception '부모님 폰에서 보낸 메시지가 아니에요.'
      using errcode = '42501';
  end if;

  select coalesce(nullif(btrim(p.display_name), ''), '부모님')
    into sender
    from public.senior_profiles p
   where p.id = msg.senior_profile_id;

  return query
    select g.push_token,
           sender,
           -- An image carries no text, and `사진을 보내셨어요` is what the
           -- app says everywhere else for one. The body is the message as
           -- sent; a notification that hides what was said would make the
           -- guardian open the app to learn nothing had happened.
           coalesce(nullif(btrim(msg.body), ''), '사진을 보내셨어요')
      from public.guardian_senior_links l
      join public.guardian_accounts g on g.id = l.guardian_account_id
     where l.senior_profile_id = msg.senior_profile_id
       and l.status = 'active'
       -- A guardian whose phone has never opened the dashboard has no
       -- address. There is nothing to send and nothing is wrong.
       and g.push_token is not null;
end;
$$;

revoke all on function public.notify_family_message(uuid) from public;
grant execute on function public.notify_family_message(uuid) to authenticated;
