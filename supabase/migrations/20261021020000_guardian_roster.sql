-- Who is looking after this parent, readable by the people it is about.
--
-- `guardian_accounts` has exactly one policy, `guardian_accounts_own`, and it
-- is `auth_user_id = auth.uid()`. That is right for the table and wrong for
-- everything built on top of it, because the embedded read in `guardiansFor`
-- inherits it. Probed against the live project, a family of one parent and
-- two guardians comes back like this:
--
--   senior's phone  : primary -> null, family -> null
--   guardian g1     : primary -> {g1}, family -> null
--   guardian g2     : primary -> null, family -> {g2}
--
-- Everyone can see their own row and nothing else. Two screens were built on
-- that and neither works:
--
--  * 긴급 연락's 보호자 button. `04_SCREEN_SPEC` asks for 119, 112 and 보호자.
--    The number is collected when the guardian connects and stored right
--    here — and the one phone that needs it in an emergency is the one phone
--    with no policy to read it. The button has been `onTap: null` since the
--    screen existed, under a caption promising it would work once a family
--    was connected.
--  * 연결된 가족 on the guardian's 가족 tab, which lists a sibling as the
--    literal word 보호자 because their name reads as null.
--
-- A function rather than a widened policy: the table's own rule stays as
-- strict as it is, and this returns exactly the roster — no auth ids, no
-- tokens, and an email only to the account it belongs to.

create or replace function public.guardians_for_senior(
  p_senior_profile_id uuid
)
returns table (
  guardian_account_id uuid,
  role text,
  status text,
  display_name text,
  phone_number text,
  email text
)
language sql
stable
security definer
set search_path = public, auth
as $$
  select
    l.guardian_account_id,
    l.role,
    l.status,
    a.display_name,
    -- Shared with the family this roster is about. They can already rearrange
    -- the parent's home screen and read every message; a number they gave
    -- each other is less than that, and without it the SOS button cannot
    -- exist at all.
    a.phone_number,
    -- Not shared. It is an account identifier rather than a way to reach
    -- anyone, and the roster has a name for that.
    case when a.auth_user_id = auth.uid() then a.email end
  from public.guardian_senior_links l
  join public.guardian_accounts a on a.id = l.guardian_account_id
  where l.senior_profile_id = p_senior_profile_id
    and l.status <> 'removed'
    -- The caller has to be one of the two kinds of person this concerns: a
    -- guardian who manages the parent, or the parent's own phone.
    and (
      public.guardian_manages(p_senior_profile_id)
      or public.device_owns(p_senior_profile_id)
    )
  -- 대표 보호자 first. The senior's SOS button takes the first number it is
  -- given, and the person who should answer is the one the family named.
  order by (l.role = 'primary') desc, l.created_at;
$$;

revoke all on function public.guardians_for_senior(uuid) from public;
revoke all on function public.guardians_for_senior(uuid) from anon;
grant execute on function public.guardians_for_senior(uuid) to authenticated;
