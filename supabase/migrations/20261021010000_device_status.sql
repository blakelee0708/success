-- 기기 상태 — the battery and the ringer, carried by the check-in.
--
-- The second of 안심 케어's four capabilities, and the second that can exist
-- before 위치정보 is cleared: Android hands any app the battery level and the
-- ringer mode with no runtime permission, no manifest permission and nothing
-- for Play to review.
--
-- There is no new schedule. `07_PHASE_PLAN` asks for a 5-minute background
-- sync, which is a foreground service — but a reading is worth having exactly
-- when the parent used the phone, and `touch_senior_device` already fires at
-- that moment. One call, one row, one thing to fail.
--
-- 인터넷 is deliberately absent. Reporting it would mean ACCESS_NETWORK_STATE,
-- and the answer is already in `status_read_at`: a reading that arrived is a
-- reading that got through.

alter table public.senior_devices
  add column if not exists battery_percent int
    check (battery_percent is null
           or (battery_percent >= 0 and battery_percent <= 100)),
  add column if not exists is_charging boolean,
  add column if not exists ringer_mode text
    check (ringer_mode is null
           or ringer_mode in ('silent', 'vibrate', 'normal')),
  -- Stamped on the parent's phone when the reading was taken, not here when
  -- it arrived. On a phone that was offline for an hour those are different
  -- times, and the guardian's card states the age of the reading.
  add column if not exists status_read_at timestamptz;

-- Widened rather than joined by a second function: the reading and the
-- check-in are one event. Dropped first because the parameter list changes —
-- `create or replace` would leave the one-argument version standing beside
-- the new one and PostgREST would have two candidates to choose between.
drop function if exists public.touch_senior_device(text);

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
begin
  update public.senior_devices
     set last_seen_at = now(),
         updated_at = now(),
         -- A phone that could not read a value sends null, and null leaves
         -- the last real reading standing. Writing the null through would
         -- turn one failed read into an erased battery level, and the card
         -- would go from 72% to 아직 받지 못했어요 for no reason the guardian
         -- could see.
         battery_percent = coalesce(p_battery_percent, battery_percent),
         is_charging     = coalesce(p_is_charging, is_charging),
         ringer_mode     = coalesce(p_ringer_mode, ringer_mode),
         status_read_at  = coalesce(p_status_read_at, status_read_at)
   where install_id = p_install_id
     and auth_user_id = auth.uid();
end;
$$;

-- `is_active` is still deliberately untouched; see the previous migration.

revoke all on function public.touch_senior_device(
  text, int, boolean, text, timestamptz) from public;
revoke all on function public.touch_senior_device(
  text, int, boolean, text, timestamptz) from anon;
grant execute on function public.touch_senior_device(
  text, int, boolean, text, timestamptz) to authenticated;
