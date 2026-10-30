-- 공지: what the company tells the people using the app, written on the
-- server so it reaches phones that will never be updated.
--
-- **A launcher is the app Play will not update**, so this had to ship in the
-- first build or never reach the phones that most need it: a notice added in
-- an update cannot be read by a phone that did not take the update.
--
-- Service notices only - 점검, 기능 안내, 업데이트 안내. Anything that is
-- advertising needs 수신 동의 under 정보통신망법 before it may be pushed, and
-- there is no such consent in the app. Writing one here is an owner's act
-- from the dashboard; no client can.
--
-- `audience` is who reads it: the parent's phone, the child's, or both. The
-- senior's card shows `body` under a fixed 잘보이네에서 알려 드려요, so keep
-- it to a few short lines - the card does not scroll.
--
-- `below_build`, when set, shows the notice only to builds lower than it:
-- 업데이트해 주세요 is said to the phones that have not, and to nobody else.

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  audience text not null check (audience in ('senior', 'guardian', 'both')),
  title text not null,
  body text not null,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  below_build int check (below_build is null or below_build > 0),
  created_at timestamptz not null default now()
);

create index if not exists announcements_live_idx
  on public.announcements (starts_at desc);

alter table public.announcements enable row level security;

-- Readable while it is running, by anybody: a parent's phone may not have a
-- session yet, and nothing in a notice is about a person.
drop policy if exists announcements_read on public.announcements;
create policy announcements_read on public.announcements
  for select to anon, authenticated
  using (starts_at <= now() and (ends_at is null or ends_at > now()));

revoke insert, update, delete on public.announcements from anon, authenticated;
