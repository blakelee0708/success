-- 월 30회 / 사진 5장, said once.
--
-- **The counter and the gate disagreed, and the gate was the stale one.**
-- `20261028020000_pricing.sql` repriced 가족 메시지 from 월 50회 / 사진 10장
-- to the PRD's 30 / 5 by rewriting `family_message_quota` - and
-- `send_family_message` keeps its own copy of the same two numbers, which
-- nobody touched. So the guardian's screen counted down from 30, said
-- `메시지 0번 더 보낼 수 있어요`, raised the 안심 케어 sheet, and the server
-- would have accepted twenty more.
--
-- Which way round that failed is worth recording. The app checks the quota
-- **before** the write - see `## Every refusal is an offer` - so the number
-- on the screen was the one in force and nothing was oversold. What was
-- broken is the thing the server gate exists for: a client that asks the
-- server directly, or an older build, was not held to the price at all.
--
-- `tool/verify_supabase_messages.py` is what found it, and only once it was
-- made to run again: it had been asserting 50 and 10 since Phase 7, so it
-- agreed with the stale half and passed. The one in the pair that was right
-- about the price, `tool/verify_supabase_pricing.py`, never sent a 31st
-- message.
--
-- So the numbers go where `guardian_home_edits_free()` already is: one
-- function each, read by both callers. The next reprice is one line and
-- cannot land on half the rule.

create or replace function public.family_text_free()
returns int
language sql
immutable
as $$ select 30 $$;

create or replace function public.family_image_free()
returns int
language sql
immutable
as $$ select 5 $$;

comment on function public.family_text_free() is
  '무료 가족 메시지 월 한도. Read by family_message_quota and by '
  'send_family_message, so the screen and the gate cannot drift apart.';

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
    'text_limit', public.family_text_free(),
    'image_used', images,
    'image_limit', public.family_image_free()
  );
end;
$$;

create or replace function public.send_family_message(
  p_senior_profile_id uuid,
  p_body text default null,
  p_image_url text default null
)
returns public.messages
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  guardian_id uuid;
  device_id uuid;
  used int;
  result public.messages;
begin
  guardian_id := public.current_guardian_account_id();

  select id into device_id
  from public.senior_devices
  where senior_profile_id = p_senior_profile_id
    and auth_user_id = auth.uid()
    and is_active;

  if device_id is null then
    -- A guardian, then - and only one who actually looks after this parent.
    if guardian_id is null or not public.guardian_manages(p_senior_profile_id) then
      raise exception 'not allowed to manage this profile';
    end if;

    -- The quota applies here and nowhere else. The senior's replies fall
    -- through to the insert below without ever being counted: a launcher for
    -- an elderly person that refuses to let them answer their daughter
    -- because a monthly allowance ran out is selling the wrong thing.
    if not public.care_is_active(p_senior_profile_id) then
      if p_image_url is not null then
        select count(*) into used from public.messages
        where senior_profile_id = p_senior_profile_id
          and sender_guardian_id is not null
          and image_url is not null
          and created_at >= date_trunc('month', now());
        if used >= public.family_image_free() then
          raise exception 'image quota reached';
        end if;
      else
        select count(*) into used from public.messages
        where senior_profile_id = p_senior_profile_id
          and sender_guardian_id is not null
          and image_url is null
          and created_at >= date_trunc('month', now());
        if used >= public.family_text_free() then
          raise exception 'message quota reached';
        end if;
      end if;
    end if;
  else
    -- Sent from the parent's phone. `guardian_id` is cleared so the row
    -- records one sender, even if this auth user somehow also holds a
    -- guardian account.
    guardian_id := null;
  end if;

  insert into public.messages
    (senior_profile_id, sender_guardian_id, sender_device_id, body, image_url)
  values (
    p_senior_profile_id,
    guardian_id,
    device_id,
    nullif(trim(coalesce(p_body, '')), ''),
    p_image_url
  )
  returning * into result;

  return result;
end;
$$;

grant execute on function public.family_text_free() to authenticated;
grant execute on function public.family_image_free() to authenticated;
grant execute on function public.family_message_quota(uuid) to authenticated;
grant execute on function public.send_family_message(uuid, text, text)
  to authenticated;
