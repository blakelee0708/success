-- 폰 미사용 알림 is out of the product.
--
-- Decided 2026-10-29, after reading Play's stalkerware policy rather than
-- recalling it. The rule bans collecting and transmitting personal or
-- sensitive data to monitor another person, and names two exceptions:
-- 부모가 자녀를, and 기업 관리자가 직원을. This app is 자녀 → 부모, which is
-- one adult watching another, and the policy is explicit that the ban holds
-- **even where the watched person has agreed**:
--
--   배우자를 포함한 다른 성인을 추적해서는 안 됩니다.
--   이는 허락을 받은 경우에도 마찬가지입니다.
--
-- Everything else 안심 케어 sends is a value Android hands over with no
-- permission: a battery percentage, a ringer mode, the moment the phone was
-- last unlocked. `이틀 넘게 안 켜셨는지` is different in kind. It is a
-- pattern of use, watched across days, and of the six things in the tier it
-- is the one a reviewer would stop on.
--
-- **The cron job is unscheduled and the function is left in place.** The
-- rows it would have written are gone, so nothing reads it; dropping the
-- function would also drop `unused_notified_for` and the `phone_unused`
-- value from the `alerts` type constraint, and a constraint that has held a
-- value since Phase 6 is not worth narrowing for a feature that may come
-- back if the policy is read differently. The schedule is the thing that
-- makes it run, and that is what is removed.

select cron.unschedule('check-unused-phones')
 where exists (
   select 1 from cron.job where jobname = 'check-unused-phones'
 );

comment on function public.check_unused_phones(int) is
  '폰 미사용 알림 - out of the product since 2026-10-29. Not scheduled and '
  'not callable by a client. Kept so the column and the alert type it uses '
  'do not have to be narrowed. See this migration for why.';
