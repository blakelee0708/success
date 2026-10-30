-- Settings the app reads from the server, so they change without an update.
--
-- **A launcher is the app Play will not update** (it is always the one in
-- front of the user), so anything that might need to change after a parent's
-- phone is set up has to be read rather than built in. One row, read by
-- anybody - nothing in it is about a person.
--
-- `store_listed` is the first: whether the 설치 링크 text is sent. Until the
-- app is on Play the store link opens a page that does not exist, so the
-- guardian sends one text - the number - and the parent's app was installed
-- by hand. Turned on the day the listing goes live, with no app update.
--
-- `latest_build` is the newest build on Play, for telling a guardian their
-- own app is out of date. Null says nothing, which is what it says now.

create table if not exists public.app_config (
  id boolean primary key default true check (id),
  store_listed boolean not null default false,
  latest_build int check (latest_build is null or latest_build > 0),
  updated_at timestamptz not null default now()
);

insert into public.app_config (id) values (true) on conflict (id) do nothing;

alter table public.app_config enable row level security;

drop policy if exists app_config_read on public.app_config;
create policy app_config_read on public.app_config
  for select to anon, authenticated using (true);

-- Written from the dashboard or the Management API only.
revoke insert, update, delete on public.app_config from anon, authenticated;
