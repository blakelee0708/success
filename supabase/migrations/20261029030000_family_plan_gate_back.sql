-- The family-plan gate, put back, and widened to count a parent who has not
-- answered yet.
--
-- **`20261029010000_link_consent.sql` dropped it.** That migration rewrote
-- `create_senior_profile` and `claim_senior_pairing_code` to write a
-- 'pending' link, and in rewriting them left out the one line each that
-- stood above the insert: `perform public.assert_can_add_senior()`. A
-- `create or replace` replaces the whole body, so the 두 번째 부모님 gate -
-- the only thing the 가족 플랜 sells - was gone from both paths while the
-- SQL that defines it sat there untouched and passing its own checks.
--
-- `tool/verify_supabase_phase6.py` is what caught it, and only because it
-- asks the question from the outside: it adds a second parent with no plan
-- and expects a refusal. Nothing that reads the migrations could have seen
-- it, because nothing is missing from them - the loss is in what the later
-- file does not say.
--
-- **The count now includes 'pending', which is the part that is not just a
-- restoration.** Gating on active links alone would have left the gate open
-- to anybody who never gets consent: ask three parents, none of them
-- answers, add a fourth for nothing. A link the guardian asked for is a
-- parent they have taken on, whatever the answer turns out to be.

create or replace function public.assert_can_add_senior()
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
  -- however that link came about. 'pending' counts - see above.
  select count(*) into existing
  from public.guardian_senior_links
  where guardian_account_id = public.current_guardian_account_id()
    and status in ('active', 'pending');

  if existing >= 1 and not public.has_family_plan() then
    raise exception 'family plan required';
  end if;
end;
$$;

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

  perform public.assert_can_add_senior();

  insert into public.senior_profiles (display_name, age_band, customer_code)
  values (p_display_name, p_age_band, public.generate_customer_code())
  returning * into result;

  -- 'pending': the senior's phone does not exist yet, and the card is drawn
  -- the moment it connects.
  insert into public.guardian_senior_links
    (guardian_account_id, senior_profile_id, role, status)
  values (guardian_id, result.id, 'primary', 'pending');

  return result;
end;
$$;

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

  perform public.assert_can_add_senior();

  link := public.claim_pair_link(p_code, 'senior_shares_code');

  update public.senior_profiles
    set display_name = coalesce(nullif(trim(p_display_name), ''), display_name)
  where id = link.senior_profile_id
  returning * into profile;

  -- **Pending, not active.** Showing a code says *here is my number*, not
  -- *you may see how I am*.
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

revoke execute on function public.assert_can_add_senior() from anon, authenticated;
grant execute on function public.create_senior_profile(text, text) to authenticated;
grant execute on function public.claim_senior_pairing_code(text, text, text)
  to authenticated;
