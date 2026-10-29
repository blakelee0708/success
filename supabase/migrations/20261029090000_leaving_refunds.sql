-- Two refund rules the leaving migration got wrong, found by review
-- before any money could move (there is no Play Billing yet).
--
-- 1. `settle_care_after_leaving` refunded every 'canceled' row, including
--    one whose month had already run out.
-- 2. `remove_guardian_link` refunded only when no active link was left, so
--    a child cut while a sibling stayed lost 안심 케어 and kept paying.

create or replace function public.settle_care_after_leaving(
  p_senior_profile_id uuid,
  p_guardian_account_id uuid,
  p_refund boolean
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  -- Only this guardian's own subscription. A sibling's card is theirs.
  update public.subscriptions
     set status = case when p_refund then 'refunded' else 'canceled' end,
         canceled_at = coalesce(canceled_at, now()),
         refunded_at = case when p_refund then now() else refunded_at end,
         updated_at = now()
   where senior_profile_id = p_senior_profile_id
     and guardian_account_id = p_guardian_account_id
     and plan = 'care'
     and (
       status in ('active', 'pending_senior_consent')
       -- A cancelled month refunds only while it still has days in it. One
       -- that ran out was delivered in full; refunding it on a later leave
       -- would pay money back for a month already used.
       or (status = 'canceled' and current_period_end > now())
     );

  -- An unanswered consent question is withdrawn rather than left standing on
  -- the parent's home screen, pointing at a family that is no longer there.
  if not exists (
    select 1 from public.subscriptions
     where senior_profile_id = p_senior_profile_id
       and plan = 'care'
       and status in ('active', 'pending_senior_consent')
  ) and exists (
    select 1 from public.senior_profiles
     where id = p_senior_profile_id
       and paid_consent_status = 'pending'
  ) then
    update public.senior_profiles
       set paid_consent_status = 'none'
     where id = p_senior_profile_id;
  end if;
end;
$$;
revoke execute on function
  public.settle_care_after_leaving(uuid, uuid, boolean) from anon, authenticated;

create or replace function public.remove_guardian_link(
  p_guardian_account_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  profile_id uuid;
  senior_label text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  -- **Only the phone the link is about may cut it.** Scoped through the
  -- active device rather than through the profile, which is the same check
  -- `answer_guardian_link` makes: a guardian who could remove a sibling
  -- would be deciding for their parent, and this is the one decision that is
  -- hers.
  select d.senior_profile_id into profile_id
    from public.senior_devices d
   where d.auth_user_id = auth.uid()
     and d.is_active;

  if profile_id is null then
    raise exception 'this phone is not an active senior device';
  end if;

  update public.guardian_senior_links
     set status = 'removed', updated_at = now()
   where senior_profile_id = profile_id
     and guardian_account_id = p_guardian_account_id
     and status in ('active', 'pending');

  if not found then
    -- Not an error. Pressing 끊기 twice, or on a row a sibling's handover
    -- already changed, is somebody getting what they asked for.
    return;
  end if;

  select display_name into senior_label
    from public.senior_profiles where id = profile_id;

  -- **One line, and no reason.** Why a mother cut the link is her business,
  -- and an app guessing at it in writing would be worse than silence. But
  -- silence alone leaves the child one day finding nothing on their screen
  -- and no idea why, so something has to be said.
  insert into public.guardian_notices
    (guardian_account_id, type, senior_name, body)
  values (
    p_guardian_account_id, 'link_removed', senior_label,
    '연결이 끊어졌습니다.'
  );

  -- **Always, for the child who was cut.** It used to wait until no active
  -- link was left, on the grounds that a sibling who stayed did nothing
  -- wrong - but this only ever touches the removed child's own row, and
  -- `care_is_active` needs the buyer's own link. So with a sibling still
  -- there the removed child lost the feature and kept paying for it, which
  -- is the one outcome the rule 어르신이 끊으면 돈은 돌아간다 exists to stop.
  -- The sibling's own subscription is theirs and is not touched.
  perform public.settle_care_after_leaving(
    profile_id, p_guardian_account_id, true
  );
end;
$$;
grant execute on function public.remove_guardian_link(uuid) to authenticated;
