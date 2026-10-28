-- 가족, 소리, 인터넷, 긴급 구조 요청 can be taken off the home screen.
--
-- They were the only four buttons on a senior's phone that nobody could
-- remove - not the senior, not their family - on the half of the product
-- whose whole job is that the family can arrange that screen. The case is a
-- real one and it came from a parent: a senior who finds a large red
-- emergency bar alarming, or who keeps pressing it by accident, asks their
-- child to take it away.
--
-- **It is a column on the profile rather than rows in `home_apps`**, because
-- what is being recorded is the *absence* of a button and `home_apps` holds
-- rows. Absence there has always meant *nobody has edited this one yet, draw
-- the default* - which is what still draws all four for a family that has
-- never touched them. Reading absence as removal would have emptied every
-- one of those screens the moment this shipped, and nothing in the rows
-- tells the two apart.
--
-- The names are `AppCategory`'s, so the app writes what it reads. A value
-- this version does not know is ignored rather than rejected: a newer phone
-- in the family must not stop an older one from syncing at all.

alter table public.senior_profiles
  add column if not exists removed_slots text[] not null default '{}';

comment on column public.senior_profiles.removed_slots is
  '어떤 자리 버튼을 홈 화면에서 뺐는지. AppCategory 이름.';
