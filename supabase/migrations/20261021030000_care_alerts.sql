-- 배터리 부족 알림 and 폰 미사용 알림.
--
-- Both are named in the PRD's 안심 케어 list, so both are gated on
-- `care_is_active` — which is a subscription *and* the senior's consent, and
-- with no Play Billing yet means neither fires for anybody today. That is the
-- right shape to build: the PRD is the owner's to change, not this file's.
--
-- The `alerts` table and the 돌봄 tab that renders it have existed since
-- Phase 6. Only one thing ever wrote a row — the refund — so this is the
-- first time anything watches.
--
-- The two need opposite machinery, which is the whole interest of them:
--
--   배터리 부족  fires on an event. The parent's phone reports 12% and the
--                row is written on the way through `touch_senior_device`.
--   폰 미사용    fires on the *absence* of events, so nothing the phone does
--                can trigger it. It needs something that runs when nothing
--                happens, which is pg_cron.

-- ---------------------------------------------------------------------------
-- the two new kinds
-- ---------------------------------------------------------------------------

alter table public.alerts drop constraint if exists alerts_type_check;
alter table public.alerts add constraint alerts_type_check check (
  type in (
    'care_consent_refused',
    'care_consent_granted',
    'location_permission_refused',
    'unknown_contact_call',
    'app_installed',
    'battery_low',
    'phone_unused'
  )
);

-- Hysteresis. Without it a phone sitting at 12% writes an alert on every
-- resume — dozens a day, which is not an alert, it is a reason to stop
-- reading alerts. One row per low spell: raised when it crosses down, armed
-- again only once the battery is genuinely back up or on the charger.
alter table public.senior_devices
  add column if not exists battery_low_notified boolean not null default false;

-- Which check-in the 미사용 alert was about. A phone that is picked up moves
-- `last_seen_at` past this, which arms the next one by itself — no clearing
-- step, and nothing to go stale if a job is missed.
alter table public.senior_profiles
  add column if not exists unused_notified_for timestamptz;

-- ---------------------------------------------------------------------------
-- 배터리 부족 — on the check-in
-- ---------------------------------------------------------------------------

-- Matches `DeviceStatusLines.isBatteryLow` on the guardian's card, and for the
-- same reason: a low battery on the charger is a problem being solved, and
-- flagging it teaches the guardian to ignore the flag.
create or replace function public.raise_battery_alert(
  p_senior_profile_id uuid,
  p_install_id text,
  p_battery_percent int,
  p_is_charging boolean
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  already boolean;
begin
  if p_battery_percent is null then
    return;
  end if;

  select battery_low_notified into already
    from public.senior_devices
   where install_id = p_install_id;

  -- Back up, or plugged in: arm the next one and say nothing. Recovering at
  -- 30 rather than at the 15 it fires on is what stops a phone hovering on
  -- the line from alerting every few minutes.
  if p_battery_percent >= 30 or coalesce(p_is_charging, false) then
    if already then
      update public.senior_devices
         set battery_low_notified = false
       where install_id = p_install_id;
    end if;
    return;
  end if;

  if p_battery_percent > 15 or coalesce(already, false) then
    return;
  end if;

  -- Paid, and only once the senior has agreed. A subscription with no
  -- consent has to behave exactly like no subscription.
  if not public.care_is_active(p_senior_profile_id) then
    return;
  end if;

  insert into public.alerts (senior_profile_id, type, title, body, metadata)
  values (
    p_senior_profile_id,
    'battery_low',
    '부모님 폰 배터리가 얼마 없어요',
    p_battery_percent || '% 남았고 충전 중이 아니에요.',
    jsonb_build_object('battery_percent', p_battery_percent)
  );

  update public.senior_devices
     set battery_low_notified = true
   where install_id = p_install_id;
end;
$$;

-- Folded into the check-in rather than given a call of its own: the reading
-- and the judgement about it are one event, and a second round trip is a
-- second thing to fail on a phone that may have one bar.
create or replace function public.touch_senior_device(
  p_install_id text,
  p_battery_percent int default null,
  p_is_charging boolean default null,
  p_ringer_mode text default null,
  p_status_read_at timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  profile_id uuid;
begin
  update public.senior_devices
     set last_seen_at = now(),
         updated_at = now(),
         -- A phone that could not read a value sends null, and null leaves
         -- the last real reading standing. Writing the null through would
         -- turn one failed read into an erased battery level.
         battery_percent = coalesce(p_battery_percent, battery_percent),
         is_charging     = coalesce(p_is_charging, is_charging),
         ringer_mode     = coalesce(p_ringer_mode, ringer_mode),
         status_read_at  = coalesce(p_status_read_at, status_read_at)
   where install_id = p_install_id
     and auth_user_id = auth.uid()
  returning senior_profile_id into profile_id;

  if profile_id is not null and p_battery_percent is not null then
    perform public.raise_battery_alert(
      profile_id, p_install_id, p_battery_percent, p_is_charging
    );
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 폰 미사용 — on the absence of a check-in
-- ---------------------------------------------------------------------------

create or replace function public.check_unused_phones(
  p_quiet_days int default 2
)
returns int
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  written int := 0;
begin
  with quiet as (
    select p.id, d.last_seen_at
      from public.senior_profiles p
      join public.senior_devices d
        on d.senior_profile_id = p.id and d.is_active
     where d.last_seen_at is not null
       -- A phone that has never checked in is 연결되기 전, not 미사용. There
       -- is nothing to tell the guardian that their own dashboard does not
       -- already say.
       and d.last_seen_at < now() - make_interval(days => p_quiet_days)
       -- Already said, about this same silence. Picking the phone up moves
       -- last_seen_at past this by itself.
       and (p.unused_notified_for is null
            or p.unused_notified_for < d.last_seen_at)
       and public.care_is_active(p.id)
  ), written_rows as (
    insert into public.alerts (senior_profile_id, type, title, body, metadata)
    select
      q.id,
      'phone_unused',
      '부모님이 한동안 폰을 안 쓰셨어요',
      to_char(
        extract(day from now() - q.last_seen_at)::int, 'FM999'
      ) || '일째 폰을 켜지 않으셨어요.',
      jsonb_build_object('last_seen_at', q.last_seen_at)
    from quiet q
    returning senior_profile_id
  ), marked as (
    -- The check-in the alert was *about*, not the moment it was written.
    -- Storing `now()` reads as "we have spoken recently", which is a
    -- different claim: a phone picked up and then left again for a week
    -- compares its new silence against a mark already past it and stays
    -- quiet forever. Storing the check-in means a later one arms the next
    -- alert by itself, with no clearing step to miss.
    update public.senior_profiles p
       set unused_notified_for = q.last_seen_at
      from quiet q
     where p.id = q.id
    returning p.id
  )
  select count(*) into written from written_rows;

  return written;
end;
$$;

-- pg_cron, because this fires on nothing happening. Supabase installs it into
-- its own schema and runs it as the database owner, so the function must not
-- read `auth.uid()` — it does not.
create extension if not exists pg_cron with schema cron;

select cron.unschedule('check-unused-phones')
 where exists (
   select 1 from cron.job where jobname = 'check-unused-phones'
 );

-- 09:07 KST. Morning, so a guardian reads it at a time they could act on it,
-- and off the hour because every other job in the world runs at :00.
select cron.schedule(
  'check-unused-phones',
  '7 0 * * *',
  $$select public.check_unused_phones()$$
);

-- ---------------------------------------------------------------------------
-- grants
-- ---------------------------------------------------------------------------

-- Neither of these is something a client calls. The check-in reaches the
-- battery one through `touch_senior_device`, and the sweep belongs to cron.
revoke all on function public.raise_battery_alert(uuid, text, int, boolean)
  from public, anon, authenticated;
revoke all on function public.check_unused_phones(int)
  from public, anon, authenticated;
