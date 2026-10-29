-- 안심 케어 해지, and the month it is a month of.
--
-- **The 안심 케어 tab has been promising this since Phase 6.** It says
-- 월 5,900원 / **언제든 해지할 수 있습니다** under the buy button, and
-- nothing in the app or the schema could. `subscriptions.status` has carried
-- 'canceled' and the table a `canceled_at` column from the day it was
-- written, and nothing ever wrote either - the same shape `'pending'` and
-- `'removed'` were in before this week. Play asks for it too: *you must also
-- provide an option for users to cancel their subscriptions in your app*.
--
-- **Everything here is built to the shape Play Billing will arrive in**, so
-- that the day it lands nothing has to be undone:
--
-- - `current_period_end` is ours to compute today and **Google's to
--   overwrite** tomorrow. When a real subscription exists the renewal
--   instant is `expiryTimeMillis`, to the millisecond, and if our number
--   disagrees with Google's the user is looking at two screens that say
--   different things. Google wins.
-- - `purchase_token` is the only string that ties our row to Google's
--   subscription. Without it a Real Time Developer Notification arrives and
--   nothing can tell which row it is about. It costs one column now and is
--   unrecoverable later, because the notification does not carry our ids.
-- - **Cancelling does not switch anything off.** That is how a Play
--   subscription behaves and it is what `site/terms.html` already promises:
--   남은 기간까지는 계속 쓰실 수 있습니다. `care_is_active` therefore has to
--   accept a cancelled row whose period has not run out, or the senior's
--   안부 신호 would stop the moment their child pressed 해지.

alter table public.subscriptions
  add column if not exists current_period_end timestamptz;

alter table public.subscriptions
  add column if not exists purchase_token text;

comment on column public.subscriptions.current_period_end is
  'When the paid period runs out. Computed here while there is no Billing; '
  'once there is, this is Google''s expiryTimeMillis and Google is right.';

comment on column public.subscriptions.purchase_token is
  'Google Play''s purchase token. Null until Billing exists. It is what a '
  'Real Time Developer Notification is matched on.';

-- One Google subscription is one row of ours.
create unique index if not exists subscriptions_purchase_token
  on public.subscriptions (purchase_token)
  where purchase_token is not null;

-- 한 달은 30일이 아니라 다음 달 같은 날 같은 시각.
--
-- 30 days is wrong in seven months of the year, and the month has to be
-- added **in Seoul**: these are `timestamptz`, so `+ interval '1 month'` is
-- computed in whatever the session's TimeZone happens to be, and the same
-- purchase would land on a different date depending on a server setting.
--
-- 1월 31일 01:00 has no 2월 31일 to land on. Postgres answers 2월 28일 01:00,
-- which is the rule a person would give, and it is written down here because
-- it is the case that breaks quietly rather than loudly.
create or replace function public.one_month_after(p_at timestamptz)
returns timestamptz
language sql
immutable
as $$
  select ((p_at at time zone 'Asia/Seoul') + interval '1 month')
           at time zone 'Asia/Seoul';
$$;

-- The month runs from the senior's 허락합니다, not from the payment - and
-- never more than three hours from the payment.
--
-- **The anchor is the consent** because that is when the thing being paid
-- for starts working: a guardian who pays at one in the morning and whose
-- mother answers at nine has had nothing for eight hours.
--
-- **The cap is three hours** because Google renews on the *payment*
-- instant, and an anchor that could sit days later would leave our expiry
-- and Google's renewal permanently out of step, by an amount nobody could
-- explain. Three hours is a gap small enough to ignore, and only the first
-- period carries it at all: every renewal after that is Google's own date
-- arriving through `current_period_end`.
create or replace function public.care_period_anchor(
  p_started_at timestamptz,
  p_agreed_at timestamptz
)
returns timestamptz
language sql
immutable
as $$
  select least(p_agreed_at, p_started_at + interval '3 hours');
$$;

-- Consent is what starts the month, so it is what writes the end of it.
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
begin
  if not public.device_owns(p_senior_profile_id) then
    raise exception 'only the senior device can answer this';
  end if;

  if not exists (
    select 1 from public.subscriptions
    where senior_profile_id = p_senior_profile_id
      and plan = 'care' and status = 'pending_senior_consent'
  ) then
    raise exception 'nothing to answer';
  end if;

  update public.subscriptions
    set status = case when p_approve then 'active' else 'refunded' end,
        refunded_at = case when p_approve then null else now() end,
        current_period_end = case
          when p_approve then public.one_month_after(
            public.care_period_anchor(started_at, now()))
          else null
        end,
        updated_at = now()
  where senior_profile_id = p_senior_profile_id
    and plan = 'care' and status = 'pending_senior_consent';

  update public.senior_profiles
    set paid_consent_status = case when p_approve then 'granted' else 'refused' end
  where id = p_senior_profile_id
  returning * into profile;

  insert into public.alerts (senior_profile_id, type, title, body)
  values (
    p_senior_profile_id,
    case when p_approve then 'care_consent_granted' else 'care_consent_refused' end,
    case
      when p_approve then profile.display_name || '님이 안심 케어를 허락하셨어요'
      else profile.display_name || '님이 안심 케어를 원하지 않으셨어요'
    end,
    case
      when p_approve then '이제 부모님이 어떻게 지내시는지 보실 수 있어요.'
      else '결제는 환불 처리되었습니다. 무료 기능은 그대로 쓰실 수 있어요.'
    end
  );

  return profile;
end;
$$;

-- 해지하기.
--
-- **Two different rows can be cancelled and they end differently**, which is
-- the whole reason this is not one update:
--
-- - An `active` one has been running. It becomes `canceled` and keeps its
--   `current_period_end`, so everything stays on until the month is up. No
--   money comes back; a refund is the other request, and it goes to the
--   address in `site/terms.html`.
-- - A `pending_senior_consent` one never started. The senior has not
--   answered, nothing was delivered, so it is `refunded` and the card on
--   their phone goes away. Without this the guardian who changes their mind
--   is held until their mother answers a question they no longer want asked.
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
  was text;
begin
  if not public.guardian_manages(p_senior_profile_id) then
    raise exception 'not allowed to manage this profile';
  end if;

  select status into was from public.subscriptions
   where senior_profile_id = p_senior_profile_id
     and plan = 'care'
     and status in ('active', 'pending_senior_consent');

  if was is null then
    raise exception 'nothing to cancel';
  end if;

  update public.subscriptions
    set status = case when was = 'active' then 'canceled' else 'refunded' end,
        canceled_at = now(),
        refunded_at = case when was = 'active' then null else now() end,
        updated_at = now()
  where senior_profile_id = p_senior_profile_id
    and plan = 'care'
    and status in ('active', 'pending_senior_consent')
  returning * into result;

  -- An unanswered question is withdrawn rather than left on their screen.
  if was = 'pending_senior_consent' then
    update public.senior_profiles
      set paid_consent_status = 'none'
    where id = p_senior_profile_id;
  end if;

  return result;
end;
$$;

-- Both halves are still required, and the consent half still decides. What
-- is new is that **a cancelled subscription is live until its month runs
-- out** - the behaviour Play Billing has, and the one `site/terms.html`
-- already promises. Without this clause pressing 해지 would stop the
-- senior's 안부 신호 the same second, on a month their child has paid for.
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
  );
$$;

-- Buying again inside the month you already cancelled is 해지 취소, not a
-- second subscription. Play does the same, and without this the unique index
-- would not stop it: it only covers 'active' and 'pending_senior_consent',
-- so a cancelled-but-live row would sit beside a brand new one and the
-- family would be asked for consent they have already given.
create or replace function public.start_care_subscription(p_senior_profile_id uuid)
returns public.subscriptions
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  result public.subscriptions;
begin
  if not public.guardian_manages(p_senior_profile_id) then
    raise exception 'not allowed to manage this profile';
  end if;

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

grant execute on function public.one_month_after(timestamptz) to authenticated;
grant execute on function public.care_period_anchor(timestamptz, timestamptz)
  to authenticated;
grant execute on function public.cancel_care_subscription(uuid) to authenticated;
