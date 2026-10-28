-- 문의하기 — the number an elderly person reads out to the support desk.
--
-- The case this exists for is the one the rest of the app cannot help: a
-- senior with **no family on the phone at all**. Everything else here assumes
-- a child to ask. 가족 연결 needs somebody to connect, 가족 메시지 needs
-- somebody to write to, and 긴급 연락's 보호자 tile is disabled until a
-- guardian gives a number. A senior who installed this alone, or whose child
-- set it up and then could not be reached, has nobody to ask why the phone is
-- doing something, and this app **is** their home screen.
--
-- **Why not `customer_code`.** That column already identifies a profile
-- uniquely and is written on every creation path, so it was the obvious
-- answer. It is eight characters from a 32-letter alphabet - `K7PQR2ST` - and
-- the whole point of this number is that it is **spoken down a telephone by
-- an eighty-year-old to a stranger**. Six digits read as two groups of three;
-- eight mixed letters and digits is the reading task this app exists because
-- its users cannot do.
--
-- A million codes with a four-digit alternative on the table: 10,000 is too
-- few to stay unique for long, and the generator loops on collision, so a
-- crowded space turns into a slow insert rather than a clash. Six is the
-- smallest size that is still easy to say.
--
-- It is **not a secret and not a credential.** It identifies a profile to a
-- person on the telephone; nothing is granted by holding it. `pair_links`
-- is where the short-lived secrets live, and a support number that expired
-- would be the opposite of useful.

alter table public.senior_profiles
  add column if not exists support_code text;

create or replace function public.generate_support_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  candidate text;
begin
  loop
    -- 100000..999999, so it is always six digits and never opens with a zero
    -- a senior might drop when reading it out.
    candidate := (100000 + floor(random() * 900000)::int)::text;
    exit when not exists (
      select 1 from public.senior_profiles where support_code = candidate
    );
  end loop;
  return candidate;
end;
$$;

-- A trigger rather than a line in each creating function. There are four
-- paths that insert a profile - `create_senior_profile`,
-- `start_senior_pairing`, `create_senior_invite` and whatever comes next -
-- and a profile with no support number is a senior who cannot be identified
-- when they ring. The one that gets forgotten would be the new one.
create or replace function public.fill_support_code()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.support_code is null then
    new.support_code := public.generate_support_code();
  end if;
  return new;
end;
$$;

drop trigger if exists senior_profiles_support_code on public.senior_profiles;
create trigger senior_profiles_support_code
  before insert on public.senior_profiles
  for each row execute function public.fill_support_code();

update public.senior_profiles
   set support_code = public.generate_support_code()
 where support_code is null;

alter table public.senior_profiles
  alter column support_code set not null;

create unique index if not exists senior_profiles_support_code_key
  on public.senior_profiles (support_code);

-- The senior's phone asking for its own number.
--
-- It **creates the profile when this install has none**, which is the whole
-- reason the function exists rather than a select: the senior this is for has
-- no family, so nothing has ever created one for them. That is not a new
-- behaviour - `start_senior_pairing` does exactly this, and 연결됨 has never
-- meant *a profile exists*, it means a guardian is attached. A number on this
-- card tells the senior nothing about their family either way.
--
-- It does not mint a pair link. 문의하기 is not a way of connecting anybody,
-- and a 4-digit code nobody asked for sitting live for ten minutes is a
-- secret created by a screen that had no use for one.
create or replace function public.ensure_senior_support_code(
  p_install_id text,
  p_platform text default null
)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  profile public.senior_profiles;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select p.* into profile
  from public.senior_profiles p
  join public.senior_devices d on d.senior_profile_id = p.id
  where d.install_id = p_install_id and d.is_active;

  if profile.id is null then
    insert into public.senior_profiles (display_name, customer_code)
    values ('부모님', public.generate_customer_code())
    returning * into profile;
  end if;

  -- Also rebinds `auth_user_id` for a phone whose anonymous session was
  -- replaced, which is the one repair the senior's half can make for itself.
  perform public.attach_senior_device(
    profile.id, p_install_id, null, p_platform, null);

  return profile.support_code;
end;
$$;

-- `from public` as well as by name, and that order matters. Supabase's default
-- privileges grant EXECUTE on a new function to PUBLIC, and revoking from
-- `anon, authenticated` alone leaves that standing: the generator answered a
-- client with a fresh code until the verifier said so.
revoke all on function public.generate_support_code() from public;
revoke all on function public.generate_support_code() from anon;
revoke all on function public.generate_support_code() from authenticated;
revoke all on function public.fill_support_code() from public;
revoke all on function public.fill_support_code() from anon;
revoke all on function public.fill_support_code() from authenticated;
revoke all on function public.ensure_senior_support_code(text, text) from public;
revoke all on function public.ensure_senior_support_code(text, text) from anon;
grant execute on function public.ensure_senior_support_code(text, text) to authenticated;
