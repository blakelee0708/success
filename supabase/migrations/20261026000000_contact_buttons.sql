-- 사람 버튼 — a person on the home screen instead of an app.
--
-- Seniors fail at finding *people* far more often than at finding apps:
-- opening 연락처 and scrolling is where they give up. A button that reads
-- 딸 영희 and opens the dialer with her number already in it removes the
-- step they actually lose.
--
-- `app_type` already allowed `'family_contact'` — `05_DATA_MODEL` anticipated
-- this in Phase 4 and nothing ever wrote one. The column to hold the number
-- was the only missing piece.
--
-- The number is supplied by the **guardian**, from their own phone. That is
-- what keeps a contacts permission off the parent's phone entirely: the
-- launcher never reads the address book, it is handed one number at a time.

alter table public.home_apps
  add column if not exists phone_number text;

-- Carried through the existing sync. `replace_home_apps` rewrites the whole
-- list on every save, so the insert column list is the only place that needs
-- to know about a new field.
create or replace function public.replace_home_apps(
  p_senior_profile_id uuid,
  p_apps jsonb
)
returns setof public.home_apps
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not (
    public.guardian_manages(p_senior_profile_id)
    or public.device_owns(p_senior_profile_id)
  ) then
    raise exception 'not allowed to manage this profile';
  end if;

  -- `not exists` rather than `not in`: a payload row with a missing client_id
  -- would turn `not in` null and silently delete nothing.
  delete from public.home_apps h
  where h.senior_profile_id = p_senior_profile_id
    and not exists (
      select 1
      from jsonb_array_elements(p_apps) e
      where e.value ->> 'client_id' = h.client_id
    );

  insert into public.home_apps (
    senior_profile_id, client_id, app_type, package_name,
    label, icon_key, button_color, phone_number, sort_order, is_default
  )
  select
    p_senior_profile_id,
    app ->> 'client_id',
    coalesce(app ->> 'app_type', 'system_app'),
    app ->> 'package_name',
    app ->> 'label',
    app ->> 'icon_key',
    app ->> 'button_color',
    app ->> 'phone_number',
    -- The ordinality fallback is the original's and is kept: a payload that
    -- omits sort_order still lands in the order it was sent.
    coalesce((app ->> 'sort_order')::int, ordinality::int - 1),
    coalesce((app ->> 'is_default')::boolean, false)
  from jsonb_array_elements(p_apps) with ordinality as t(app, ordinality)
  on conflict (senior_profile_id, client_id) do update
    set app_type = excluded.app_type,
        package_name = excluded.package_name,
        label = excluded.label,
        icon_key = excluded.icon_key,
        button_color = excluded.button_color,
        phone_number = excluded.phone_number,
        sort_order = excluded.sort_order,
        is_default = excluded.is_default,
        -- Not in the original, and it should have been: a rename left
        -- updated_at reading the moment the row was first created.
        updated_at = now();

  return query
    select * from public.home_apps
     where senior_profile_id = p_senior_profile_id
     order by sort_order;
end;
$$;

revoke all on function public.replace_home_apps(uuid, jsonb) from public, anon;
grant execute on function public.replace_home_apps(uuid, jsonb) to authenticated;
