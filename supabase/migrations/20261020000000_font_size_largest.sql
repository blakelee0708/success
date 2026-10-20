-- 제일 크게 — a fourth text size.
--
-- The column's check constraint is the reason this migration exists at all:
-- the senior's phone can save a new size locally, but syncing it would be
-- rejected by the server, and the failure would land on the one person in the
-- system who cannot do anything about it. Widen the server first.
alter table public.senior_profiles
  drop constraint if exists senior_profiles_font_size_check;

alter table public.senior_profiles
  add constraint senior_profiles_font_size_check
  check (font_size in ('normal', 'large', 'extraLarge', 'largest'));
