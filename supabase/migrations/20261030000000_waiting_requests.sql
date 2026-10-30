-- 기다리는 연결 요청을 자녀가 거두고, 거절은 자녀에게 알린다.
--
-- Three faults on the guardian's waiting page, all of the same shape: a
-- request the parent had not answered was something the guardian could
-- neither see the state of nor take back.
--
-- 1. **No way to take a request back.** A wrong name, or a change of mind,
--    and the pending link sat there. Under 1대1 a pending link holds the
--    guardian's one seat (`assert_can_add_senior` counts it), so they could
--    not start again either. The only way out was 계정 삭제.
-- 2. **An install number that ran out stranded them for good.** It lives 14
--    days; after that the page lost its number and fell through to
--    부모님 폰에 여쭤보는 화면이 떠 있어요 - about a parent who never
--    installed the app, so had no screen to show anything on.
--    `pending_guardian_links` now says whether the parent's phone is there
--    at all, and 1 is the way out.
-- 3. **A 거절 was silent.** `answer_guardian_link` deleted the row and told
--    nobody, so the waiting page simply became 부모님 연결하기 - which reads
--    as the app failing, and the first thing a guardian does about that is
--    try again. It now leaves the same one-line notice a 끊기 does, with no
--    reason, for the same reason: why a mother said no is hers.

-- ---------------------------------------------------------------------------
-- 거절도 한 줄 남긴다
-- ---------------------------------------------------------------------------

alter table public.guardian_notices
  drop constraint if exists guardian_notices_type_check;
alter table public.guardian_notices
  add constraint guardian_notices_type_check
    check (type in ('link_removed', 'link_declined'));

-- As in `20261029010000_link_consent.sql`, plus the notice on 아니요. The
-- approve half is unchanged.
create or replace function public.answer_guardian_link(
  p_link_id uuid,
  p_approve boolean
)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  profile_id uuid;
  asked_by uuid;
  senior_label text;
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
       and status = 'pending'
    returning guardian_account_id into asked_by;
    get diagnostics touched = row_count;

    if asked_by is not null then
      select display_name into senior_label
        from public.senior_profiles where id = profile_id;
      insert into public.guardian_notices
        (guardian_account_id, type, senior_name, body)
      values (asked_by, 'link_declined', senior_label, '연결되지 않았어요.');
    end if;
  end if;

  return touched > 0;
end;
$$;
grant execute on function public.answer_guardian_link(uuid, boolean)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 부모님 폰이 있는지
-- ---------------------------------------------------------------------------

-- Dropped first: `create or replace` cannot change a function's return type.
drop function if exists public.pending_guardian_links();

create function public.pending_guardian_links()
returns table (
  senior_profile_id uuid,
  senior_name text,
  asked_at timestamptz,
  has_phone boolean
)
language plpgsql
security definer
set search_path = public, auth
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

  -- `has_phone` is whether any handset has attached to this parent. It says
  -- nothing about which phone or when - only whether there is a screen for
  -- the question to be on.
  return query
    select l.senior_profile_id, p.display_name, l.created_at,
           exists (
             select 1 from public.senior_devices d
              where d.senior_profile_id = l.senior_profile_id
                and d.is_active
           )
      from public.guardian_senior_links l
      join public.senior_profiles p on p.id = l.senior_profile_id
     where l.guardian_account_id = guardian_id
       and l.status = 'pending'
     order by l.created_at;
end;
$$;
revoke all on function public.pending_guardian_links() from public;
grant execute on function public.pending_guardian_links() to authenticated;

-- ---------------------------------------------------------------------------
-- 연결 요청 취소
-- ---------------------------------------------------------------------------

-- The caller's own pending request and nothing else; an active link is
-- `leave_senior`'s, which is a different act with money in it.
--
-- Three things go with the request:
--
-- - **the install numbers it issued**, so a parent who installs next week
--   cannot spend a number their child has taken back;
-- - **the parent's waiting card**, which is the pending row itself;
-- - **the profile, when it was only ever this request** - no phone, no
--   other link, no message. That is a guardian's 설치 문자 that nobody
--   installed, and left behind it is a row nobody can reach. A profile a
--   parent's own phone made (번호 보여주기) has a device and stays.
create or replace function public.withdraw_link_request(
  p_senior_profile_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  guardian_id uuid;
begin
  guardian_id := public.current_guardian_account_id();
  if guardian_id is null then
    raise exception 'no guardian account for current user';
  end if;

  delete from public.guardian_senior_links
   where senior_profile_id = p_senior_profile_id
     and guardian_account_id = guardian_id
     and status = 'pending';

  if not found then
    -- Pressed twice, or the parent answered first. Either way there is
    -- nothing left to take back, which is what was asked for.
    return;
  end if;

  update public.pair_links
     set expires_at = least(expires_at, now())
   where senior_profile_id = p_senior_profile_id
     and guardian_account_id = guardian_id
     and used_at is null;

  delete from public.senior_profiles p
   where p.id = p_senior_profile_id
     and not exists (
       select 1 from public.senior_devices d where d.senior_profile_id = p.id
     )
     and not exists (
       select 1 from public.guardian_senior_links l
        where l.senior_profile_id = p.id
     )
     and not exists (
       select 1 from public.messages m where m.senior_profile_id = p.id
     );
end;
$$;
revoke all on function public.withdraw_link_request(uuid) from public;
grant execute on function public.withdraw_link_request(uuid) to authenticated;
