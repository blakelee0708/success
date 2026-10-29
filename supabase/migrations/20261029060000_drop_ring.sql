-- 소리 울리기 is out of the product, server half included.
--
-- It was the one paid capability with no privacy question at all: it
-- collected nothing and sent nothing about the parent. What it had instead
-- were two problems money and time do not fix.
--
-- **It did not work.** A push reaches the app only while the app is in the
-- foreground, so it rang a phone that was awake and not one that was asleep
-- - and a phone nobody is holding is the entire case the feature existed
-- for. Closing that needs a background handler, native code to bring the
-- screen forward, and on Android 14 the `USE_FULL_SCREEN_INTENT` route,
-- which is not granted to a launcher by default.
--
-- **And it had no precedent.** No published app was found that lets one
-- adult make another adult's phone sound. A reviewer meeting it for the
-- first time, on a tier whose other five things do work, was the trade
-- worth refusing.
--
-- So the gate goes, and with it the address it sent to.

-- The gate. Nothing in the app calls it, and leaving it callable would leave
-- a way to make somebody's phone ring that no screen in the app asks for.
drop function if exists public.request_phone_ring(uuid, text);

-- **The check-in stops asking for a token**, which is the part worth
-- reading. An FCM token is an address, and with nothing left to send to it,
-- holding one is collecting something for no purpose - the same reason
-- `senior_devices.permission_status` is absent from `site/privacy.html`:
-- what is never used is not collected.
--
-- The guardian's own token is untouched. `guardian_accounts.push_token` is
-- what tells a child their parent wrote to them, and that is the one
-- direction left.
create or replace function public.touch_senior_device(
  p_install_id text,
  p_battery_percent integer default null,
  p_is_charging boolean default null,
  p_ringer_mode text default null,
  p_status_read_at timestamptz default null,
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
         -- Here the rule matters in the other direction: a null that erased
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

-- The seven-argument signature is left behind by `create or replace` when
-- the argument list changes, and PostgREST would then have two candidates
-- and refuse to choose. Dropped so there is one.
--
-- **A build older than this one stops checking in**, because it sends
-- `p_push_token` and no function takes it. That is accepted: nothing is
-- published yet, every APK is a sideloaded debug build, and the alternative
-- is worse - a compatibility wrapper taking the token and discarding it
-- would make the six-argument call ambiguous, so every phone would fail
-- instead of only the old ones.
drop function if exists public.touch_senior_device(
  text, integer, boolean, text, timestamptz, text, text
);

grant execute on function public.touch_senior_device(
  text, integer, boolean, text, timestamptz, text
) to authenticated;

-- The column, last, because the gate selected it.
--
-- Dropping rather than clearing: a column nothing writes and nothing reads
-- is a thing the privacy policy has to keep accounting for, and the next
-- person to find it would reasonably wire something to it.
alter table public.senior_devices
  drop column if exists push_token;
