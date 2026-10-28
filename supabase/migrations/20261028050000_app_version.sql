-- 부모님 폰의 앱이 오래됐어요 — the one thing Play will not fix by itself.
--
-- **A launcher is the app Play cannot auto-update.** It installs an update
-- only while the app is not the one in front of the user, and this app *is*
-- the home screen. Add to that the Wi-Fi-only default on a phone whose owner
-- may have no Wi-Fi at all, and the parent's handset can sit on one build
-- forever with nobody aware of it.
--
-- The senior is the last person who should be asked to go and fix that, which
-- is the rule the whole app follows. So the version rides up on the check-in
-- and the guardian's dashboard is what says something.
--
-- **It is free, and deliberately not a reading.** 안부 신호, the battery and
-- the ringer are what 안심 케어 sells and they go through `senior_readings`.
-- Which build a phone is running is not about how the parent is - it is
-- housekeeping about the app itself, and a family locked out of that would be
-- a family that cannot be helped.
alter table public.senior_devices
  add column if not exists app_version text;

create or replace function public.touch_senior_device(
  p_install_id text,
  p_battery_percent integer default null,
  p_is_charging boolean default null,
  p_ringer_mode text default null,
  p_status_read_at timestamptz default null,
  p_push_token text default null,
  p_app_version text default null
)
returns void
language plpgsql
security definer
set search_path to 'public', 'auth'
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
         status_read_at  = coalesce(p_status_read_at, status_read_at),
         -- Same rule, and it matters more here: clearing a good token
         -- because the network was down for a second would leave the phone
         -- unreachable until Firebase next rotated it.
         push_token      = coalesce(p_push_token, push_token),
         -- And here it matters in the other direction: a null that erased
         -- the version would read as 말할 수 없음, which the dashboard is
         -- careful never to round into 오래됐어요.
         app_version     = coalesce(p_app_version, app_version)
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

-- The six-argument signature is left behind by `create or replace` when the
-- argument list changes, and PostgREST would then have two candidates to
-- choose between. Dropped explicitly so there is one.
drop function if exists public.touch_senior_device(
  text, integer, boolean, text, timestamptz, text
);

grant execute on function public.touch_senior_device(
  text, integer, boolean, text, timestamptz, text, text
) to authenticated;
