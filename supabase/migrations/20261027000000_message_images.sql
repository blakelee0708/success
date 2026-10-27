-- 가족 메시지의 사진.
--
-- The table half of this has existed since Phase 7: `messages.image_url`, a
-- quota that counts texts and images separately, and `send_family_message`
-- refusing an eleventh image on the free plan. What was missing is the place
-- the file itself goes, which is why 이미지 전송 was the one thing
-- `04_SCREEN_SPEC` asks for that the message tab did not do.
--
-- Three decisions here are load-bearing.
--
--  * **The bucket is private.** A public bucket would mean every photo a
--    family sends is readable by anyone who guesses the URL, forever, with
--    no way to take it back. These are pictures of somebody's parent. The
--    app reads them through signed URLs instead.
--  * **The path carries the profile id, and the policies read it.** A file
--    lives at `<senior_profile_id>/<name>`, so the same `guardian_manages`
--    and `device_owns` that guard the `messages` rows guard the files, with
--    no second copy of the rule to drift.
--  * **A removed guardian loses the photos too.** Both helpers already
--    return false once a link is no longer active, so this comes for free -
--    and it is the same thing `request_phone_ring` refuses for the same
--    reason.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'message-images',
  'message-images',
  false,
  -- 8 MB. A phone camera JPEG is well under this; the limit is here so a
  -- mistake cannot fill the project's storage with one upload.
  8388608,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic']
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- The first path segment is the senior profile the photo belongs to.
create or replace function public.message_image_profile(object_name text)
returns uuid
language sql
immutable
as $$
  select nullif(split_part(object_name, '/', 1), '')::uuid
$$;

drop policy if exists message_images_read on storage.objects;
create policy message_images_read on storage.objects
  for select
  using (
    bucket_id = 'message-images'
    and (
      public.guardian_manages(public.message_image_profile(name))
      or public.device_owns(public.message_image_profile(name))
    )
  );

drop policy if exists message_images_write on storage.objects;
create policy message_images_write on storage.objects
  for insert
  with check (
    bucket_id = 'message-images'
    and (
      public.guardian_manages(public.message_image_profile(name))
      or public.device_owns(public.message_image_profile(name))
    )
  );

-- Deliberately no update and no delete.
--
-- Nothing in the app edits or removes a sent photo, and a message that has
-- been read cannot be unsent - the conversation is a record of what a family
-- said to each other. Leaving the verbs out means a stolen token cannot do
-- either either.
