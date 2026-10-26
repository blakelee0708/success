-- 소리 울리기's address book.
--
-- The guardian presses a button on their phone and the parent's has to make
-- a noise. Everything else the guardian changes is read by the parent's phone
-- the next time it asks, which is fine because none of it is urgent; a phone
-- nobody is holding cannot wait for the next resume.
--
-- The token lives on the device row rather than in a table of its own because
-- it is a property of *this install on this handset*, exactly like the battery
-- reading beside it, and it dies with the row when the phone is retired.

alter table public.senior_devices
  add column if not exists push_token text;

-- **A guardian in the family can read this column**, and that is accepted
-- rather than prevented. RLS is row-level, their policy already selects their
-- parent's device row, and a column cannot be carved out of the table-level
-- SELECT grant that `authenticated` holds — a `revoke select (push_token)`
-- against it is simply a no-op, which was tried and checked. Enforcing it
-- would mean revoking that grant and re-granting column by column, after
-- which every column added to this table breaks every read until somebody
-- remembers to grant it. That is a trap, and the thing it protects is inert:
-- a token sends nothing without the FCM service-account key, which lives in
-- Edge Function secrets and never reaches a client.
--
-- What is done instead is to not hand it out — `activeDevice` names its
-- columns, so the token is not shipped to either app in the ordinary read.
comment on column public.senior_devices.push_token is
  'FCM registration token, written by touch_senior_device. Readable by the '
  'family under RLS; useless without the service-account key. Clients select '
  'senior_devices by explicit column list so it is not sent to them.';

-- Carried by the check-in rather than by a call of its own: a token rotates
-- (reinstall, restore to a new handset, and occasionally for Firebase's own
-- reasons), and the check-in is the one thing that already runs on every
-- resume. A registration done once at pairing would have gone stale silently.
create or replace function public.touch_senior_device(
  p_install_id text,
  p_battery_percent integer default null,
  p_is_charging boolean default null,
  p_ringer_mode text default null,
  p_status_read_at timestamptz default null,
  p_push_token text default null
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
         push_token      = coalesce(p_push_token, push_token)
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

-- The five-argument signature is left behind by `create or replace` when the
-- argument list changes, and PostgREST would then have two candidates to
-- choose between. Dropped explicitly so there is one.
drop function if exists public.touch_senior_device(
  text, integer, boolean, text, timestamptz
);
