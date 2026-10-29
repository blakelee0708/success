-- 가족 연결 동의 — the senior answers on their own phone, before anything is
-- shared.
--
-- **A guardian typed a number and was connected.** Nothing ever asked the
-- person whose phone it is. On 경로 B they had at least pressed 번호
-- 보여주기; on the install-SMS path they did nothing at all, and when a
-- sibling joined by invitation their mother was never told it had happened.
--
-- Play's rule for an app that looks at another adult's phone is that the
-- adult knows and agrees, on their own device. This is that, and it is the
-- most valuable thing in the app for 심사 after taking 위치 out.
--
-- `status` has carried 'pending' in its check constraint since Phase 4 and
-- nothing ever wrote it, so there is no constraint to widen.
--
-- **Only the three places a guardian attaches change.** Redeeming a recovery
-- code or an install invite attaches a *device*, not a guardian, and the link
-- it lands on was already answered - or is still pending, and the card is
-- waiting on the phone that just connected.

-- 1. A guardian creating a parent from their own dashboard. The senior's
--    phone does not exist yet; the card is drawn the moment it connects.
create or replace function public.create_senior_profile(
  p_display_name text,
  p_age_band text default null
)
returns public.senior_profiles
language plpgsql
security definer
set search_path to 'public', 'auth'
as $$
declare
  guardian_id uuid;
  result public.senior_profiles;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select id into guardian_id from public.guardian_accounts
   where auth_user_id = auth.uid();
  if guardian_id is null then
    raise exception 'no guardian account for current user';
  end if;

  insert into public.senior_profiles (display_name, age_band, customer_code)
  values (p_display_name, p_age_band, public.generate_customer_code())
  returning * into result;

  insert into public.guardian_senior_links
    (guardian_account_id, senior_profile_id, role, status)
  values (guardian_id, result.id, 'primary', 'pending');

  return result;
end;
$$;

-- 2. 경로 B — the number the parent read out.
create or replace function public.claim_senior_pairing_code(
  p_code text,
  p_display_name text,
  p_phone_number text default null
)
returns public.senior_profiles
language plpgsql
security definer
set search_path to 'public', 'auth'
as $$
declare
  guardian_id uuid;
  link public.pair_links;
  profile public.senior_profiles;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select id into guardian_id from public.guardian_accounts
   where auth_user_id = auth.uid();
  if guardian_id is null then
    raise exception 'no guardian account for current user';
  end if;

  link := public.claim_pair_link(p_code, 'senior_shares_code');

  update public.senior_profiles
    set display_name = coalesce(nullif(trim(p_display_name), ''), display_name)
  where id = link.senior_profile_id
  returning * into profile;

  -- **Pending, not active.** Showing a code says *here is my number*, not
  -- *you may see how I am*. The card on their own phone is where that is
  -- answered, and it is the first thing they see after reading the number
  -- out.
  insert into public.guardian_senior_links
    (guardian_account_id, senior_profile_id, role, status)
  values (guardian_id, profile.id, 'primary', 'pending')
  on conflict (guardian_account_id, senior_profile_id) do update
    -- A guardian already attached stays attached: re-entering a code must
    -- not put a working family back into waiting.
    set status = case
      when public.guardian_senior_links.status = 'active' then 'active'
      else 'pending'
    end;

  if p_phone_number is not null then
    update public.guardian_accounts
      set phone_number = coalesce(phone_number, p_phone_number)
    where id = guardian_id;
  end if;

  return profile;
end;
$$;

-- 3. A sibling joining. The gap this closes is the widest of the three: the
--    parent was never told at all.
create or replace function public.redeem_family_invite(p_code text)
returns public.senior_profiles
language plpgsql
security definer
set search_path to 'public', 'auth'
as $$
declare
  guardian_id uuid;
  link public.pair_links;
  profile public.senior_profiles;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select id into guardian_id from public.guardian_accounts
   where auth_user_id = auth.uid();
  if guardian_id is null then
    raise exception 'no guardian account for current user';
  end if;

  link := public.claim_pair_link(p_code, 'guardian_invite_family');

  -- 'family', never 'primary'. Joining by invitation does not take over the
  -- account; that is a separate request the senior has to approve.
  insert into public.guardian_senior_links
    (guardian_account_id, senior_profile_id, role, status)
  values (guardian_id, link.senior_profile_id, 'family', 'pending')
  on conflict (guardian_account_id, senior_profile_id) do update
    set status = case
      when public.guardian_senior_links.status = 'active' then 'active'
      else 'pending'
    end;

  select * into profile from public.senior_profiles
   where id = link.senior_profile_id;
  return profile;
end;
$$;

-- What the card on the senior's phone says, and which link it answers.
--
-- Security definer for the same reason `guardians_for_senior` is: the
-- account table's one policy is `auth_user_id = auth.uid()`, which is right
-- for the table and returns nothing to the phone this is about.
--
-- One at a time, oldest first. Two children connecting the same afternoon is
-- two cards, each naming one person - a card that said 두 명이 연결을
-- 부탁하셨어요 would be a single yes to two different people.
create or replace function public.pending_guardian_link()
returns table (link_id uuid, guardian_name text, role text)
language plpgsql
security definer
set search_path to 'public', 'auth'
as $$
declare
  profile_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select d.senior_profile_id into profile_id
    from public.senior_devices d
   where d.auth_user_id = auth.uid()
     and d.is_active
   limit 1;
  if profile_id is null then
    return;
  end if;

  return query
    select l.id, g.display_name, l.role
      from public.guardian_senior_links l
      join public.guardian_accounts g on g.id = l.guardian_account_id
     where l.senior_profile_id = profile_id
       and l.status = 'pending'
     order by l.created_at
     limit 1;
end;
$$;

-- 허락합니다 / 아니요.
--
-- **Only the phone the link is about may answer**, which is the check worth
-- reading twice: a guardian who could approve their own link would have
-- turned the card into a formality. The caller is the senior's device,
-- scoped by `auth.uid()` exactly as the check-in is.
--
-- A refusal **removes the row** rather than marking it. It is not final and
-- not a punishment: the guardian can ask again, and a pressed-by-mistake
-- 아니요 must not lock a family out. What it must not do is leave a row that
-- some later query reads as a connection.
create or replace function public.answer_guardian_link(
  p_link_id uuid,
  p_approve boolean
)
returns boolean
language plpgsql
security definer
set search_path to 'public', 'auth'
as $$
declare
  profile_id uuid;
  touched int;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select d.senior_profile_id into profile_id
    from public.senior_devices d
   where d.auth_user_id = auth.uid()
     and d.is_active
   limit 1;
  if profile_id is null then
    return false;
  end if;

  if p_approve then
    update public.guardian_senior_links
       set status = 'active', updated_at = now()
     where id = p_link_id
       and senior_profile_id = profile_id
       and status = 'pending';
    get diagnostics touched = row_count;
  else
    delete from public.guardian_senior_links
     where id = p_link_id
       and senior_profile_id = profile_id
       and status = 'pending';
    get diagnostics touched = row_count;
  end if;

  return touched > 0;
end;
$$;

-- The guardian's side of the wait.
--
-- `linked_senior_profiles` stays active-only on purpose: every screen behind
-- it - 홈 화면 정리, 메시지, 돌봄 - would otherwise be pointed at a parent
-- who has not agreed, and the RLS underneath would refuse each one
-- separately. This is a separate, smaller question: is anybody still
-- thinking about it?
create or replace function public.pending_guardian_links()
returns table (senior_profile_id uuid, senior_name text, asked_at timestamptz)
language plpgsql
security definer
set search_path to 'public', 'auth'
as $$
declare
  guardian_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select id into guardian_id from public.guardian_accounts
   where auth_user_id = auth.uid();
  if guardian_id is null then
    return;
  end if;

  return query
    select l.senior_profile_id, p.display_name, l.created_at
      from public.guardian_senior_links l
      join public.senior_profiles p on p.id = l.senior_profile_id
     where l.guardian_account_id = guardian_id
       and l.status = 'pending'
     order by l.created_at;
end;
$$;

grant execute on function public.pending_guardian_link() to authenticated;
grant execute on function public.answer_guardian_link(uuid, boolean)
  to authenticated;
grant execute on function public.pending_guardian_links() to authenticated;
