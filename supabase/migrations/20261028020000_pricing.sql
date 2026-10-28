-- 무료와 안심 케어의 경계. Settled with the owner 2026-10-28.
--
-- The line was wrong, and it was wrong in the way that empties a paid tier:
-- `01_PRODUCT_PRD` says 무료는 부모님 폰이 편해지는 것, 유료는 보호자의 안심
-- 수요 - and the three things that reassure the **child** (안부 신호, the
-- battery and ringer reading, and seeing them on a dashboard) were all free.
-- What was left to sell was two alerts.
--
-- The line now: **무료는 부모님 폰을 편하게 만드는 것, 유료는 부모님이 어떻게
-- 지내시는지 아는 것.** Four changes carry it, and the fourth was a plain
-- defect rather than a pricing decision.
--
-- One rule runs through all of them: **the senior is never the one charged.**
-- Their own phone edits its own buttons without limit, their replies are
-- never counted, and nothing here can stop them reaching their family.

-- ---------------------------------------------------------------------------
-- 1. 가족 메시지, 월 50회 / 사진 10장 → 월 30회 / 사진 5장
-- ---------------------------------------------------------------------------

create or replace function public.family_message_quota(p_senior_profile_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  texts int;
  images int;
  unlimited boolean;
begin
  if not (
    public.guardian_manages(p_senior_profile_id)
    or public.device_owns(p_senior_profile_id)
  ) then
    raise exception 'not allowed to manage this profile';
  end if;

  unlimited := public.care_is_active(p_senior_profile_id);

  -- Calendar month, so the number resets on a date the family can predict
  -- rather than on a rolling window nobody can see.
  select
    count(*) filter (where image_url is null),
    count(*) filter (where image_url is not null)
  into texts, images
  from public.messages
  where senior_profile_id = p_senior_profile_id
    and sender_guardian_id is not null
    and created_at >= date_trunc('month', now());

  return jsonb_build_object(
    'unlimited', unlimited,
    'text_used', texts,
    'text_limit', 30,
    'image_used', images,
    'image_limit', 5
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. 자녀 폰에서 홈 화면 정리는 평생 2회
-- ---------------------------------------------------------------------------

alter table public.senior_profiles
  add column if not exists guardian_home_edits int not null default 0;

comment on column public.senior_profiles.guardian_home_edits is
  'How many times a guardian has saved this parent''s home screen from their '
  'own phone. The senior''s own saves are never counted.';

-- A lifetime count, not a monthly one, and the owner chose that knowing what
-- it costs: a guardian who spends both while setting up cannot fix a wrong
-- button remotely afterwards. What makes that survivable is the rule above -
-- **the senior's own phone is never limited**, so nothing on their home
-- screen is ever stuck, and 앱 설정하기 is two presses from it.
create or replace function public.guardian_home_edits_free()
returns int
language sql
immutable
as $$ select 2 $$;

create or replace function public.replace_home_apps(
  p_senior_profile_id uuid,
  p_apps jsonb
)
returns setof public.home_apps
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  is_device boolean;
  used int;
begin
  if not (
    public.guardian_manages(p_senior_profile_id)
    or public.device_owns(p_senior_profile_id)
  ) then
    raise exception 'not allowed to manage this profile';
  end if;

  -- Which phone is saving. The senior's own is free and unlimited; only the
  -- guardian's remote convenience is priced.
  is_device := public.device_owns(p_senior_profile_id);

  if not is_device and not public.care_is_active(p_senior_profile_id) then
    select guardian_home_edits into used
      from public.senior_profiles where id = p_senior_profile_id;
    if coalesce(used, 0) >= public.guardian_home_edits_free() then
      raise exception '무료로 바꿀 수 있는 횟수를 다 쓰셨어요.'
        using errcode = '42501';
    end if;
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
    label, icon_key, button_color, sort_order, is_default
  )
  select
    p_senior_profile_id,
    app ->> 'client_id',
    coalesce(app ->> 'app_type', 'system_app'),
    app ->> 'package_name',
    app ->> 'label',
    app ->> 'icon_key',
    app ->> 'button_color',
    coalesce((app ->> 'sort_order')::int, ordinality::int - 1),
    coalesce((app ->> 'is_default')::boolean, false)
  from jsonb_array_elements(p_apps) with ordinality as t(app, ordinality)
  on conflict (senior_profile_id, client_id) do update
    set app_type = excluded.app_type,
        package_name = excluded.package_name,
        label = excluded.label,
        icon_key = excluded.icon_key,
        button_color = excluded.button_color,
        sort_order = excluded.sort_order,
        is_default = excluded.is_default,
        updated_at = now();

  -- Counted **after** the write, so a save that failed costs nothing. And
  -- counted even on a subscription, so cancelling does not hand back a fresh
  -- two.
  if not is_device then
    update public.senior_profiles
       set guardian_home_edits = guardian_home_edits + 1
     where id = p_senior_profile_id;
  end if;

  return query
    select * from public.home_apps
     where senior_profile_id = p_senior_profile_id
     order by sort_order;
end;
$$;

revoke all on function public.replace_home_apps(uuid, jsonb) from public;
grant execute on function public.replace_home_apps(uuid, jsonb) to authenticated;
grant execute on function public.guardian_home_edits_free() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. 안부 신호와 배터리·소리는 첫 1주일만 무료
-- ---------------------------------------------------------------------------

-- The trial runs from the moment a family first attached to this parent, not
-- from the guardian's sign-up: a child who installs the app in March and
-- connects their mother in June should get the week in June.
create or replace function public.care_trial_ends_at(p_senior_profile_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path = public, auth
as $$
  select min(created_at) + interval '7 days'
    from public.guardian_senior_links
   where senior_profile_id = p_senior_profile_id;
$$;

create or replace function public.care_readings_visible(p_senior_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select public.care_is_active(p_senior_profile_id)
      or coalesce(public.care_trial_ends_at(p_senior_profile_id) > now(), false);
$$;

-- What the guardian's dashboard reads instead of the device row.
--
-- The gate has to live somewhere the app cannot skip, and a column cannot be
-- carved out of the table-level SELECT grant `authenticated` holds - that was
-- tried for `push_token` and written into its migration so nobody tries it
-- twice. So the readings move behind a function, and `activeDevice` stops
-- selecting them. **A guardian determined enough to query the table directly
-- can still see the columns**, which is the same accepted limit the push
-- token carries; what this stops is the app handing them over.
-- Dropped first: `create or replace` cannot change a function's return
-- type, and this one gained `is_charging` after a first pass named the
-- column `battery_charging`, which does not exist. The grants below are
-- what re-applies what the drop takes away.
drop function if exists public.senior_readings(uuid);

create function public.senior_readings(p_senior_profile_id uuid)
returns table (
  visible boolean,
  trial_ends_at timestamptz,
  last_seen_at timestamptz,
  battery_percent int,
  is_charging boolean,
  ringer_mode text
)
language plpgsql
stable
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
grant execute on function public.care_readings_visible(uuid) to authenticated;
grant execute on function public.care_trial_ends_at(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. 읽음 확인에 결제 확인이 없었다
-- ---------------------------------------------------------------------------

-- Not a pricing change - a defect. 읽음 확인 has been in the 5,900원 list
-- since the PRD and `mark_conversation_read` never checked anything, so it
-- worked for free. The other three paid capabilities all check.
--
-- Gated on the **senior's** call, which is the one that produces the receipt
-- a guardian reads. The guardian's own marking is untouched and always free:
-- it is what clears their unread badge, and there is deliberately no 읽음
-- shown to the senior at all, so nothing of theirs is being sold back.
create or replace function public.mark_conversation_read(
  p_senior_profile_id uuid
)
returns int
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  marked int := 0;
  is_device boolean;
begin
  if not (
    public.guardian_manages(p_senior_profile_id)
    or public.device_owns(p_senior_profile_id)
  ) then
    raise exception 'not allowed to read this conversation';
  end if;

  is_device := public.device_owns(p_senior_profile_id);

  -- No row is written rather than written and hidden. Nothing then exists to
  -- leak through a direct query, and a family that subscribes later starts
  -- from the next message rather than being handed a history of when their
  -- parent read things nobody had paid for.
  if is_device and not public.care_is_active(p_senior_profile_id) then
    return 0;
  end if;

  update public.messages m
     set read_at = now()
   where m.senior_profile_id = p_senior_profile_id
     and m.read_at is null
     -- The parent marks what guardians sent; a guardian marks what the
     -- parent sent. Neither can mark their own.
     and case
           when is_device then m.sender_guardian_id is not null
           else m.sender_device_id is not null
         end;

  get diagnostics marked = row_count;
  return marked;
end;
$$;

revoke all on function public.mark_conversation_read(uuid) from public, anon;
grant execute on function public.mark_conversation_read(uuid) to authenticated;
