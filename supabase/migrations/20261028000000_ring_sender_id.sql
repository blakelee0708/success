-- Who asked, as an id rather than only a name.
--
-- The parent's phone now offers to **call the child back** while it is
-- ringing, which is the whole resolution of 엄마가 전화를 안 받아: a senior who
-- picks up a loud phone and can only silence it has been told something and
-- given nothing to do about it.
--
-- That needs the sender's number, and the roster already has it. What was
-- missing was a way to say *which* guardian, because the payload carried
-- `from_name` and nothing else. Matching on the name was the alternative and
-- it is wrong in the case that matters: two children, one of them called
-- 아들 by both of them, and the phone rings the other one.
--
-- When the id cannot be resolved to a number the phone shows **no call
-- button** rather than falling back to the primary guardian. Ringing the
-- wrong child is worse than offering nothing.
--
-- `create or replace` cannot change a function's return type, so this drops
-- and recreates - which also drops the grants, re-applied at the bottom.
drop function if exists public.request_phone_ring(uuid, text);

create function public.request_phone_ring(
  p_senior_profile_id uuid,
  p_message text default null
)
returns table (
  push_token text,
  from_id uuid,
  from_name text,
  line text
)
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
           guardian.id,
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

-- Re-applied because the drop above took the old function's grants with it.
revoke all on function public.request_phone_ring(uuid, text) from public;
grant execute on function public.request_phone_ring(uuid, text) to authenticated;
