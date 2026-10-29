-- 끊기, 그 양쪽, 그리고 계정 삭제.
--
-- Four things were missing and all four are the same shape: somebody wants
-- out and the app has no way to say so. `guardian_senior_links.status` has
-- carried `'removed'` since Phase 4 and **nothing ever wrote it.**
--
-- One rule runs through all of it: **끊는 것은 언제나 즉시 되고, 묻지 않고,
-- 되돌릴 수 있다.** Neither side needs the other's permission - a leaving
-- that needs the other party's consent is not a leaving - and neither side
-- loses anything that cannot be had back. A senior's buttons, colours and
-- text size are untouched, because leaving is stopping somebody from
-- looking, not putting a phone back how it was.
--
-- And one more: **the senior is never the one charged.** If the senior cuts
-- the link and the child can no longer use what they paid for, the money
-- goes back.

-- ---------------------------------------------------------------------------
-- 자녀에게 전할 말이 있을 곳
-- ---------------------------------------------------------------------------

-- **`alerts` cannot carry this and that is why this table exists.** Alerts
-- hang off the profile and `alerts_read` is `guardian_manages`, which is
-- false the instant a link goes to `'removed'` - so an alert saying
-- 연결이 끊어졌어요 would be readable by every guardian **except** the one it
-- is about. Probed rather than assumed.
--
-- It also could not name the parent. A removed guardian cannot read
-- `senior_profiles` either, so the name is copied in here at write time.
-- That is a snapshot on purpose: it is their own mother's name, and the
-- sentence is useless without it when a family has two parents.
create table if not exists public.guardian_notices (
  id uuid primary key default gen_random_uuid(),
  guardian_account_id uuid not null
    references public.guardian_accounts (id) on delete cascade,
  type text not null check (type in ('link_removed')),
  -- The parent's name as it was. Null only if the profile had none.
  senior_name text,
  body text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists guardian_notices_guardian_idx
  on public.guardian_notices (guardian_account_id, created_at desc);

alter table public.guardian_notices enable row level security;

-- Only the person it is addressed to. Not the family: whether a sibling was
-- removed is between that sibling and their parent.
drop policy if exists guardian_notices_own on public.guardian_notices;
create policy guardian_notices_own on public.guardian_notices
  for select to authenticated
  using (guardian_account_id = public.current_guardian_account_id());

drop policy if exists guardian_notices_mark_read on public.guardian_notices;
create policy guardian_notices_mark_read on public.guardian_notices
  for update to authenticated
  using (guardian_account_id = public.current_guardian_account_id())
  with check (guardian_account_id = public.current_guardian_account_id());

-- ---------------------------------------------------------------------------
-- 끊긴 뒤에는 유료 기능도 멈춘다
-- ---------------------------------------------------------------------------

-- **`care_is_active` did not look at the link at all**, which is the defect
-- this file fixes before it adds anything. A guardian whose link was removed
-- would have gone on being told their parent's battery, because the gate
-- asked only about the subscription and the consent. RLS would have refused
-- the rows, so what shipped would have been two layers disagreeing - and the
-- one that decides what a family is *charged for* was the permissive one.
create or replace function public.care_is_active(p_senior_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from public.subscriptions s
    join public.senior_profiles p on p.id = s.senior_profile_id
    where s.senior_profile_id = p_senior_profile_id
      and s.plan = 'care'
      and p.paid_consent_status = 'granted'
      and (
        s.status = 'active'
        or (s.status = 'canceled' and s.current_period_end > now())
      )
      -- Somebody has to still be looking after this parent. Checked on the
      -- subscription's own buyer rather than on any guardian: a sibling who
      -- stayed is not who the money came from, and their link does not keep
      -- a cancelled card alive.
      and exists (
        select 1
        from public.guardian_senior_links l
        where l.senior_profile_id = s.senior_profile_id
          and l.guardian_account_id = s.guardian_account_id
          and l.status = 'active'
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- 마지막 링크가 사라질 때
-- ---------------------------------------------------------------------------

-- Shared by both directions, because the question is the same from either
-- side: with this link gone, is anyone left?
--
-- `p_refund` is what differs. 어르신이 끊으면 자녀는 남은 기간을 쓸 수
-- 없으므로 돌려준다. 자녀가 스스로 떠나면 자기 선택이고, 그래도 쓸 수
-- 없게 되는 것은 같아서 역시 돌려준다 - 환불이 없는 쪽은 `해지하기`뿐이고,
-- 그쪽은 남은 기간을 그대로 쓴다.
create or replace function public.settle_care_after_leaving(
  p_senior_profile_id uuid,
  p_guardian_account_id uuid,
  p_refund boolean
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  -- Only this guardian's own subscription. A sibling's card is theirs.
  update public.subscriptions
     set status = case when p_refund then 'refunded' else 'canceled' end,
         canceled_at = coalesce(canceled_at, now()),
         refunded_at = case when p_refund then now() else refunded_at end,
         updated_at = now()
   where senior_profile_id = p_senior_profile_id
     and guardian_account_id = p_guardian_account_id
     and plan = 'care'
     and status in ('active', 'pending_senior_consent', 'canceled');

  -- An unanswered consent question is withdrawn rather than left standing on
  -- the parent's home screen, pointing at a family that is no longer there.
  if not exists (
    select 1 from public.subscriptions
     where senior_profile_id = p_senior_profile_id
       and plan = 'care'
       and status in ('active', 'pending_senior_consent')
  ) and exists (
    select 1 from public.senior_profiles
     where id = p_senior_profile_id
       and paid_consent_status = 'pending'
  ) then
    update public.senior_profiles
       set paid_consent_status = 'none'
     where id = p_senior_profile_id;
  end if;
end;
$$;
revoke execute on function
  public.settle_care_after_leaving(uuid, uuid, boolean) from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 어르신이 끊는다
-- ---------------------------------------------------------------------------

-- Called by the parent's own phone, from 설정 → 가족 연결 설정.
--
-- **One guardian at a time, by name.** A single 가족 연결을 끊기 that took
-- everybody off was considered and refused: the person a mother is cross
-- with is usually one of them, and a button that cannot tell her children
-- apart makes her choose between all of them and none.
create or replace function public.remove_guardian_link(
  p_guardian_account_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  profile_id uuid;
  senior_label text;
  still_there int;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  -- **Only the phone the link is about may cut it.** Scoped through the
  -- active device rather than through the profile, which is the same check
  -- `answer_guardian_link` makes: a guardian who could remove a sibling
  -- would be deciding for their parent, and this is the one decision that is
  -- hers.
  select d.senior_profile_id into profile_id
    from public.senior_devices d
   where d.auth_user_id = auth.uid()
     and d.is_active;

  if profile_id is null then
    raise exception 'this phone is not an active senior device';
  end if;

  update public.guardian_senior_links
     set status = 'removed', updated_at = now()
   where senior_profile_id = profile_id
     and guardian_account_id = p_guardian_account_id
     and status in ('active', 'pending');

  if not found then
    -- Not an error. Pressing 끊기 twice, or on a row a sibling's handover
    -- already changed, is somebody getting what they asked for.
    return;
  end if;

  select display_name into senior_label
    from public.senior_profiles where id = profile_id;

  -- **One line, and no reason.** Why a mother cut the link is her business,
  -- and an app guessing at it in writing would be worse than silence. But
  -- silence alone leaves the child one day finding nothing on their screen
  -- and no idea why, so something has to be said.
  insert into public.guardian_notices
    (guardian_account_id, type, senior_name, body)
  values (
    p_guardian_account_id, 'link_removed', senior_label,
    '연결이 끊어졌습니다.'
  );

  -- **Only when the last one goes.** Two children and one removed: the one
  -- who was kept did nothing wrong, and taking away what they paid for
  -- would be the app punishing the wrong person.
  select count(*) into still_there
    from public.guardian_senior_links
   where senior_profile_id = profile_id
     and status = 'active';

  if still_there = 0 then
    perform public.settle_care_after_leaving(
      profile_id, p_guardian_account_id, true
    );
  end if;
end;
$$;
grant execute on function public.remove_guardian_link(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 자녀가 끊는다
-- ---------------------------------------------------------------------------

-- Called by the guardian, from 연결 관리 → 부모님 연결 끊기. Their own link
-- and nothing else: a guardian may leave, and may not remove a sibling.
create or replace function public.leave_senior(p_senior_profile_id uuid)
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

  update public.guardian_senior_links
     set status = 'removed', updated_at = now()
   where senior_profile_id = p_senior_profile_id
     and guardian_account_id = guardian_id
     and status in ('active', 'pending');

  if not found then
    return;
  end if;

  -- They can no longer use what they bought, so the money goes back - which
  -- is what separates 연결 끊기 from 해지하기. 해지 keeps the remaining days
  -- and refunds nothing.
  perform public.settle_care_after_leaving(
    p_senior_profile_id, guardian_id, true
  );

  -- **The parent is not told.** Nothing changes on their phone: the 가족
  -- button goes back to saying 가족 연결 and that is the whole of it. A
  -- notice would be the app explaining somebody's child to them.
end;
$$;
grant execute on function public.leave_senior(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 부모님이 폰을 바꾸셨을 때
-- ---------------------------------------------------------------------------

-- **The senior does what they always do**, which is press 번호 보여주기 on
-- the new phone. That makes a *new, empty* profile, because `install_id` is
-- different and `start_senior_pairing` has no way to know a handset was
-- replaced rather than added.
--
-- **The question is asked on the child's phone**, because the child is who
-- knows. They type the four digits as usual, their app sees they already
-- have this parent, and asks. 어머니 폰을 바꿨어요 lands here.
--
-- Why not the six-digit 고객센터 번호, which does survive a new phone:
-- **it never expires**, so it cannot be a key. A million values, and one
-- leak hands that family's phone over for good. The 4-digit code lives ten
-- minutes and the person answering is already an active guardian of that
-- parent. Both halves are needed.
create or replace function public.move_senior_to_new_phone(
  p_code text,
  p_senior_profile_id uuid
)
returns public.senior_profiles
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  link public.pair_links;
  empty_id uuid;
  profile public.senior_profiles;
  occupants int;
begin
  if not public.guardian_manages(p_senior_profile_id) then
    raise exception 'not allowed to manage this profile';
  end if;

  link := public.claim_pair_link(p_code, 'senior_shares_code');
  empty_id := link.senior_profile_id;

  if empty_id is null then
    raise exception 'this code does not belong to a phone';
  end if;

  if empty_id = p_senior_profile_id then
    -- The same phone showing its number again. Nothing to move, and saying
    -- so is better than silently reporting a move that did not happen.
    raise exception 'this phone is already the one connected';
  end if;

  -- **Only an empty profile may be absorbed.** Merging one that already has
  -- a guardian or a conversation is a different act entirely, and allowing
  -- it would let anyone holding a code swallow another family.
  select
    (select count(*) from public.guardian_senior_links
      where senior_profile_id = empty_id and status <> 'removed')
    + (select count(*) from public.messages
        where senior_profile_id = empty_id)
    into occupants;

  if occupants > 0 then
    raise exception 'that phone is already set up with a family';
  end if;

  -- The new handset takes the old profile, and the old handset steps down.
  -- `auth_user_id` rides along: it is the anonymous user that phone signs in
  -- as, and `touch_senior_device` is scoped to it.
  update public.senior_devices
     set is_active = false, updated_at = now()
   where senior_profile_id = p_senior_profile_id
     and is_active;

  update public.senior_devices
     set senior_profile_id = p_senior_profile_id,
         is_active = true,
         updated_at = now()
   where senior_profile_id = empty_id;

  -- What is left of the empty profile is deleted, which takes its default
  -- home-app rows with it. The real arrangement is on the profile that was
  -- kept, and the phone pulls it on its next resume.
  delete from public.senior_profiles where id = empty_id;

  select * into profile from public.senior_profiles
   where id = p_senior_profile_id;
  return profile;
end;
$$;
grant execute on function public.move_senior_to_new_phone(text, uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 계정 삭제, which Play requires
-- ---------------------------------------------------------------------------

-- Play's user-data policy requires that an account made in the app can be
-- deleted **in the app and from a web page**, and says in as many words that
-- deactivating or suspending does not count. There was nothing: `lib/` held
-- no 탈퇴 and no `deleteAccount`, only 로그아웃.
--
-- **It does not reach the senior.** They never make an account - their phone
-- signs in anonymously - so the requirement is the guardian's alone.
--
-- Three decisions about what survives, and the shape of all three is the
-- same: deleting your own account may not take somebody else's things with
-- it.
create or replace function public.delete_guardian_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  guardian_id uuid;
  user_id uuid := auth.uid();
  orphan uuid;
  orphans uuid[];
begin
  guardian_id := public.current_guardian_account_id();
  if guardian_id is null then
    raise exception 'no guardian account for current user';
  end if;

  -- Money first, while the links can still be counted. They are losing
  -- access, so whatever is left of a paid month goes back.
  for orphan in
    select l.senior_profile_id
      from public.guardian_senior_links l
     where l.guardian_account_id = guardian_id
       and l.status = 'active'
  loop
    perform public.settle_care_after_leaving(orphan, guardian_id, true);
  end loop;

  -- **어르신의 프로필과 폰 설정은 남는다.** The parent is still holding that
  -- phone, and a child deleting their own account must not collapse their
  -- mother's home screen. The one exception is a profile nobody ever used:
  -- noted now, because after the delete there is no link left to find it by.
  select coalesce(array_agg(distinct l.senior_profile_id), '{}')
    into orphans
    from public.guardian_senior_links l
   where l.guardian_account_id = guardian_id
     and not exists (
       select 1 from public.guardian_senior_links other
        where other.senior_profile_id = l.senior_profile_id
          and other.guardian_account_id <> guardian_id
          and other.status <> 'removed'
     )
     and not exists (
       select 1 from public.senior_devices d
        where d.senior_profile_id = l.senior_profile_id
     );

  -- **대화는 지우지 않고 보낸 사람만 지운다.** Those messages are also
  -- something the parent received; a child deleting their account must not
  -- erase what they said from their mother's phone. The FK is already
  -- `on delete set null`, so the cascade does this - see the constraint
  -- below, which had to be loosened for it to be possible at all.
  --
  -- Deleting the auth user is what makes this a deletion rather than a
  -- deactivation. `guardian_accounts.auth_user_id` is
  -- `references auth.users on delete cascade`, so the account row, its
  -- links, its subscriptions, its pair links and its notices all go with it.
  delete from auth.users where id = user_id;

  -- A profile no guardian and no phone was ever attached to is a profile
  -- somebody half-made and abandoned. Left behind it is a row nobody can
  -- reach or delete.
  delete from public.senior_profiles where id = any(orphans);
end;
$$;
grant execute on function public.delete_guardian_account() to authenticated;

-- **`one_sender` was an exclusive-or and it made the cascade impossible.**
-- `messages.sender_guardian_id` is `on delete set null`, and nulling it on a
-- row whose `sender_device_id` is also null violated
-- `(a is null) <> (b is null)` - a check is re-tested on update, and
-- `on delete set null` is an update. So deleting a guardian who had ever
-- sent a message would have failed with a constraint violation, on the one
-- path Play requires to work. Found by reading rather than by trying it.
--
-- It is now *never both*, and *exactly one* is enforced where the rows are
-- actually written: `send_family_message` is the only writer, and `messages`
-- has no insert policy at all. A row with neither is a message whose sender
-- deleted their account, which is a real thing rather than a corruption -
-- `FamilyMessage.isFromSenior` reads `sender_device_id`, so it stays on the
-- side of the conversation it was always on, with no name over it.
alter table public.messages drop constraint if exists one_sender;
alter table public.messages add constraint one_sender check (
  sender_guardian_id is null or sender_device_id is null
);
