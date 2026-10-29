-- 1대1만 연결한다, for now.
--
-- The owner's call on 2026-10-29: 복잡할 거 같아. The app could already put
-- several children on one parent and several parents on one child, and
-- almost everything awkward in it came from one of those two - 두 자녀 중
-- 하나만 끊으면 안심 케어는 어떻게 되나, 메시지에 누가 보냈는지, 대표
-- 보호자는 누가 정하나, 부모님이 두 분이면 어느 쪽 폰을 바꾸신 건가.
--
-- **This is a lock, not a rewrite.** `guardian_senior_links` is a join
-- table and stays one: nothing is dropped, no row moves, and the invite and
-- handover functions are left exactly where they are. What changes is two
-- numbers, and opening it again later means changing them back. There is no
-- migration to write on the way out, which is the whole reason it was done
-- this way.
--
-- Nothing is published yet, so no family has two of either. This is the
-- cheapest moment there will ever be to do it.

-- The two numbers, as functions rather than literals - the same shape
-- `family_text_free()` and `guardian_home_edits_free()` already use, and for
-- the same reason: a limit written into each caller is a limit that gets
-- changed in one place and missed in the other.
create or replace function public.max_guardians_per_senior()
returns int language sql immutable as $$ select 1 $$;

create or replace function public.max_seniors_per_guardian()
returns int language sql immutable as $$ select 1 $$;

-- ---------------------------------------------------------------------------
-- 부모님 한 분에 자녀 한 명
-- ---------------------------------------------------------------------------

-- **There was no gate here at all.** A sibling joined by redeeming an
-- invite and nothing counted. Hiding 가족 초대하기 would have been enough in
-- practice - no screen creates a code any more - but a rule the server does
-- not hold is a rule two layers can disagree about, which is the defect
-- `care_is_active` was fixed for one file earlier.
create or replace function public.assert_can_add_guardian(p_senior_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  existing int;
begin
  -- 'removed' is not counted, which is what lets a family reconnect after a
  -- 끊기: the row is still there and still says removed, and the seat it
  -- used to hold is free.
  select count(*) into existing
  from public.guardian_senior_links
  where senior_profile_id = p_senior_profile_id
    and status in ('active', 'pending')
    -- The same guardian re-entering a code is not a second guardian. It
    -- happens on a reconnect, and on an install SMS followed by a code.
    and guardian_account_id is distinct from public.current_guardian_account_id();

  if existing >= public.max_guardians_per_senior() then
    raise exception 'one guardian per senior';
  end if;
end;
$$;
revoke execute on function public.assert_can_add_guardian(uuid)
  from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 자녀 한 명에 부모님 한 분
-- ---------------------------------------------------------------------------

-- **가족 플랜 is not deleted, it is unreachable.** The plan rows, the
-- subscription kind and `has_family_plan()` all stay; what goes is the
-- carve-out that let it raise the limit, and the card that sold it. Putting
-- the plan back means putting `and not public.has_family_plan()` back on the
-- line below - which is why the condition is left written out here rather
-- than tidied away.
--
-- It costs nothing today either way: there is no Play Billing, so the plan
-- could not be sold.
-- **`p_except_profile` is the whole of the reconnect case**, and leaving it
-- out was a real bug the verifier caught before anything shipped. A guardian
-- re-entering a code for the parent they **already have** is not taking on a
-- second parent - it happens on a reconnect, and after an install SMS when
-- the parent reads their number out anyway. Counted without the exception,
-- they were told 지금은 부모님 한 분만 연결할 수 있어요 about their own
-- mother, which is the dead end this file exists to avoid rather than
-- create.
--
-- The zero-argument version is dropped rather than left beside this one:
-- two candidates where one has a default is ambiguous, and
-- `create_senior_profile`'s existing `assert_can_add_senior()` resolves to
-- this one with a null.
drop function if exists public.assert_can_add_senior();

create or replace function public.assert_can_add_senior(
  p_except_profile uuid default null
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  existing int;
begin
  -- Counted over the guardian's own links rather than over profiles they
  -- created: a sibling invited to help with one parent has one parent,
  -- however that link came about. 'pending' counts, because a gate that
  -- waits for consent is a gate anyone can walk past by never asking for it.
  select count(*) into existing
  from public.guardian_senior_links
  where guardian_account_id = public.current_guardian_account_id()
    and status in ('active', 'pending')
    and senior_profile_id is distinct from p_except_profile;

  -- 가족 플랜 raised this to unlimited and does not any more:
  --   if existing >= 1 and not public.has_family_plan() then
  if existing >= public.max_seniors_per_guardian() then
    raise exception 'one senior per guardian';
  end if;
end;
$$;
revoke execute on function public.assert_can_add_senior(uuid)
  from anon, authenticated;

-- ---------------------------------------------------------------------------
-- The two paths that attach a guardian to a profile that already exists
-- ---------------------------------------------------------------------------

-- `create_senior_profile` is not one of them: it makes the profile, so there
-- is nobody on it yet and `assert_can_add_senior` is the whole gate there.
--
-- `redeem_recovery_code` and `redeem_senior_invite` are not either - those
-- attach a **device**, not a guardian.
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

  -- **Both checks sit after the code resolves**, because neither question
  -- can be answered before it. 이 번호가 누구 것인지 알아야 *두 번째* 부모님인지
  -- 알 수 있다 - and a guardian re-entering a number for the parent they
  -- already have must not be refused. The code is spent either way, and a
  -- spent code costs ten minutes and one tap.
  perform public.assert_can_add_senior(link.senior_profile_id);
  perform public.assert_can_add_guardian(link.senior_profile_id);

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
grant execute on function public.claim_senior_pairing_code(text, text, text)
  to authenticated;

-- 가족 초대하기 is off every screen, so nothing can create one of these
-- codes any more. The gate goes on anyway: an invite made before today is
-- still redeemable for seven days, and a rule that holds only because no
-- button calls it is a rule waiting to be broken by the next button.
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

  perform public.assert_can_add_senior(link.senior_profile_id);
  perform public.assert_can_add_guardian(link.senior_profile_id);

  select * into profile from public.senior_profiles
   where id = link.senior_profile_id;
  if profile.id is null then
    raise exception 'no such profile';
  end if;

  -- Never 'primary': joining by invitation does not take over the account.
  insert into public.guardian_senior_links
    (guardian_account_id, senior_profile_id, role, status)
  values (guardian_id, profile.id, 'family', 'pending')
  on conflict (guardian_account_id, senior_profile_id) do update
    set status = case
      when public.guardian_senior_links.status = 'active' then 'active'
      else 'pending'
    end;

  return profile;
end;
$$;
grant execute on function public.redeem_family_invite(text) to authenticated;
