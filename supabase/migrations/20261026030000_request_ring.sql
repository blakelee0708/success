-- The gate in front of 소리 울리기.
--
-- It is SQL rather than TypeScript on purpose. The Edge Function that talks to
-- FCM is a sender and nothing else; every question about *whether this ring is
-- allowed* is the same kind of question the rest of this schema already
-- answers, and splitting them would mean the subscription gate lived in two
-- languages with one of them unverifiable from here.
--
-- Three things have to be true, and the third is the one that is easy to
-- forget: paying does not turn 안심 케어 on. `care_is_active` is a
-- subscription *and* the senior's consent, and a paid subscription with no
-- consent has to behave exactly like no subscription.
create or replace function public.request_phone_ring(
  p_senior_profile_id uuid,
  p_message text default null
)
returns table (push_token text, from_name text, line text)
language plpgsql
security definer
set search_path to 'public', 'auth'
as $$
declare
  caller uuid := auth.uid();
  guardian record;
begin
  if caller is null then
    raise exception '로그인이 필요해요.' using errcode = '42501';
  end if;

  select ga.id, ga.display_name
    into guardian
    from public.guardian_accounts ga
    join public.guardian_senior_links l
      on l.guardian_account_id = ga.id
   where ga.auth_user_id = caller
     and l.senior_profile_id = p_senior_profile_id
     -- A removed guardian keeps their row. Without this they could go on
     -- making a phone they no longer look after shout at the person holding
     -- it, which is the single worst thing this feature could be used for.
     and l.status = 'active'
   limit 1;

  if guardian.id is null then
    raise exception '이 부모님의 보호자가 아니에요.' using errcode = '42501';
  end if;

  if not public.care_is_active(p_senior_profile_id) then
    raise exception '안심 케어가 켜져 있어야 보낼 수 있어요.' using errcode = '42501';
  end if;

  return query
    select d.push_token,
           -- The senior reads this. A guardian who never set a name is
           -- `가족` rather than a blank, because the screen's whole job is to
           -- say who is asking before the phone starts making a noise.
           coalesce(nullif(btrim(guardian.display_name), ''), '가족'),
           coalesce(nullif(btrim(p_message), ''), '전화 한 번만 주세요.')
      from public.senior_devices d
     where d.senior_profile_id = p_senior_profile_id
       and d.is_active
       -- A phone that has never checked in has no token, and a row with a
       -- null token would have the sender POST `to: null` to FCM and read the
       -- rejection as a delivery failure. There is nothing to ring; say so by
       -- returning nothing.
       and d.push_token is not null
     limit 1;
end;
$$;

-- Callable by a signed-in guardian: the function reads `auth.uid()`, so a
-- service-role call would have no caller to check and would answer for
-- nobody. The Edge Function therefore forwards the user's own JWT rather than
-- using the service key for this step, and holds the service key only for the
-- part that actually needs it — talking to Google.
revoke all on function public.request_phone_ring(uuid, text) from public;
grant execute on function public.request_phone_ring(uuid, text) to authenticated;
