-- 무료 1주일은 부모님이 허락하신 날부터, 설치 번호는 7일.
--
-- 1. **The free week ran from the request, not from the 허락.** Since
--    `20261029010000_link_consent.sql` every link is written 'pending' when
--    the guardian asks, and `care_trial_ends_at` took `min(created_at)`. The
--    readings were already hidden until the parent agreed (`guardian_manages`
--    reads 'active' only), so nothing leaked - but the clock was running. On
--    the install-number path the parent may install days later, and found
--    the week half spent or gone before their child had seen anything.
--
--    `approved_at` is the moment a link first became 'active', written by a
--    trigger rather than by a line in `answer_guardian_link`: rewriting a
--    function whole to add one line is how a gate was once lost here, and a
--    trigger also covers any path that writes 'active' later. It is set once
--    and never moved, so a link cut and reconnected does not get a second
--    week.
--
-- 2. **The install number lives 7 days, down from 14.** The owner's call on
--    2026-10-30. The trial no longer depends on it, so this is about how long
--    a number sent by text stays spendable, and a week covers a weekend's
--    help with room to spare.

-- ---------------------------------------------------------------------------
-- 1. approved_at
-- ---------------------------------------------------------------------------

alter table public.guardian_senior_links
  add column if not exists approved_at timestamptz;

-- Rows from before link consent were active the moment they were written,
-- and a removed row was active before it was removed. Pending rows have not
-- been agreed to and stay null.
update public.guardian_senior_links
   set approved_at = created_at
 where approved_at is null
   and status in ('active', 'removed');

create or replace function public.stamp_link_approved_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status = 'active' and new.approved_at is null then
    new.approved_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists guardian_senior_links_approved_at
  on public.guardian_senior_links;
create trigger guardian_senior_links_approved_at
  before insert or update of status on public.guardian_senior_links
  for each row execute function public.stamp_link_approved_at();

-- Same signature and body as `20261028020000_pricing.sql`, reading
-- `approved_at` where it read `created_at`. A parent nobody has been allowed
-- to see yet has no trial running, so null - which `care_readings_visible`
-- already reads as not visible.
create or replace function public.care_trial_ends_at(p_senior_profile_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path = public, auth
as $$
  select min(approved_at) + interval '7 days'
    from public.guardian_senior_links
   where senior_profile_id = p_senior_profile_id;
$$;

-- ---------------------------------------------------------------------------
-- 2. 설치 번호 7일
-- ---------------------------------------------------------------------------

-- As in `20260730000000_phase5_pairing.sql` (compared against the live
-- definition before this was written), with the interval changed.
create or replace function public.create_senior_invite(p_display_name text)
returns public.pair_links
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  profile public.senior_profiles;
  link public.pair_links;
begin
  profile := public.create_senior_profile(p_display_name);

  -- A week: the parent has to receive a text, install an app and open it,
  -- possibly with help that arrives at the weekend.
  insert into public.pair_links
    (senior_profile_id, guardian_account_id, code, token, mode, expires_at)
  values (
    profile.id,
    public.current_guardian_account_id(),
    public.generate_pair_code(6),
    public.generate_pair_token(),
    'guardian_invites_senior',
    now() + interval '7 days'
  )
  returning * into link;

  return link;
end;
$$;
