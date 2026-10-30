-- 환불은 누가 끊었는지가 아니라 썼는지로 정한다.
--
-- The rule it replaces was *who wanted out*: a parent's 끊기 refunded the
-- remaining days, a child's 해지 kept them. The owner found the hole in one
-- sentence - 그럼 부모님께 끊으라고 하겠지 - and it cannot be closed from
-- either phone, because a mother pressing 끊기 at her son's request looks
-- exactly like a mother pressing it on her own.
--
-- What the server *can* see is whether the paid month was used:
--
-- | | 결제 후 7일 이내 | 7일 이후 |
-- |---|---|---|
-- | 쓰지 않음 | 전액 | 남은 기간 |
-- | 씀 | 없음, 기간 끝까지 | 없음, 기간 끝까지 |
--
-- and it is the same table for 해지, for either side's 끊기 and for 계정
-- 삭제. A consent the parent never gave is still always a full refund,
-- because nothing was ever switched on.
--
-- **What counts as 쓰다 is a day the guardian's phone was shown the paid
-- readings** - 안부 신호, 배터리, 소리. The dashboard opens on them, so that
-- is the same as a day the app was opened while 안심 케어 was on, which is
-- the owner's 접속도 안 하고 안 썼다. Messages and home edits are not counted
-- separately: nobody reaches either without passing through 홈 first.
--
-- **The day of the cancel itself does not count.** Opening the app to press
-- 해지 lands on 홈, which reads the readings, and somebody who came only to
-- cancel has not used anything. The cost of the exclusion is one day of
-- genuine use on that same day, which is worth less than the rule being
-- wrong for everyone who opens the app only to leave.
--
-- **A used month cut and reconnected inside its period asks the parent
-- again.** Reconnecting is the parent agreeing to the *link*; whatever made
-- them press 끊기 may well have been being looked at, so 안심 케어 is put
-- back to them as its own question. 허락 brings the remaining days back;
-- 거절 refunds nothing, because otherwise 끊었다가 다시 연결하고 거절해 줘
-- would be the same hole this file closes, one step longer. The first
-- refusal, on a month that never ran, is still always a full refund.
--
-- No money moves: there is no Play Billing. `refund_kind` is what the day it
-- arrives will hand to `subscriptionsv2.revoke` - `full` as a full refund,
-- `remaining` as a prorated one, which Google computes.

alter table public.subscriptions
  add column if not exists refund_kind text
    check (refund_kind in ('full', 'remaining'));

comment on column public.subscriptions.refund_kind is
  'How much a refunded row gives back: full, or remaining (prorated by '
  'Google). Null on a row that was not refunded.';

-- Every refund already written was a full one: a refusal, a withdrawn
-- question, or a leave under the old rule, which nobody has paid for.
update public.subscriptions
   set refund_kind = 'full'
 where status = 'refunded' and refund_kind is null;

-- One row per subscription per Seoul day. A day, not a timestamp: the
-- question asked of it is only ever 이 날 썼나.
create table if not exists public.care_use_days (
  subscription_id uuid not null
    references public.subscriptions (id) on delete cascade,
  used_on date not null,
  primary key (subscription_id, used_on)
);

-- Written and read only by the functions below. No client needs it, and a
-- guardian able to write it could make a used month look unused.
alter table public.care_use_days enable row level security;
revoke all on public.care_use_days from anon, authenticated;

create or replace function public.seoul_today()
returns date
language sql
stable
as $$
  select (now() at time zone 'Asia/Seoul')::date;
$$;

-- Called by `senior_readings` for the guardian's phone. Only while 안심
-- 케어 is actually on: the free first week shows the same readings, and a
-- day spent on the free week is not a day of the paid month.
create or replace function public.record_care_use(p_senior_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.care_is_active(p_senior_profile_id) then
    return;
  end if;

  insert into public.care_use_days (subscription_id, used_on)
  select s.id, public.seoul_today()
    from public.subscriptions s
   where s.senior_profile_id = p_senior_profile_id
     and s.guardian_account_id = public.current_guardian_account_id()
     and s.plan = 'care'
     and (
       s.status = 'active'
       or (s.status = 'canceled' and s.current_period_end > now())
     )
  on conflict do nothing;
end;
$$;
revoke execute on function public.record_care_use(uuid)
  from public, anon, authenticated;

-- 이 구독을 지금 끝내면 얼마를 돌려주나. Null is 돌려주지 않는다.
--
-- `started_at` is the payment. Play Billing's renewals will move it to each
-- new payment, which is what makes the seven days run again every month.
--
-- A 'canceled' row answers null: it was cancelled while used - an unused
-- one is refunded the moment it is cancelled and never becomes 'canceled' -
-- so a later 끊기 inside its remaining days has nothing more to give back.
create or replace function public.care_refund_due(p_subscription_id uuid)
returns text
language sql
stable
security definer
set search_path = public, auth
as $$
  select case
    when s.status = 'pending_senior_consent' then 'full'
    when s.status <> 'active' then null
    when exists (
      select 1 from public.care_use_days u
       where u.subscription_id = s.id
         and u.used_on >= (s.started_at at time zone 'Asia/Seoul')::date
         and u.used_on < public.seoul_today()
    ) then null
    when now() < s.started_at + interval '7 days' then 'full'
    else 'remaining'
  end
  from public.subscriptions s
  where s.id = p_subscription_id;
$$;
revoke execute on function public.care_refund_due(uuid)
  from public, anon, authenticated;

-- Ends one subscription by the table above, and returns what it became.
--
-- Refunded means off at once: the days are given back, so they are not
-- also kept. Not refunded means 'canceled' with `current_period_end`
-- standing, so the month runs to its end - and a family that reconnects
-- inside it gets it back, because `care_is_active` asks for a live link and
-- nothing else changed.
create or replace function public.care_settle(p_subscription_id uuid)
returns public.subscriptions
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  due text;
  result public.subscriptions;
begin
  due := public.care_refund_due(p_subscription_id);

  if due is null then
    update public.subscriptions
       set status = 'canceled',
           canceled_at = coalesce(canceled_at, now()),
           updated_at = now()
     where id = p_subscription_id
       and status = 'active'
    returning * into result;
  else
    update public.subscriptions
       set status = 'refunded',
           refund_kind = due,
           canceled_at = coalesce(canceled_at, now()),
           refunded_at = now(),
           updated_at = now()
     where id = p_subscription_id
       and status in ('active', 'pending_senior_consent')
    returning * into result;
  end if;

  if result.id is null then
    select * into result from public.subscriptions where id = p_subscription_id;
  end if;
  return result;
end;
$$;
revoke execute on function public.care_settle(uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 해지하기
-- ---------------------------------------------------------------------------

create or replace function public.cancel_care_subscription(
  p_senior_profile_id uuid
)
returns public.subscriptions
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  result public.subscriptions;
  sub_id uuid;
  was text;
begin
  if not public.guardian_manages(p_senior_profile_id) then
    raise exception 'not allowed to manage this profile';
  end if;

  select id, status into sub_id, was from public.subscriptions
   where senior_profile_id = p_senior_profile_id
     and plan = 'care'
     and status in ('active', 'pending_senior_consent');

  if sub_id is null then
    raise exception 'nothing to cancel';
  end if;

  result := public.care_settle(sub_id);

  -- An unanswered question is withdrawn rather than left on their screen.
  if was = 'pending_senior_consent' then
    update public.senior_profiles
      set paid_consent_status = 'none'
    where id = p_senior_profile_id;
  end if;

  return result;
end;
$$;
grant execute on function public.cancel_care_subscription(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 끊기와 계정 삭제
-- ---------------------------------------------------------------------------

-- **`p_refund` is no longer read.** Its three callers - the parent's 끊기,
-- the child's 끊기 and 계정 삭제 - all passed true, and that was the rule
-- being replaced. It stays in the signature because changing it means
-- rewriting all three, and rewriting a function whole is how the family-plan
-- gate was once deleted by accident (`20261029030000`).
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
declare
  sub_id uuid;
begin
  -- Only this guardian's own subscription.
  for sub_id in
    select id from public.subscriptions
     where senior_profile_id = p_senior_profile_id
       and guardian_account_id = p_guardian_account_id
       and plan = 'care'
       and status in ('active', 'pending_senior_consent')
  loop
    perform public.care_settle(sub_id);
  end loop;

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
-- 어르신이 거절하시면 전액
-- ---------------------------------------------------------------------------

-- As in `20261029040000_care_cancel.sql`, plus `refund_kind` and the second
-- question: a used month whose family reconnected inside it.
create or replace function public.resolve_care_consent(
  p_senior_profile_id uuid,
  p_approve boolean
)
returns public.senior_profiles
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  profile public.senior_profiles;
  asked_again boolean;
begin
  if not public.device_owns(p_senior_profile_id) then
    raise exception 'only the senior device can answer this';
  end if;

  if exists (
    select 1 from public.subscriptions
    where senior_profile_id = p_senior_profile_id
      and plan = 'care' and status = 'pending_senior_consent'
  ) then
    asked_again := false;
  elsif exists (
    select 1 from public.senior_profiles p
     where p.id = p_senior_profile_id
       and p.paid_consent_status = 'pending'
  ) and exists (
    select 1 from public.subscriptions
     where senior_profile_id = p_senior_profile_id
       and plan = 'care' and status = 'canceled'
       and current_period_end > now()
  ) then
    asked_again := true;
  else
    raise exception 'nothing to answer';
  end if;

  -- The month that already ran keeps its row either way. Only a first
  -- answer writes the subscription.
  if not asked_again then
    update public.subscriptions
      set status = case when p_approve then 'active' else 'refunded' end,
          refunded_at = case when p_approve then null else now() end,
          refund_kind = case when p_approve then null else 'full' end,
          current_period_end = case
            when p_approve then public.one_month_after(
              public.care_period_anchor(started_at, now()))
            else null
          end,
          updated_at = now()
    where senior_profile_id = p_senior_profile_id
      and plan = 'care' and status = 'pending_senior_consent';
  end if;

  update public.senior_profiles
    set paid_consent_status = case when p_approve then 'granted' else 'refused' end
  where id = p_senior_profile_id
  returning * into profile;

  insert into public.alerts (senior_profile_id, type, title, body)
  values (
    p_senior_profile_id,
    case when p_approve then 'care_consent_granted' else 'care_consent_refused' end,
    case
      when p_approve and asked_again
        then profile.display_name || '님이 안심 케어를 다시 허락하셨어요'
      when p_approve then profile.display_name || '님이 안심 케어를 허락하셨어요'
      else profile.display_name || '님이 안심 케어를 원하지 않으셨어요'
    end,
    case
      when p_approve and asked_again then '남은 기간 동안 다시 보실 수 있어요.'
      when p_approve then '이제 부모님이 어떻게 지내시는지 보실 수 있어요.'
      when asked_again
        then '이미 사용하신 기간이라 환불은 없습니다. 무료 기능은 그대로 쓰실 수 있어요.'
      else '결제는 환불 처리되었습니다. 무료 기능은 그대로 쓰실 수 있어요.'
    end
  );

  return profile;
end;
$$;

-- ---------------------------------------------------------------------------
-- 다시 연결되면 다시 묻는다
-- ---------------------------------------------------------------------------

-- A trigger rather than a line in `answer_guardian_link`, for the reason
-- `settle_care_after_leaving` keeps its unused parameter: rewriting a
-- function whole to add one line is how a gate was once lost.
--
-- Fires when a link becomes active and that guardian holds a cancelled
-- month with days left - which, since an unused month is refunded the
-- moment it ends, is always a used one. Nothing else qualifies: a first
-- connection has no subscription, and an active one cannot exist without
-- the link.
create or replace function public.ask_care_again_on_reconnect()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if new.status = 'active'
     and (tg_op = 'INSERT' or old.status is distinct from 'active')
     and exists (
       select 1 from public.subscriptions s
        where s.senior_profile_id = new.senior_profile_id
          and s.guardian_account_id = new.guardian_account_id
          and s.plan = 'care'
          and s.status = 'canceled'
          and s.current_period_end > now()
     ) then
    update public.senior_profiles
       set paid_consent_status = 'pending'
     where id = new.senior_profile_id;
  end if;
  return new;
end;
$$;
revoke execute on function public.ask_care_again_on_reconnect()
  from public, anon, authenticated;

drop trigger if exists ask_care_again_on_reconnect on public.guardian_senior_links;
create trigger ask_care_again_on_reconnect
  after insert or update of status on public.guardian_senior_links
  for each row execute function public.ask_care_again_on_reconnect();

-- ---------------------------------------------------------------------------
-- 해지 취소는 허락이 살아 있을 때만
-- ---------------------------------------------------------------------------

-- As in `20261029040000_care_cancel.sql`, except that buying again inside a
-- cancelled month resumes it only while the parent's 허락 stands. Waiting
-- on their second answer, there is nothing to buy; after a second 거절, a
-- purchase is a new one and asks them again, as a first purchase does.
create or replace function public.start_care_subscription(p_senior_profile_id uuid)
returns public.subscriptions
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  result public.subscriptions;
  consent text;
begin
  if not public.guardian_manages(p_senior_profile_id) then
    raise exception 'not allowed to manage this profile';
  end if;

  select paid_consent_status into consent
    from public.senior_profiles where id = p_senior_profile_id;

  if consent = 'pending' then
    raise exception '부모님의 답을 기다리고 있어요.';
  end if;

  if consent = 'granted' then
    update public.subscriptions
      set status = 'active', canceled_at = null, updated_at = now()
    where senior_profile_id = p_senior_profile_id
      and plan = 'care'
      and status = 'canceled'
      and current_period_end > now()
    returning * into result;

    if result.id is not null then
      return result;
    end if;
  end if;

  insert into public.subscriptions
    (guardian_account_id, senior_profile_id, plan, status)
  values (
    public.current_guardian_account_id(),
    p_senior_profile_id,
    'care',
    'pending_senior_consent'
  )
  returning * into result;

  -- The senior's phone reads this to know it has been asked.
  update public.senior_profiles
    set paid_consent_status = 'pending'
  where id = p_senior_profile_id;

  return result;
end;
$$;

-- ---------------------------------------------------------------------------
-- 읽은 날을 남긴다
-- ---------------------------------------------------------------------------

-- As in `20261028020000_pricing.sql`, plus the one call that records a day.
-- **No longer `stable`**: a stable function may not write, and Postgres
-- refuses the insert inside it rather than skipping it.
create or replace function public.senior_readings(p_senior_profile_id uuid)
returns table (
  visible boolean,
  trial_ends_at timestamptz,
  last_seen_at timestamptz,
  battery_percent int,
  is_charging boolean,
  ringer_mode text
)
language plpgsql
volatile
security definer
set search_path = public, auth
as $$
declare
  allowed boolean;
begin
  if not (
    public.guardian_manages(p_senior_profile_id)
    or public.device_owns(p_senior_profile_id)
  ) then
    raise exception 'not allowed to manage this profile';
  end if;

  allowed := public.care_readings_visible(p_senior_profile_id);

  -- The guardian's phone only. The parent's own phone reading its own
  -- battery is not their child using what they paid for.
  if allowed and public.guardian_manages(p_senior_profile_id) then
    perform public.record_care_use(p_senior_profile_id);
  end if;

  return query
    select allowed,
           public.care_trial_ends_at(p_senior_profile_id),
           -- Nulls rather than no row, so the screen can tell *we are not
           -- allowed to say* from *this phone has never checked in* - the
           -- two need different sentences and one of them is a sales line.
           case when allowed then d.last_seen_at end,
           case when allowed then d.battery_percent end,
           case when allowed then d.is_charging end,
           case when allowed then d.ringer_mode end
      from public.senior_devices d
     where d.senior_profile_id = p_senior_profile_id
       and d.is_active
     limit 1;
end;
$$;

revoke all on function public.senior_readings(uuid) from public;
grant execute on function public.senior_readings(uuid) to authenticated;
