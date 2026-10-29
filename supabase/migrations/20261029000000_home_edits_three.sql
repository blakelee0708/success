-- 자녀 폰에서 홈 화면 정리, 평생 2회에서 **3회**로.
--
-- The owner's call on 2026-10-29. Two is a tight first impression: a guardian
-- arranges the home screen, their parent asks for one thing changed, and the
-- allowance is gone before anybody has decided whether the app is any good.
--
-- The rule it sits under is unchanged and is the one to check any change
-- against: **the senior's own phone is never limited.** 앱 설정하기 is two
-- presses from their home screen and saves without counting, whatever the
-- guardian has spent.
create or replace function public.guardian_home_edits_free()
returns int
language sql
immutable
as $$ select 3 $$;
