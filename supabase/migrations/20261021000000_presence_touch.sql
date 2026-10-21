-- 안부 신호 — the parent's phone reporting that it is still being used.
--
-- `last_seen_at` has existed since Phase 4, but nothing ever wrote it after
-- the moment the phone registered: `register_senior_device` set it once and
-- no other path touched it. The guardian's hero card read that column in the
-- present tense, so a phone set up in July and never opened since still lit
-- the green dot and read 폰은 잘 켜져 있어요. The column was right and the
-- writer was missing.
--
-- This is the cheapest capability in the whole product and the only one of
-- 안심 케어's readings that needs no permission at all: the launcher is the
-- phone's home screen, so coming to the foreground means the parent unlocked
-- it or came back from another app. No location, no sensor, no background
-- service, nothing for Play to review and nothing extra for the senior to
-- agree to.
--
-- It is a function rather than a table write so that a reporting call can
-- only ever move this one column. `senior_devices_write_own` would let a
-- device rewrite its whole row, including `is_active` and which profile it
-- belongs to, and a call made on every resume is the last place to hand that
-- reach out.

create or replace function public.touch_senior_device(p_install_id text)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  -- Scoped to the caller's own row by `auth_user_id`, exactly as the policy
  -- would be. A phone cannot report on behalf of another phone, and a row
  -- that matches nothing is simply not updated: the parent's launcher must
  -- not be shown an error for a courtesy it is paying no attention to.
  update public.senior_devices
     set last_seen_at = now(),
         updated_at = now()
   where install_id = p_install_id
     and auth_user_id = auth.uid();
end;
$$;

-- `is_active` is deliberately left alone. A phone the parent has replaced may
-- still have the app on it and still resume; letting a report flip that flag
-- back would hand the retired handset the profile again, and the unique index
-- on one active device per profile would start rejecting the real one.

revoke all on function public.touch_senior_device(text) from public;
-- `anon` is revoked by name as well as through `public`. Supabase's default
-- privileges grant EXECUTE on new functions to anon explicitly, and revoking
-- from PUBLIC does not take an explicit grant away. The senior's phone signs
-- in anonymously but that is a real session with the `authenticated` role, so
-- nothing the app does needs this.
revoke all on function public.touch_senior_device(text) from anon;
grant execute on function public.touch_senior_device(text) to authenticated;
