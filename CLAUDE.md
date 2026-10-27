# 잘보이네 — Flutter senior launcher

## Environment

Remote sessions have no Flutter SDK. `.claude/hooks/session-start.sh` installs
the revision pinned in `.metadata` (currently 3.38.9 / Dart 3.10.8) and puts it
on `PATH`. It runs automatically at session start — roughly 1m30s cold, and it
skips the download when the SDK is already correct.

If `flutter` is somehow missing, run the hook by hand:

```bash
CLAUDE_CODE_REMOTE=true ./.claude/hooks/session-start.sh
```

Commands:

```bash
flutter analyze          # currently clean
flutter test             # currently 266 tests, all passing
```

The SDK unpacks as a root-owned git checkout, so `git config --global --add
safe.directory /opt/flutter` is required or every flutter command aborts on
dubious ownership. The hook already does this.

## Skills

The Superpowers skills library is vendored at `.claude/skills/` because
`/plugin install` cannot be run from a remote session. The plan documents in
`docs/superpowers/plans/` name `subagent-driven-development` and
`executing-plans` as the required sub-skills for implementing them
task-by-task.

## Where the project stands

`docs/claude-code/07_PHASE_PLAN_FOR_CLAUDE_CODE.md` is the phase plan, and it
asks that each phase be implemented, reviewed, and tested on its own rather
than all at once.

- **Phase 0 (project setup)** — done. Riverpod, go_router, feature-first layout.
- **Phase 1 (senior launcher)** — done, then reworked: the role-split screen was
  replaced by the splash in
  `docs/superpowers/specs/2026-07-29-splash-and-guardian-entry-design.md`. The
  phone inside the illustration is the start control; there is no 시작하기
  button, and removing it again would undo a deliberate decision.
- **Phase 2 (local settings)** — done. Settings persist through
  `SharedPreferencesSeniorSettingsRepository`; 설정 → 앱 설정하기 reorders,
  renames, recolours and removes buttons, 글씨 크기 조절하기 picks the text size.
  Both homes draw from the saved list rather than the constant defaults.
- **Phase 3 (guardian dashboard)** — done. Built as mocked UI, then wired to
  the live data after Phase 4: 홈 화면 reads and writes the parent's `home_apps`
  rows, 홈 shows the real profile, the real active device and the settings the
  parent chose, and the parent switcher is real when more than one is linked.
  The mocked battery / ringer / network readings were **removed** rather than
  kept — they arrive with the Phase 6 background sync, and a plausible
  `배터리 72%` on a dashboard whose job is to reassure is worse than an empty
  state that says so. 돌봄 and the 4-digit code card are still Phase 5/6 shapes
  and are labelled 준비 중.
- **Phase 4 (Supabase)** — done. Schema, RLS and RPCs are applied to the live
  project; guardian email sign-in, senior profile creation, device registration
  and two-way home-app sync all work. See `## Supabase` below.
- **Launcher registration and app opening** — added after Phase 4, outside the
  numbered plan, which never assigned them a phase. The home buttons now open
  real apps and the app can become the phone's home screen. Native, and
  unverified from this environment — see `## The launcher half is native` below.
- **Phase 5 (pairing and recovery)** — done. Both paths from the plan, recovery,
  the free family invite and the primary-guardian handover, all applied to the
  live project and verified by `tool/verify_supabase_phase5.py`. The Phase 4
  `customer_code` path is superseded; the code direction is now the plan's —
  the parent's phone **shows** a 4-digit code and the guardian types it.
- **Phase 6 (paid features)** — done as far as it can be here. The subscription
  model, the consent flow, the refund-on-refusal state and the family-plan gate
  are applied to the live project and verified by
  `tool/verify_supabase_phase6.py`. The four capabilities themselves are
  **interfaces only**, which is what the phase plan asks for — see
  `## 가족 메시지 and its allowance

`supabase/migrations/20260801000000_phase7_messages.sql`. The PRD prices it at
월 50회 / 이미지 10개 free, unlimited with 안심 케어, and two decisions in the
counting are load-bearing:

- **The quota counts guardian messages only.** A senior replying to their child
  is never blocked, whatever the counter says — a launcher for an elderly
  person that refuses to let them answer their daughter because a monthly
  allowance ran out is selling the wrong thing, and the allowance exists to
  price the guardian's use.
- **The allowance is the family's, not each guardian's.** Two siblings share
  one, because the parent is the one reading them.

`ConversationView` draws both ends. One widget on purpose: it is the same
conversation, and two copies would drift. `large` is what differs — the
senior's is scaled up and hides the counter, because a tally of how many times
their family may write to them would be unkind and is not about them anyway.

On the senior's home, `04_SCREEN_SPEC`'s 가족 연결 또는 자녀 이름 버튼 is now
literal: before a family is attached it connects one, and afterwards it opens
the conversation.

## The paid features are interfaces` below.

All six numbered phases are now done, and what is left is not a phase. This
list was stale — it still named the `applicationId`, 더 보기, the 메시지 탭
and a run on a real phone, all four of which have since happened. As of
2026-10-27:

- **Play 출시**: an upload key (the APK is still debug-signed), a Play Console
  account, a privacy-policy URL, and Play Billing. Until Billing exists the
  buy button makes a subscription with no money.
- **Guardian sign-in**: Google and Kakao OAuth clients, and the project's mail
  settings — see `### Email sign-up cannot work` below. Both are console work
  only the owner can do.
- **소리 울리기**: the background wake-up and the guardian's button. Both are
  blocked on things outside this environment; see `## Firebase`.
- **메시지**: image sending, which needs a picker and file storage.
- **설정**: 진동/벨소리 전환, the one row still in 아직 준비 중.
- **The paid watchers**: 5분 주기 갱신 and anything else `CareReadiness
  .planned` still covers.

Route `/` is a launch gate, not a screen: a senior with a saved screen mode
lands on their home instead of the splash, because this app becomes the phone's
launcher and pressing Home must not show a splash. The guardian half now reads
the session Supabase restored from disk.

## Where the dashboard departs from the uploaded design

The design carried four things the project docs rule out, and the docs won.
Restoring any of them means changing the PRD first, not just the screen:

- 약 알림 / 복약 기록 — PRD Out Of MVP.
- 보이스피싱 의심 전화 — **removed outright on 2026-10-20.** The PRD already
  excluded call-content analysis, so it had been scoped to numbers absent
  from the contact list; that still needs `READ_CALL_LOG`, which Play grants
  to default phone and messaging apps, and this is a launcher. Keeping it
  meant selling a feature whose permission was unlikely to be granted. The
  docs under `docs/claude-code/` still list it — changing them is a PRD
  decision, not a code one.
- 실시간 위치 추적 — `06_PERMISSION_AND_POLICY` forbids the phrasing, since how
  it is described is what the senior consents to.
- 여러 보호자 초대 — free in the PRD, paid in the design.

메시지 탭 is now built. An earlier note here said it had no design — that was
wrong: `04_SCREEN_SPEC` specifies it (카톡 스타일 대화, 텍스트 전송, 이미지 전송,
무료 잔여 횟수 표시, 유료 전환 안내) and `02_MVP_SCOPE` puts it in the MVP.
Everything but **image sending** is there; a picture needs an image picker and
file storage, neither of which can be built or verified here, so it is absent
rather than present-and-broken.

## Layout under large text

Raising the text size is the point of this app, so anything that only fits at
the default size is a bug. The app tile, the SOS pill and the pairing-code row
all scale down to fit rather than overflow — check new screens at 아주 크게.

`HomeBody` sizes the grid rows from the space actually left rather than
leaving the tiles square. Neither home scrolls, and a `GridView` is a
scrollable: asked for more height than it has, it clips the bottom row in
silence instead of painting an overflow stripe. `home_fits_test.dart` measures
every tile against the grid on **both** screens at all three text sizes,
because nothing throws when this breaks — and it does catch it: replacing the
clamp with the unclamped square height fails all eight cases.

`flutter test test/screenshots_test.dart` writes each screen to
`build/screenshots/`. There is no display here and no way to build an APK
(see below), so those PNGs are how layout gets reviewed.

**Pumping the app twice in one test needs `pumpApp`, not `pumpWidget`.** A
second `App` pumped straight over the first only *updates* the existing
elements, so the ProviderScope keeps its container and the router keeps its
stack — new overrides and new prefs are read by nobody and the test quietly
re-examines the first app. `pumpApp` tears the old tree down first. Until it
did, every 아주 크게 screenshot was byte-identical to its normal-size twin, and
the clipped grid above had been sitting in plain sight for weeks.

## The look: white ground, clay buttons

Settled in the 2026-10-20 review, which threw out the cream ground and the
flat tiles. Everything a senior can press is drawn as a solid object by
`lib/core/widgets/clay_pad.dart`, and that one widget is what keeps the screen
coherent — the tiles, 가족, 더 보기, SOS, the clock card and the avatar are all
lit from the same direction.

Three parts make the object, and dropping any one leaves a flat rectangle: the
**wall** (a shadow with no blur, offset straight down, always the darkest of
the four colours), the **face gradient** (light → base → deep), and the
**sheen**. Flutter has no inset shadow, so the sheen is a gradient painted over
the face and *under* the content; as a `foregroundDecoration` it would wash out
the icon and the label too. `sheen` scales it down for the near-white card,
where full strength reads as grime.

Two rules about colour, both found by `clay_palette_test.dart` rather than by a
phone:

- **No blue or teal on the senior's screens.** Short-wavelength colours are the
  first an ageing eye loses. 가족 is amber and 더 보기 brown for that reason.
  The 문자 tile keeps its blue only because it was there before the rule and
  removing it was not asked for.
- **A face carries lettering it can actually hold.** White needs 3:1 against
  the face; yellow cannot manage it, so the yellow tile and the amber 가족
  button are lettered in ink. `AppCategory.letteringColor` decides.
- **The ink is a step back from black, and warm.** `seniorInk` was `#1B1A18`
  — 17.4:1 on the white ground, the highest value in the app — and at this
  size that is not free: the bright ground spreads into the strokes and large
  glyphs read as though they are bleeding. `#352F29` is 13.2:1, on the same
  warm side as the terracotta and the amber. It is **not** the `#3A2410` that
  came out of the palette; that was plainly brown, this is ink with warmth in
  it. The test brackets it from both ends, because past about 12:1 it stops
  looking solid and starts looking faded — the opposite failure. Changing
  this one constant changes every heading, the 카카오톡 tile's lettering and
  the 가족 button's, because they all read it.

`ColorScheme.fromSeed` does not keep its seed — it generates a tonal palette,
and the terracotta came back as a muddy brown on every filled button. Both
themes now set `primary` and `onPrimary` outright.

## The band's type was a fiction for one commit

Raised on 2026-10-27 after it was called too small on a phone — and the first
attempt **changed nothing**, because the sizes were not what was wrong.

`오후 7:14` was breaking after 오후. Two lines tall, the band's content came
to 228px against a 160px budget, and the `FittedBox` answered by scaling the
whole band to **0.79** — so the code said 54px and the phone drew 43. Raising
the numbers could not help: every increase was absorbed by the same scaling,
which is why the first fix looked identical on the phone. `가족을 연결해
보세요` was wrapping too, for 17px where the code said 22.

The fix is `maxLines: 1, softWrap: false` on both, not more height. With them
one line each the content is 166px, the band draws 1:1 at 212, and the clock
renders at **63px against 43 before**. The date's own note three paragraphs
down had already recorded that Korean glyphs are about as wide as the type
size and a line has to be measured — it just never reached the clock beside
it.

**This is the third fault this `FittedBox` has hidden in this file**, and the
first to survive a fix. `home_fits_test.dart` now asks the box what scale it
used and fails below 1.0 at the default size, which is the only question that
catches it: nothing throws, nothing overflows, and the screenshots look
plausible at any scale.

## The band across the top of both home screens

`HomeStrip`. It exists because square tiles could not fill the screen: stretched
to fit they became 169x250 rectangles, and left square they left 211px of
nothing at the bottom. The slack became one wide thing worth looking at — the
clock, and underneath it whoever is looking after this phone.

It is on 자세한 화면 too since the 2026-10-20 review, at the same 192px.
`HomeBody.preferredStrip` is that height, and it is laid out **first**: the
grid takes what is left, not the other way round. Reversed — which is how it
shipped for one commit — 자세한 화면's eight rows pushed the band to its 110px
floor, and because the band is wrapped in a `FittedBox` nothing overflowed and
nothing threw: it just scaled the whole band to 0.58 and drew the clock at
29px while the easy screen's stayed 50. The band only starts giving height
back when the rows could not otherwise hold a 44px icon over a label.

`home_fits_test.dart` measures the laid-out band and the rendered clock on both
screens for exactly that reason. It is the one check a `FittedBox` cannot make
for you.

The date sits *above* the clock. Side by side they ran to 328px inside a 310px
card and the date was pushed out of its own box; Korean glyphs are about as
wide as the type size, so a line of them has to be measured, not eyeballed.

This is now the 가족 연결 또는 자녀 이름 slot `04_SCREEN_SPEC` asks for: the
band shows the family's newest message and opens the conversation, so the
button beside it is left with the connection itself and is named 가족 연결
until there is one.

## 자세한 화면 lost its tab bar

It was a scrolling grid under a Material `NavigationBar` until the 2026-10-20
review. Neither problem was colour — its tiles were already the shared
`AppTile`:

- The tab bar was the one part of the screen the text size never reached, on
  an app whose whole promise is that the text gets bigger.
- One home scrolled and the other did not, which is most of why they read as
  two different apps.

It is now the band, eight cells (2x4, rows 108px), and 긴급 구조 요청 beside
가족 where the tabs were. Three decisions in it are load-bearing:

- **설정 is a tile, and it had to go somewhere.** That list is the only way
  into 글씨 크기 조절하기 anywhere in the app — 더 보기 on the easy screen is
  still a "곧 추가할 수 있어요" placeholder — so dropping the tab bar without
  rehoming it would have removed the setting the app is sold on. It is brown
  rather than a category colour because it stands next to 전화 and must not be
  taken for an app, and it lives at `Routes.seniorSettings` now.
- **긴급 구조 요청 gets 203 of the 354px, not 177.** Split evenly its label
  scales to 17px, smaller than the 26px tile labels above it, and SOS ending
  up the smallest lettering on the screen is wrong. Stacking it full-width
  under 가족 instead — the easy screen's arrangement — costs the tile rows
  30px each and the icon no longer fits.
- **Empty slots stay hollow, and there are one or two of them, never six.**
  Padding the grid out to eight whatever the senior kept would fill most of
  their home with 추가하기, which is a reproach rather than an invitation. The
  slot's muted-clay beige is gone with the rest of the beige;
  `clay_palette_test.dart` now asserts its three colours are neutral.

`nowProvider` is where the time comes from, so tests and the review
screenshots can pin it. A screenshot whose clock moves every run is a
screenshot nobody can diff.

## 가족 연결 does not ask the senior to choose

The screen used to put 번호 보여주기 and 번호 입력하기 side by side at the same
size, under a line asking which one they wanted. They are not two equal
choices:

- **번호 보여주기** is the path anyone can take alone, and it is `경로 B` —
  the required fallback for when the Play install referrer did not survive.
- **번호 입력하기** cannot be done at all without a number already in hand. To
  a senior holding no number it is not an option, it is a dead end.

So the first is a 140px red pad reading **번호 보여주기 / 여기를 누르세요**, and
the second is a quieter question below a rule — `자녀분이 먼저 번호를 알려
주셨나요?`, which only the few it applies to will answer. A test asserts the
first is more than half again the height of the second.

**It is 영상 보기's red (`#DF4F28`) with white lettering**, not the amber 가족
wears elsewhere. Two measurements decided that: the amber sits at hue 36°,
**one degree** off the 카카오톡 tile, and its value is 95% — the highest in the
whole palette, which is what makes it read as washed out beside tiles sitting
at 87–88%. White on this red measures 3.97:1, clear of the 3.0 floor for
lettering this size.

The red is 6° from the SOS pill. That is close, and the only reason it is
acceptable is that 영상 보기 already sits in the same red on the same home
screen as SOS — this adds no distinction the app did not already ask a senior
to make. It is still worth keeping the shape different: SOS is a wide bar and
this is a tall pad with an icon over two lines.

The 가족 button on both home screens is **still the old amber**. Changing it is
a separate decision and it was not made, so the two do not match yet.

## The home-app question moved into onboarding, and off the home screen

It used to live on the home screen as a card over the tiles, not dismissible,
and at 제일 크게 it asked for more height than the phone had. Nothing
overflowed — every tile is a `FittedBox` — so the tiles simply shrank, to
**12px**, with their labels smaller than the 가족 pill underneath. The same
silent failure the band had, one screen along.

It is asked **once, at the end of onboarding**, right after the screen is
chosen; `06_PERMISSION_AND_POLICY` allows exactly this one request there.
Having asked, the home screen does not ask again — the card is gone from both
homes, and with it the 26% cap and the band-standing-down it had forced.

**The answer is read, never awaited.** `ScreenModeChoiceScreen.build` watches
`isDefaultHomeProvider`, so the platform is asked the moment the screen opens
and `_choose` reads the value. Awaiting the channel in the tap handler
strands the senior on the screen they just answered whenever it does not
reply — `flutter test` is such a platform, and so is a phone whose launcher
service is wedged. Seven tests caught exactly that.

The way back is **설정 → 첫 화면으로 정하기**: one row among the others, and
only where the phone says this app is not its home app. Tapping it opens the
phone's own chooser directly. There is no screen in between, and no card —
both existed and both were wrong. The card was an announcement where a
setting belonged; the screen said 첫 화면으로 정하기 three times, as its
title, as its heading and on its only button, before doing what the row now
does on tap. When the phone refuses to open its chooser — Samsung keeps its
own launcher set, so pressing Home never offers a choice — a dialog gives the
path through the phone's settings.

**Almost nobody sees any of it.** The row exists only after a senior answers
나중에 during onboarding. It showed up in every review screenshot because
those pump `FakeAppLauncher(defaultHome: false)`, which is a phone that was
never set up.

That made a second gap visible and worth closing: **정말 쉬운 화면 had no
route to 설정 at all**, so a senior on the easy screen could not change their
text size either — the setting the app is sold on. **더 보기 goes straight
there** now. The screen that used to sit in between held one button and a
line saying apps cannot be added yet, which is a screen that exists to be
passed through.

## The two consent cards cover the home

안심 케어 동의 and the primary-guardian handover are the two things only the
senior can answer, on their own phone, so neither can move to another screen.
They used to sit above the tiles and they did what the 첫 화면 card did: at
제일 크게 they asked for more height than the phone had, and because every
tile is a `FittedBox` nothing overflowed — the tiles came out **24px** tall,
wide bars with no icon and no label.

`SeniorNoticeLayer` draws whichever one is pending over the whole home
instead, one at a time, care first because money is already held against it.
That costs a senior their tiles until they answer, and both are answered by
pressing one of two buttons; a grid they cannot read costs them the tiles
anyway.

**Every line on both cards is short enough to be a whole line.** Written long
and left to wrap, `지금 쓰시는 기능은` broke after 기능 and left 은 alone on a
line of its own — on the one screen in the app where a senior is being asked
to agree to something. Korean glyphs are about as wide as the type size, so
a line has to be counted rather than eyeballed: at 20px in a 318px card that
is sixteen glyphs. The copy is cut to fit that, not wrapped to it.

Now that they have the screen, they use it: headline 27px, the three things
being consented to at 20px bold, the two buttons 72px tall.

`home_fits_test.dart` now covers these two as well. It only ever covered the
첫 화면 card, which is why they kept the fault after that one was fixed — the
check was written around the card that happened to be in front of me.

## Adding a button asks what kind it is

Both ways in — 앱 설정하기 on the senior's phone and 홈 화면 on the guardian's —
used to add every new button as `AppCategory.message`. A button called 딸 came
out blue, wore the 문자 icon and opened the messaging app, which is the one
thing on that screen the senior cannot fix themselves.

`askForCategory` asks first, and the name dialog then opens pre-filled with
`AppCategory.defaultLabel` so the common case is one tap and 저장. The options
are drawn as the tiles themselves rather than as a list of names: what is being
picked is the thing about to appear on the home screen, and on the guardian's
half that is the one place the senior's clay belongs — it is a depiction of
their mother's phone, not chrome for this one.

## 설정 is six rows of three kinds

Six identical Material cards in the warm brown ink that came out of the
palette, which made this look like a different app from the home it opens
off. They are the same clay object the home screen is made of now, and
grouped, because the six are not six of a kind: **이 화면** (앱 설정하기, 글씨
크기, and 첫 화면으로 정하기 when it applies), **가족** (메시지, 연결 설정) and
**아직 준비 중** (진동/벨소리, 사용하지 않기).

**잘보이네 사용하지 않기 left that last group and joined the first.** It sat
in 아직 준비 중 with no `onTap`, which was honest and useless: a senior who
wants their old home screen back had no way to say so, on the one app that
took the home screen over. Android gives an app **no way to unset itself** as
the home app — there is no "clear default" to call — so the phone's own
chooser is the only route, and it is the same screen 첫 화면으로 정하기 opens.
That needed no new Kotlin: `openHomeSettings` asks for the HOME *role* only
when this app does not hold it, so holding it, the call falls through to
`ACTION_HOME_SETTINGS`, which is the picker.

The two live side by side in **이 화면** because they are one setting seen
from two sides, and exactly one of them is ever shown — `isDefaultHome`
decides which. It asks first, because it changes what pressing Home does on
someone's phone, and the dialog says **nothing is lost**: the buttons, the
text size and the family connection all stay, and a senior left to guess that
reads a reversible choice as a final one. The same manual-path dialog covers
a phone that refuses to open its chooser.

진동/벨소리 전환 is what is left in 아직 준비 중. It has no `onTap` at all, so
it cannot be pressed — the way the disabled SOS tile says the same thing. It
fades to 0.6 rather than 0.5: `Opacity` fades lettering with the face, and
`곧 쓰실 수 있어요` is the only thing on that row worth reading. 가족 메시지 is
lettered in ink because its amber cannot hold white, the same rule as
everywhere else.

## 긴급 연락 is three colours now, and the sizes go to four

**The three tiles were all the same red**, which left the digits as the only
thing telling 119 from 112 — on the screen where getting it right matters
most and the reader is least composed. They are red, purple and yellow now,
and the colour carries as far across a room as the digits do. Yellow cannot
hold white lettering (2.38:1), so 보호자 is written in ink, exactly as the
카카오톡 tile is.

112's purple is the first short-wavelength colour chosen *deliberately* for a
senior screen. The rule it bends is real, and so is the reason: telling two
emergency numbers apart beats absolute visibility when both labels are 48px
digits. 문자's blue was already there, so it is not the first blue a senior
meets.

The disabled 보호자 tile fades to **0.75, not 0.5**. `Opacity` fades the whole
subtree, lettering included: at 0.5 the line explaining why the tile cannot
be used measured 2.99:1 against its own face, and that line is the only thing
on the tile worth reading.

**`FontSize` has a fourth step, `largest` (1.7).** The server had
`check (font_size in ('normal','large','extraLarge'))`, so adding it in Dart
alone would have let the senior pick a size their phone saves and the sync
rejects — a failure landing on the one person in the system who can do
nothing about it. `20261020000000_font_size_largest.sql` widens it and is
applied to the live project. `home_fits_test.dart` walks `FontSize.values`,
so the new size was covered the moment it existed.

## The guardian app is a different design, on purpose

Settled 2026-10-20, from a pastel reference the owner brought. The form came
across — a gradient ground, a hero card with translucent discs, a 2x2 grid of
actions, big radii and soft shadows. The palette did not.

`04_SCREEN_SPEC` gives this persona 파란 포인트, and `guardianPrimary` was
already `#0B5FD9`, so **the blue is the documented design and the terracotta
suggested here first was the deviation**. Three gradients carry it:

| | |
|---|---|
| ground | `#EEF2FF → #F7F9FF → #FFFFFF` |
| card | `#FFFFFF → #F4F7FE` |
| hero | `#0B4FC4 → #1B5CD8 → #2E6FE8` |

**The hero is a saturated blue, not the reference's pastel, and that is the
whole point.** Same hue; the pastel is that hue mixed with white. Sampled out
of the reference PNG, its light stop is `#B5CBF6` and the white label on it
measures **1.64:1** — a third of what 12.5px needs. The chosen stops measure
7.17 and 4.61, so small white text is allowed on the card at all.
`guardian_palette_test.dart` measures **every stop**, because checking only
the dark end of a gradient is exactly how that reference shipped.

Captions are `#5F6B7A`, not the `#8B95A1` this family of greys usually puts
there: that measures 3.04 against white, under the bar before the card's own
gradient is counted.

**None of the senior rules reach this half.** No clay, no 26px lettering, no
ban on blue, and scrolling is right rather than forbidden — all of those
follow from an ageing eye, and the son or daughter reading this screen does
not have one. What ties the two halves together is the typeface and nothing
else.

Two things the home tab will not do:

- **The hero never reassures on no evidence.** It shows how long ago the
  parent's phone was last used, or it says there is none — `아직 / 연결되기
  전이에요`. The server knows a phone was unlocked; it does not know the parent
  is well. This is the most comforting-looking object on the screen, which is
  why it is the one that must not round a missing check-in up — nor an old
  one, which it did until 안부 신호 existed. Same rule that took the mocked
  `배터리 72%` off this tab. Every line it says comes from `SeniorPresence`.
- **Every number on it is read, not written.** The buttons on the action card
  come from the parent's real `home_apps`, the allowance from the real quota,
  `마지막 대화 4일 전` from the real conversation. A card that says the same
  thing every day is furniture.

**Every tab starts at the same height**: `GuardianHeading.crown` (44px) above
the headline, then `GuardianHeading.gap` (22px) under it. The crown is on top
of whatever `SafeArea` already took for the status bar — the headline is the
first thing on the screen and needs room to be that, rather than looking
wedged under the clock. It was 20 on one tab and 26 on the other, and both
were too little; a test now asserts the two tabs agree to within a pixel. 홈 draws it through `_TabScaffold`; 홈 화면 cannot, because its list is a
`ReorderableListView`, so it passes the same heading as that list's `header`.
`버튼 추가하기` is the list's `footer` rather than a bar pinned to the bottom of
the screen — pinned, it left a field of nothing between the last row and the
button and said nothing about where a new button would land. In the list it is
simply the next thing after the last button, and adding one pushes it down.
Both are tested: the button has to sit below the last row and move when a row
is added, and the heading has to scroll out of view.

**로그아웃 is on 가족, and it had been missing since Phase 4.**
`04_SCREEN_SPEC` puts it in the guardian's 설정 탭; this app folded that tab
into 가족 and the row went missing in the fold, so `signOut()` sat on the
controller with nothing on any screen calling it — a guardian signed in on a
borrowed phone had no way off it. It is the last thing on the tab and a text
button rather than a filled one, because nobody opens this app in order to
leave it. It asks first, and the dialog says what signing out does **not** do:
부모님 폰은 그대로입니다 — someone who reads 로그아웃 as 연결 끊기 will never
press it, and someone who presses it expecting that is worse off still.
Afterwards it goes to `/` rather than staying put; nothing redirects that
route on its own, so the dashboard would have gone on showing the last
parent's name until the app was restarted.

**The sign-in screen may not promise what the app cannot do.** It is the
first screen a guardian reads and the only one that makes promises, so it is
the worst place to make one that is not kept. It offered 배터리 · 소리 ·
인터넷 "한눈에" while the dashboard says 준비 중 for all three, and 사진,
which the message tab cannot send — the readings arrive with the Phase 6
background sync, which is an interface with no implementation, and an image
needs a picker and file storage that do not exist. Both are gone, and
`guardian_start_test.dart` asserts 배터리, 인터넷 and 사진 appear nowhere on
it. Same rule that took the mocked `배터리 72%` off the dashboard, one screen
earlier.

The parts are shared, in `presentation/widgets/guardian_surfaces.dart`:
`GuardianGround`, `GuardianCard`, `GuardianActionCard`, `GuardianFact`,
`GuardianPrimaryButton`, `GuardianHeading`, `GuardianSwitcher` and the
`guardianField` decoration. 홈, 홈 화면, 가족 and the sign-in screen are all
built from them.

Two Material controls went the way of the `NavigationBar`, for the same
reason — each brings a look of its own that has to be fought rather than
used. `SegmentedButton` slid a check mark in beside the chosen label, which
reads as *done* rather than *chosen*; `GuardianSwitcher` lifts the chosen
side onto a white card instead. `OutlineInputBorder` draws a 1px box that
fights the soft cards around it; `guardianField` fills and rounds instead.

The sign-in screen's three benefits carry **a tinted mark, not a number**.
Numbered badges said they were steps, and nobody does them in order. 돌봄's
four capabilities got the same treatment for the same reason: all four wore
the same clock, which turned four different things into a wall of identical
rows.

**`준비 중` on 돌봄 is a block, not a footnote.** It was a 13px grey line under
a heading — the least visible thing on the screen it is most important to be
honest on, since that screen takes money for four features none of which is
built. It is now amber, bold, and carries its whole sentence rather than a
chip's worth of it; `care_consent_test.dart` still looks for that sentence.

`ConversationView` draws both personas, so it cannot hold a colour of its
own: its bubbles and its composer read `ColorScheme`, which is terracotta on
the senior's phone and blue on the guardian's. The allowance line under the
heading was centred — the `Column` it sits in centres its children and the
`Padding` shrink-wrapped the text — and is now where the heading starts. The one filled button on the half wears the **hero's gradient**
rather than a flat `guardianPrimary` — a solid slab of `#0B5FD9` under a
gradient card reads as a Material default nobody styled, which is what it
was. The launcher rows' drag handle was `#9C8770`, the muted clay that came
out of the senior palette with the rest of the beige and had no business on
this half either.

The Material `NavigationBar` is gone the same way it went from 자세한 화면, and
for one of the same reasons: it brings its own height, its own pill indicator
and its own type scale, none of which match this one. `GuardianNavBar` draws
five destinations and nothing else. Several tests used `find.byType(
NavigationBar)` as shorthand for "we landed on the dashboard" and now look for
`GuardianNavKeys.bar`.

## The font is bundled

`assets/fonts/NotoSansKR-{Regular,Bold}.ttf`, declared in `pubspec.yaml` and
set as `AppTheme.fontFamily` on both personas. Undeclared, Flutter draws Korean
in whatever face the handset ships — 삼성One on a Galaxy, Roboto elsewhere — so
the app looked different on every phone and matched the design on none of them.

Three things about it:

- **Static faces, not the upstream variable font.** Flutter picks between
  *files* by weight and never moves a variable font's `wght` axis on its own;
  that only happens through `TextStyle.fontVariations`. One variable asset
  would draw every 700/800/900 label at the axis default, which is Thin.
- **Only 400 and 700 are bundled**, so w500/w600 round to Regular and w800/w900
  to Bold. A third face is 2.7 MB for a difference nobody reads at a glance.
- **They are subset.** Hanja is dropped, which is what takes each face from
  10 MB to 2.7. Anything outside the subset still draws through Flutter's
  fallback to the system font. `tool/build_fonts.py` regenerates both and
  documents the ranges; the OFL text is bundled and registered with
  `LicenseRegistry` because redistributing the font requires it.

`screenshots_test.dart` loads these same faces out of the asset bundle — test
environments register no bundled fonts — and deliberately registers nothing
under the fallback family, so a label the theme failed to reach shows up in the
PNG as tofu rather than being papered over.

## Supabase

Wired in as of Phase 4. `SUPABASE_ACCESS_TOKEN` in the environment is now a
working Management API token (the earlier value was the dashboard's masked
display copied as text; that is fixed).

Project: `jal 26.07`, ref `jnmvhdmxzonngqyicelx`, ap-southeast-1, PostgreSQL 17.
`SUPABASE_PROJECT_REF` holds the ref.

**The project pauses itself when nobody uses it.** It is on the free plan, and
after a stretch of inactivity its status goes `INACTIVE` — the schema and the
data survive, but every call fails until it is restored. It came back after two
idle months this way. Restoring it needs no dashboard:

```bash
curl -X POST -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H 'User-Agent: curl/8.5.0' -d '{}' \
  "https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF/restore"
```

It answers immediately and then takes two or three minutes, moving through
`COMING_UP` and `RESTORING` to `ACTIVE_HEALTHY`; poll `GET /v1/projects` for the
status rather than assuming. Give it a moment after that before trusting a
failure: running the Phase 5 and Phase 6 scripts back to back right after a
restore threw once and then never reproduced.

### Schema

`supabase/migrations/20260729000000_phase4_core.sql` is the whole Phase 4
schema and is already applied. Five tables — `guardian_accounts`,
`senior_profiles`, `senior_devices`, `guardian_senior_links`, `home_apps` — all
with RLS on, plus four RPCs (`ensure_guardian_account`, `create_senior_profile`,
`register_senior_device`, `replace_home_apps`). Phase 5 and Phase 6 tables are
deliberately absent.

Two deviations from `05_DATA_MODEL`, both load-bearing:

- `senior_devices.auth_user_id` — the senior is never asked to make an account,
  so their phone signs in **anonymously** and this column is what ties that
  anonymous user to the profile RLS lets it touch. Anonymous sign-ins are
  enabled on the project; turning them off breaks every senior device.
- `home_apps.client_id` — the launcher's own `LauncherApp.id`, so a rename or a
  recolour lands on the existing row instead of creating a second button.

`senior_profiles.screen_mode` and `font_size` are both nullable with no default.
Null means *nobody has chosen yet*: a guardian creates the profile before the
parent's phone connects, and defaulting `font_size` to `normal` would let that
silence shrink the text of a senior who had already set 아주 크게.

`tool/verify_supabase_phase4.py` walks the whole acceptance list against the
live project — sign-in, linking, device swap, both sync directions, and the RLS
denials — then deletes everything it made. Run it with
`SSL_CERT_FILE=/root/.ccr/ca-bundle.crt python3 tool/verify_supabase_phase4.py`;
without the CA bundle, and without a non-default `User-Agent`, the agent proxy
403s Python.

### Running the app against it

Nothing is committed. The keys arrive at build time:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://jnmvhdmxzonngqyicelx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable key>
```

**A build with no keys still runs.** `SupabaseConfig.isConfigured` is false, and
every repository provider resolves to its `InMemory…` twin instead. Phases 0-3
were built with no backend and `flutter test` has no keys, so that fallback is
load-bearing, not a convenience — don't make any screen require a live client.

### Pairing (Phase 5)

`supabase/migrations/20260730000000_phase5_pairing.sql` adds `pair_links` and
`senior_profiles.pending_primary_guardian_id`. Four modes share one table
because they are one idea — a short-lived secret granting exactly one
attachment — but redeeming always names the mode, so a family invite can never
be spent as a recovery.

Three things worth knowing before changing any of it:

- **The code direction is the plan's, not Phase 4's.** 경로 B is the parent's
  phone *showing* a 4-digit code that the guardian types. A code cannot carry a
  phone number, which is exactly why the guardian supplies the number and the
  name at that moment.
- **The parent's phone can create its own profile.** 경로 A rides on the Play
  install referrer, which only survives a store install, so 경로 B is the
  required fallback and has to work with no guardian present. `start_senior_pairing`
  is that path; removing it removes the fallback.
- **"연결됨" means a guardian is attached, not that a profile exists.** Showing a
  code creates the profile. Keying the senior's screen off the profile told
  them their family had arrived before anyone had typed the number.

Every invite carries both a token (the referrer) and a code (for when the
referrer did not survive). Expiries differ on purpose: 10 minutes for the
4-digit code, 24 hours for recovery, 7 days for a family invite, 14 days for an
install invite.

Moving the primary guardian is answered on the senior's own phone —
`PrimaryGuardianPrompt`, on both home screens. Not the requester, not the
current primary, not any guardian. Everyone else in the list is a guardian, so
nothing they agree among themselves establishes who should answer for the
senior.

### Guardian sign-in is email-only, and email is now its own button

Kakao and Google have no OAuth client configured on the project, and only the
repo owner can add one. `GuardianStartScreen` still leads with both buttons —
that is a deliberate design decision, see the spec — but with a project
attached they open a sheet saying the provider is being prepared and offer the
email route. With no project attached they open the dashboard as they did in
Phase 3.

**이메일로 시작하기 is the third button**, added 2026-10-27. It goes straight
to `/guardian-login` with no sheet, because it has nothing to apologise for
and nothing being prepared — a sheet there would be a screen that exists to be
passed through. It is last of the three because it asks for a password to
invent and remember, which is the most work, and it wears the app's own
`guardianTintBlue` rather than a brand's: white-and-bordered would have read
as a second Google. Lettering measures 5.1:1 on that face.

A test used to assert `이메일로 시작하기` was absent, under the rule that
`~로 시작하기` must not be split into 가입 and 로그인. That rule is about the
**verb**, not the provider, and a third provider wearing the same verb splits
nothing. The test now pins `이메일로 로그인` and `이메일로 가입하기` instead,
which are the strings that would actually break it.

### Email sign-up cannot work until the project's mail is configured

**Nothing is wrong with the app.** Checked against the live project on
2026-10-27, and `auth.users` held **zero rows** — not one unconfirmed account,
not one anonymous senior device. Three server settings, none of them in this
repository, stand between 가입하기 and an account:

| | |
|---|---|
| `smtp_host` | unset — the built-in sender delivers **only to members of the Supabase organization**, 2 per hour for the whole project |
| `mailer_autoconfirm` | `false` — an account is unusable until an emailed link is followed |
| `site_url` | `http://localhost:3000` — so a delivered link would point at a machine the phone cannot reach |

The first is why no row exists: when the send fails the sign-up fails with it,
so the account is never created rather than created-and-unconfirmed. A
guardian who is not in the Supabase org cannot sign up at all, and that is
every guardian but the owner.

**Custom SMTP is now attached** (2026-10-27): `jalboine.com` bought at 가비아,
verified in Resend with DKIM + two CNAMEs + DMARC, and
`smtp.resend.com:465` / user `resend` / sender `noreply@jalboine.com` saved on
the project. `rate_limit_email_sent` went from 2 to 30. Mail to any recipient
now works.

Two settings are still the owner's, and **no agent can make them** — every
`PATCH` to `/config/auth` from here is refused, the autoconfirm one as a
security relaxation and the allow-list one by the classifier outright:

| | |
|---|---|
| `Confirm email` | off, by decision — address verification is not wanted before launch, so sign-up returns a session straight away |
| `uri_allow_list` | must contain `https://jdnnetwork.github.io/success/reset.html`, or a reset lands on `site_url` instead |

`site_url` can stay `http://localhost:3000` **only while `Confirm email` is
off**, because nothing then redirects through it. Turning confirmation back
on before launch means fixing it in the same breath; `site/index.html` is
the page it should point at.

### 비밀번호를 잊으셨나요

Added 2026-10-27, and it had been missing since Phase 4: the login screen
held an email box, a password box and 가입하기, so a guardian who forgot
their password was locked out **permanently**. There is no other identifier
on the account and no support desk.

**This is the one auth mail that cannot be switched off.** Confirming an
address at sign-up is optional and is now off; a reset has to reach the
person's inbox or it is not a reset. That is what the domain and the SMTP
are for, and why neither was wasted by the decision above.

Three parts:

- `GuardianAuthRepository.sendPasswordReset` returns nothing a caller can
  branch on, and the screen says the same sentence for an address with no
  account as for one that has. Branching would turn the login form into a
  way of asking the server which addresses are registered.
- The row sends to **whatever is in the address box** — no dialog, no second
  screen. The field is already there, and somebody locked out is not helped
  by being asked to retype it elsewhere. An empty box is `GuardianLogin
  NeedsEmail`, which is not a failure: nothing failed, the form is not ready.
  It is hidden in 가입 mode, where nobody has a password to recover.
- `site/reset.html` is where the link lands, and unlike `index.html` it has
  work to do: Supabase redirects there with a session in the URL fragment
  and the form spends it on one `updateUser({password})`. The fragment is
  **stripped from the address bar as soon as it is read** — it carries a live
  access token, and a screenshot of that URL is the account. The page signs
  the session out once the password is changed.

The publishable key is in that page's source on purpose: it is the same key
every APK ships with, it names the project and nothing else, and RLS is what
actually guards the data. The secret key is not there and must not be.

## 가족 메시지 and its allowance

`supabase/migrations/20260801000000_phase7_messages.sql`. The PRD prices it at
월 50회 / 이미지 10개 free, unlimited with 안심 케어, and two decisions in the
counting are load-bearing:

- **The quota counts guardian messages only.** A senior replying to their child
  is never blocked, whatever the counter says — a launcher for an elderly
  person that refuses to let them answer their daughter because a monthly
  allowance ran out is selling the wrong thing, and the allowance exists to
  price the guardian's use.
- **The allowance is the family's, not each guardian's.** Two siblings share
  one, because the parent is the one reading them.

`ConversationView` draws both ends. One widget on purpose: it is the same
conversation, and two copies would drift. `large` is what differs — the
senior's is scaled up and hides the counter, because a tally of how many times
their family may write to them would be unkind and is not about them anyway.

On the senior's home, `04_SCREEN_SPEC`'s 가족 연결 또는 자녀 이름 버튼 is now
literal: before a family is attached it connects one, and afterwards it opens
the conversation.

## The guardian's changes now actually arrive

홈 화면 promises 바꾸면 부모님 폰에 반영됩니다. 부모님 폰이 꺼져 있으면 다음에
켤 때 적용돼요. The second half of that was not implemented: `pullFromServer`
was called **only at the moment the phone was linked**, from the pairing and
link controllers. An arrangement the guardian made the next day never arrived
on the parent's phone at all. `settings_sync_gaps_test.dart` is that promise,
and it fails on the code it replaces.

Two reads cover it, and both are deliberate about not blocking:

- **At start-up**, `SeniorSettingsController.build` returns what is on disk
  and *then* pulls. Awaiting the server there would open a launcher with no
  signal on a spinner.
- **On resume**, through `HomeKeyListener`, which already wraps the whole
  router. A launcher is the screen a phone sits on and may go weeks without a
  restart, so start-up alone is not enough.

Both are guarded on this phone having a `SeniorLink`, and the guard sits
**before** the sync is constructed. Without it a guardian's phone pulls a
senior's settings on every resume — six login tests failed immediately, which
is how the missing guard was found.

## 안부 신호 — the one reading that costs no permission

`last_seen_at` has existed since Phase 4 and **nothing ever wrote it after the
phone registered**. `register_senior_device` set it once; no other path touched
it. The hero card then read that column in the present tense, so a phone set up
in July and never opened since still lit the green dot and said `폰은 잘 켜져
있어요`. The column was right and the writer was missing — and *stale* is its
own kind of fabrication: the card was honest about a **missing** check-in from
the day it was built and silent about an old one.

`touch_senior_device` (`20261021000000_presence_touch.sql`, applied to the live
project) is the writer, and `SeniorPresenceReporter` calls it from
`HomeKeyListener` at start-up and on every resume. Because this app *is* the
phone's home screen, resume means the parent unlocked it or came back from
another app, so the signal is real — and it needs **no location, no sensor, no
background service, nothing Play reviews and nothing extra for the senior to
agree to.** It is the only one of 안심 케어's readings that can ship today, and
`06_PERMISSION_AND_POLICY`'s 위치정보 problem does not reach it.

Four things hold it up:

- **`SeniorPresence` owns every word the card says about the phone**, bracketed
  as never / 방금 / today / 어제 / N일째. A test walks all five brackets for
  안전, 괜찮, 잘 계, 건강 and 이상 없음, because a check-in says a phone was
  unlocked and nothing whatever about the person holding it.
- **The green dot means *now* and nothing looser.** Lit only inside
  `stillInHand` (10 minutes). An hour-old report means the phone has been face
  down on a table, and `오늘` is a day wide — a dot for either is the same
  overclaim in a smaller space.
- **Days are calendar days, not 24-hour blocks.** 23:50 to 00:10 is twenty
  minutes and two dates, and 어제 is what a person would say. A clock running
  fast stamps a check-in in the future; that reads as 방금, never `-1일째`.
- **The repository is read *after* the link guard, not taken in the
  constructor.** `HomeKeyListener` wraps the whole router, so this runs on the
  guardian's phone too. Writing the provider with `ref.watch` instead **hung
  every guardian login test** — the same trap the settings pull documents one
  section up, and it was walked straight into again.

`is_active` is deliberately untouched by a report. A phone the parent has
replaced may still have the app on it and still resume; letting that flip the
flag back would hand the retired handset the profile, and the unique index on
one active device per profile would start rejecting the real one.
`tool/verify_supabase_presence.py` checks that against the live project, along
with one phone reporting for another and a call with no session.

## 위치 is out of the product, and four things took its place

Settled 2026-10-26 and written into `01_PRODUCT_PRD` (`## 위치 기능을 뺀 이유`),
`02_MVP_SCOPE`, `04_SCREEN_SPEC` and `06_PERMISSION_AND_POLICY` — this is a PRD
change, not a code one, and the docs are where it lives. Three things stacked
up and none is solved by money or time:

1. **119 and the police are better and free.** 위치정보법 gives 긴급구조기관 a
   route to ask a carrier directly: no app, no permission, carrier-grade. In a
   real emergency ours is an inferior copy. 치매 배회 has the same problem —
   치매안심센터 hands out 배회감지기 for nothing.
2. **Play's stalkerware rule aims at exactly this.** Collecting sensitive data
   about another person is barred outside parent→child and enterprise→employee,
   and the carve-out explicitly does not reach other adults **even with their
   permission**. Unlike the Korean 신고, no paperwork fixes that. (Google's own
   pages cannot be read from this environment — the proxy 403s
   `support.google.com` — so confirm before shipping.)
3. **위치기반서비스사업 신고 applies however it is collected.** Device GPS,
   carrier API, on the check-in, on demand — the only exemption is location
   that never leaves the handset, and the whole point is to show it to the
   child.

**Two technical dead ends worth recording** so nobody re-derives them.
`developer.android.com`, read directly: a location foreground service **cannot
be created while the app is in the background** without
`ACCESS_BACKGROUND_LOCATION`, and the FCM high-priority exemption that covers
every other foreground-service type **does not cover location**. So "wake the
phone with a push and take one reading" is not a way around the hard
permission; there isn't one. And the carrier API is strictly worse here — it
removes no obligation, it is hundreds of metres coarse, and we are the
launcher, which is the best position an Android app can have for reading GPS.

What the paid tier is now: **배터리 부족 알림, 폰 미사용 알림, 읽음 확인,
소리 울리기, 5분 주기 갱신, 가족 메시지 무제한.** The character moved from
watching to connecting, which also removes every stalkerware question and the
신고 entirely.

### The four that replaced it

- **사람 버튼** (`AppCategory.contact`). Free. Seniors fail at finding *people*
  far more than at finding apps — 연락처 and scrolling is where they give up.
  The guardian types the number from their own phone, so the parent's launcher
  never needs a contacts permission. `home_apps.app_type` had
  `'family_contact'` in its check constraint from Phase 4; `05_DATA_MODEL`
  anticipated this and nothing had ever written one. It shares **가족's
  amber** rather than taking a colour of its own: the warm band is already at
  13°, 32°, 36° and 37°, and anything fitted between them is
  indistinguishable at arm's length. Ink lettering, same rule as 카카오톡.
  The dialog **reads the number back** before it will save — the parent cannot
  check it and will not learn of a wrong digit until a stranger answers — and
  refuses under nine digits.
- **읽어드리기.** Free, and it has to be: bigger text has a floor, and past it
  the only thing left is sound. Charging someone to hear their own daughter
  because their eyes went is the mistake the message allowance already
  refuses. Android's TTS is built in — no permission, no download, nothing for
  Play. The whole bubble is the button, with a speaker beside it; a small icon
  alone is a target an ageing hand misses. Received messages only, senior's
  phone only.
- **빠른 답장** — 「전화 좀 줘」「잘 있다」「고맙다」. Free. The first is why it
  exists: a parent who does not want to be a bother will not compose and will
  not ring, but will press a button that costs nothing and explains itself.
  Sent as ordinary messages rather than a new alert channel, so it is useful
  **without FCM** and shows up in the band the guardian already reads. The
  composer's half-written text is left alone.
- **읽음 확인.** This is what is left of the reassurance 위치 was going to
  sell, and the better half: `어머니가 두 시에 읽으셨다` is decent evidence a
  parent is all right, and unlike a location it is something **they did**.
  **One direction only** — the parent is never shown whether their child read
  *them*. A senior watching an unread mark on a message to a busy adult is the
  unkindest thing this app could put on a screen. And there is no 안 읽음 at
  all: a mark counting how long someone has been left waiting teaches a
  guardian to nag. `mark_conversation_read` takes no message ids — the caller
  marks the conversation, so nothing can claim a read on what it never showed,
  and neither side can mark its own.

## 소리 울리기, and the trap that has now appeared three times

The feature is for **`엄마가 전화를 안 받아`** — the phone is on silent, or in
another room, or not heard. The job is to get the parent to pick it up.

Two ideas were considered and dropped, and the reasons are the design:

- **A recorded voice asking passers-by for help.** Technically fine — the
  guardian records on their own phone, so the senior's microphone is never
  used. Dropped because somebody collapsed in public gets helped without an
  app, and a phone announcing a stranger's health to the street embarrasses
  the person it was meant to help. The same recording *addressed to the
  parent* is a different feature with a different justification, and it was
  not built either.
- **Splitting 무료 = sound, 유료 = message.** That sells the part that stops
  the sound being frightening. A phone that starts screaming with no
  explanation, at someone who cannot tell a message from a fault, is worse
  than one that stays quiet — so the line is always there, and the whole
  feature is paid. The line that is actually worth charging for is *being
  able to reach the phone at all*.

**Anywhere on the screen stops it.** `HitTestBehavior.opaque`, so the gaps
answer too — without it the senior taps a dead patch while it keeps ringing. A
pocket could end it early; the guardian can send it again, and that is not in
the same league as a senior unable to silence their own phone. It also stops
itself after `maxDuration` (60s), because the phone may be in a bag in another
room — which is the case this exists for — and a sound with no end is a flat
battery rather than a found phone.

**The speaker is told, never awaited**, and this is the third time that trap
has appeared in this codebase — after the onboarding channel and the device
status read. `MethodChannelEmergencySound` already swallows both channel
exceptions, but **a channel that never answers throws nothing at all**, so
catching is not enough. Awaiting it hung `screenshots_test.dart` for seven
minutes before the timeout. The rule, stated once for all three: *nothing a
senior is looking at may wait on a platform channel.*

On Android it plays on `STREAM_ALARM`, the one stream a silent or vibrate
ringer does not mute — that is how alarm clocks work. DND can still mute it
where the user has turned alarms off inside DND; overriding that needs
`ACCESS_NOTIFICATION_POLICY` and is not worth demanding. None of that is
written yet and none of it can be verified here.

**It still cannot be triggered, but the receiving half now exists.** The
Firebase project is registered and the parent's phone reports an FCM token on
every check-in; a `{"type":"ring"}` data message arriving in the foreground
raises `SeniorRingLayer`. Two halves are left and both are outside what can be
built here — see `## Firebase` below.

### What Play's policy actually bites

Worth recording because it points the other way from where it was expected to.
The stalkerware rule turns on **collecting and transmitting personal and
sensitive data** about another person, with an exemption only for parent→child
and enterprise→employee — and that exemption explicitly does not extend to
other adults *even with their permission*.

So **소리 울리기 is the safest feature left**: it is remote actuation, nothing
about the parent leaves their phone, and the screen lights up saying exactly
what was sent. The ones the rule aims at are **위치 확인** and **앱 설치 알림**,
both of which collect sensitive data about an adult — and unlike the Korean
위치기반서비스사업 신고, no paperwork fixes that.

Two honest limits on the above: Google's policy pages **cannot be read from
this environment** (the proxy 403s `support.google.com`), so this rests on two
independent search summaries quoting them, and the policy as enforced plainly
differs from the policy as written — Life360 and its like track adult family
members and are published. Read the primary pages before acting on this.

## One list decides what 안심 케어 is, on both screens

`lib/features/care/data/care_capabilities.dart`. The guardian's 돌봄 tab and
the senior's consent card are two descriptions of one product, and they had
already come apart. The card asked the senior to agree to:

- **`5분마다 어디 계신지`** — not built, and not until the 위치기반서비스사업
  신고 is through. A 허락합니다 pressed today would have been the only thing
  ever asked before location switched itself on months later. The whole first
  line of `06_PERMISSION_AND_POLICY` is 권한은 필요한 순간에 요청한다.
- **`배터리와 소리, 인터넷 상태`** — of which 인터넷 is never read, and the
  rest is **free** and sent on every check-in regardless. That one is the
  worse of the two: it told the senior that 아니요 would stop something 아니요
  does not stop. A consent screen that misdescribes its own refusal is not a
  consent screen.

Each capability now carries a `CareReadiness` — `free`, `live` or `planned` —
and a `seniorLine` that exists only for `live`. Both screens read that list,
so a capability cannot be sold on one and missing from the other, and
`care_capabilities_test.dart` holds the four rules:

| | |
|---|---|
| everything on the consent card is built | a consent nobody gave |
| everything built and paid is on it | a capability that starts running unnamed |
| nothing free is on it | implies 아니요 stops it |
| nothing planned is on it | asked once, switched on much later |

It also counts the glyphs — sixteen at 20px in a 318px card — because that is
the screen where a wrapped line once left 은 alone.

Which leaves **the two alerts**, and they are worded as *when the guardian is
told* rather than *what is collected*, since the collection is the free
check-in either way. `CareReadiness` is named for readiness because `CareStage`
was already the subscription flow (notBought / waitingOnSenior / refused /
active) and the two would read as one idea on a screen using both.

**Billing is deliberately still absent** and the buy button still makes a
subscription with no money. That is the owner's call and it is next; the
consent half was done first because it is the half with a person on the other
end of it.

## 배터리 부족 알림 and 폰 미사용 알림

The `alerts` table and the 돌봄 tab that renders it have existed since Phase 6.
Exactly one thing ever wrote a row — the refund — so these are the first
watchers the product has.

**Both are paid**, and that is the PRD's call, not this file's: 폰 미사용 알림
and 배터리 부족 알림 are both in the 안심 케어 월 5,900원 list, so both are
gated on `care_is_active` — a subscription *and* the senior's consent. With no
Play Billing there is no way to reach either from the app today. The gate is
therefore the part most worth checking, and it is checked where it can be:
`tool/verify_supabase_alerts.py` walks unpaid → paid-without-consent → paid-
and-agreed against the live project, 19 checks.

That same PRD reading settled something else. 무료 includes
**`폰 상태 앱 실행 시 1회 갱신`** in as many words — which is exactly what the
check-in does, so 기기 상태 as built is the *free* half and what 안심 케어 adds
is the **5분 주기** refresh. The 돌봄 tab names that now, instead of selling
the family back a feature they already have.

The two need opposite machinery, which is the whole interest of them:

- **배터리 부족 fires on an event** and is written on the way through
  `touch_senior_device`. It carries **hysteresis**: raised at 15% and armed
  again only at 30% or on the charger. Without it a phone sitting at 12%
  writes a row on every resume — dozens a day, which is not an alert, it is a
  reason to stop reading alerts. Charging is never low: it is low being dealt
  with, the same rule the guardian's amber battery row follows.
- **폰 미사용 fires on the absence of events**, so nothing the phone does can
  trigger it. That needs something that runs when nothing happens:
  **pg_cron**, installed on the project, one job at `7 0 * * *` — 09:07 KST,
  morning so the guardian reads it when they could act, off the hour because
  every other job in the world runs at :00.

Two decisions in the dedup, and the second was wrong first:

- **A phone that has never checked in is 연결되기 전, not 미사용.** There is
  nothing to tell the guardian that their own dashboard does not already say.
- **`unused_notified_for` stores the check-in the alert was about, not the
  moment it was written.** `now()` reads as *we have spoken recently*, which
  is a different claim: a phone picked up and then left again compares its new
  silence against a mark already past it and stays quiet forever. Storing the
  check-in means a later one arms the next alert by itself, with no clearing
  step to miss. The verifier caught this — picking the phone up and letting it
  go quiet again produced nothing.

Neither helper is callable by a client: `raise_battery_alert` is reached only
through the check-in, `check_unused_phones` belongs to cron, and both are
revoked from `authenticated`. There are checks for both refusals.

## The roster was readable by nobody it was about

`guardian_accounts` has exactly one policy — `guardian_accounts_own`,
`auth_user_id = auth.uid()` — which is right for the table and wrong for
everything built on it, because `guardiansFor` read the names through an
**embedded select** and the embed inherits the policy. Probed against the live
project, a family of one parent and two guardians answered like this:

| caller | primary | family |
|---|---|---|
| the parent's phone | `null` | `null` |
| guardian g1 | `{g1}` | `null` |
| guardian g2 | `null` | `{g2}` |

Everyone saw their own row and nothing else. Two screens were built on that:

- **긴급 연락's 보호자 button.** `04_SCREEN_SPEC` asks for 119, 112 and 보호자.
  It was `onTap: null` from the day the screen existed, under a caption
  reading 가족을 연결하면 사용할 수 있어요 — and connecting a family did not
  enable it. The number is collected when the guardian connects and stored in
  `guardian_accounts.phone_number`; the one phone that needs it in an
  emergency was the one phone with no policy to read it.
- **연결된 가족** on the guardian's 가족 tab, which listed a sibling as the
  literal word 보호자, because their name read as null and the UI falls back.

`guardians_for_senior` (`20261021020000_guardian_roster.sql`, applied live) is
a `security definer` function rather than a widened policy: the table's own
rule stays as strict as it is, and the function returns exactly the roster.
**No `flutter test` could have caught either bug** — the in-memory repository
always returned the names, so both halves passed locally and failed only
against a real project. `tool/verify_supabase_roster.py` is what covers it,
including the two refusals and the removed guardian.

What it returns, and why:

- **`phone_number` to the whole family.** They can already rearrange the
  parent's home screen and read every message; a number they gave each other
  is less than that, and without it the SOS button cannot exist at all.
- **`email` only to the account it belongs to.** It identifies an account
  rather than reaching anyone, and the roster has a name for that.
- **대표 보호자 first**, because that is who the SOS button calls. The Dart
  does not rely on the ordering, but the ordering is the reason it is right.

The tile's caption is now three different sentences, and that is the point:
no family (`가족을 연결하면 사용할 수 있어요`), a family that gave no number
(`자녀분 전화번호가 아직 없어요` — the field says 비워 두셔도 됩니다, so this is
a real state), and otherwise the guardian's name. One sentence for all three
made it a lie in the case it mattered most. It still dials rather than calls,
exactly as 119 does, and **119 and 112 depend on none of it** — there is a
test pinning that on a phone with no family at all.

## 기기 상태 rides on the check-in, not on a schedule

The second capability, and the second that needs **no permission at all**:
Android hands any app the battery level and the ringer mode with no runtime
permission, no manifest permission and nothing for Play to review.

`07_PHASE_PLAN` asks for a *5-minute background sync*, which is a foreground
service this environment cannot build or verify. It is not what shipped and it
was not needed: a reading is worth having exactly when the parent used the
phone, and `SeniorPresenceReporter` already fires at that moment. One call, one
row, one thing to fail. `DeviceStatusSync` survives in `care_interfaces.dart`
as **only** the background schedule that would keep a reading fresh while the
phone sits untouched; its `latest` is gone, because the reading is a column on
the device row now and an interface returning null beside a screen showing a
real number is the misleading one.

Four decisions, and the first two are the same mistake made twice:

- **The check-in never waits for the phone.** Awaiting the channel was the
  first attempt and it stopped the parent's phone reporting at all whenever
  the channel did not answer — `flutter test` is such a phone, and so is one
  whose launcher service has wedged. Bounding it with `.timeout` was the
  second and was worse: the timer outlives the widget tree, and **eighteen
  tests failed at teardown** rather than in the open. The read is now started
  and not awaited, and its result goes up with the **next** check-in. That is
  the whole cost: one resume of staleness, on a reading that is stamped with
  the time it was taken anyway.
- **Null never overwrites.** `touch_senior_device` coalesces, so a phone that
  could not read its battery leaves the last real reading standing. Writing
  the null through would take the card from 72% to 아직 받지 못했어요 for no
  reason the guardian could see.
- **A missing reading is never a zero.** The Kotlin omits a key it cannot
  read, the Dart treats a missing key as *this phone did not say*, and
  `DeviceStatusLines` says so in words. 배터리 0% is the most alarming reading
  the card can show and nothing may invent it.
- **인터넷 is gone from the row rather than left as a third 준비 중.**
  Reporting it means `ACCESS_NETWORK_STATE` for a fact the check-in already
  proves: a reading that arrived is a reading that got through.

The ringer is a **mode**, not the `ringerPercent` the Phase 6 sketch declared.
The question a guardian is asking is 왜 전화를 안 받으시지, and a phone can sit
in silent mode with its ring volume at 100% — a percentage answers the wrong
question with a confident-looking number.

A battery under 15% is drawn in amber, **unless it is charging**: 8% on the
charger is a problem being solved, and flagging it teaches the guardian to
ignore the flag. `guardian_palette_test.dart` measures that amber against the
bottom of the card, because it carries the value itself at 15px.

The Kotlin is in `MainActivity.deviceStatus()` and, like everything else in
that file, **has never run** — see `## The launcher half is native`. Two things
in it are easy to get wrong: `EXTRA_SCALE` is not always 100, so dividing by a
hard-coded 100 reads 7% on a full phone, and `ACTION_BATTERY_CHANGED` is sticky,
so a null receiver returns the last broadcast at once instead of waiting for a
change that may be minutes away.

`tool/verify_supabase_presence.py` covers both capabilities against the live
project — 18 checks, including the coalesce, the range constraint, and a new
phone starting with no reading rather than inheriting the old one's.

## The paid features are interfaces

`lib/features/care/data/care_interfaces.dart` declares four capabilities and
implements none of them. That is deliberate and it is what `07_PHASE_PLAN` asks
for — it lists a *location interface*, an *unknown-contact call alert
interface*, an *app install alert interface* and a *5-minute background sync
interface*, not the implementations. Each needs a system permission whose Play
policy has to be cleared first, and the only implementations today are
`Unimplemented…` classes that return nothing rather than plausible numbers, so a
screen wired to one has to render its empty state.

Three rules run through all of it, and none is a detail:

- **Paying does not turn 안심 케어 on.** `06_PERMISSION_AND_POLICY` puts the
  senior's agreement *after* the payment, so `pending_senior_consent` is a real
  state the guardian's screen explains rather than hides. `care_is_active`
  requires both halves and the consent half decides: a paid subscription with no
  consent must behave exactly like no subscription.
- **A refusal refunds, and is final.** It writes an alert telling the guardian
  the money came back and that the free features still work. It does not retry
  or nag, and it must not disable anything the senior was already using.
- **Location is 5분 주기 위치 확인, never tracking.** The class is called
  `PeriodicLocationCheck` for that reason: how the feature is described is what
  the senior consents to, so a `LiveLocationTracker` would make the consent
  screen a misrepresentation. There is a test asserting 실시간 and 추적 appear
  nowhere on that screen.

**No money moves.** Play Billing is native, needs a store listing, and cannot be
built or verified here. `start_care_subscription` is the seam where a verified
purchase token will be checked; everything downstream of it is real.

The family plan gates a *second parent* (`assert_can_add_senior`), which is not
the same thing as inviting a sibling to help with one parent — that stays free,
per the PRD, and both screens say so.

## The launcher half is native, and unverified here

`android/app/src/main/kotlin/com/example/app/MainActivity.kt` is the only
non-Flutter code in the project. It does two things: opens other apps, and
answers whether this app is the phone's home app.

**None of it has ever run.** There is no Android SDK and no `kotlinc` in this
environment, so the Kotlin is not compiled by `flutter analyze` and not covered
by `flutter test` — the Dart side is tested against `FakeAppLauncher`, which
proves the app asks for the right thing, not that the phone answers. Anything
touching that file needs a real build before it can be called working.

Three decisions in it are load-bearing:

- **The `HOME` + `DEFAULT` intent-filter is what makes this a launcher.**
  Without it the phone never offers the app in its home-app chooser. It comes
  with `launchMode="singleTask"` and `stateNotNeeded="true"`, which launchers
  need so pressing Home brings the running task forward instead of stacking a
  second copy.
- **Pressing Home is delivered through `onNewIntent`, not a restart.** The
  activity is already running, so the HOME intent arrives as a new intent and
  is forwarded to Dart as `goHome`; `HomeKeyListener` sends the router back to
  `/`. Without it the home key does nothing whenever the senior is anywhere but
  the home screen — which is exactly when they reach for it.
- **The `<queries>` block is not boilerplate.** On Android 11+ an app cannot
  see another app it has not declared, so removing an entry does not degrade a
  home button, it makes it fail silently. Adding a new button category means
  adding its intent there too.

System apps (전화, 문자, 사진, 앨범) are opened by intent category so each phone
uses the apps its owner already has. Only 카카오톡 and 유튜브 are named by
package, because Android has no category for them. 전화 resolves to
`ACTION_DIAL` and never `ACTION_CALL` — `06_PERMISSION_AND_POLICY` requires the
user press call themselves, and that holds for the 전화 button exactly as it
does for SOS.

## No APK from this environment — build it in CI

`dl.google.com` is blocked by egress policy, which rules out both the Android
SDK and the Android Gradle Plugin. Don't spend time installing either.

`.github/workflows/android.yml` builds the APK on GitHub's runners on every
push, and uploads it as a run artifact along with the review screenshots. That
is the only place the Kotlin is ever compiled, and the only way to get the app
onto a real phone from here.

Two things about it:

- The `apk` job deliberately does **not** depend on the `check` job. The first
  question the workflow answers is whether the native half compiles at all, and
  a failing Dart test must not withhold that answer.
- The APK is signed with the **debug** key, because
  `android/app/build.gradle.kts` still points the release build type at
  `signingConfigs.debug`. It sideloads fine and is enough to test on a phone. It
  is not a store build — a real upload key is still to do. The `applicationId`
  is no longer one of the blockers; see `## com.jalboine.app` below.

Neither job fetches a font any more. The app's own faces are committed under
`assets/fonts/`, and `screenshots_test.dart` reads them from the asset bundle,
so a fresh clone renders the same PNGs CI does.

`SUPABASE_URL` and the publishable key are optional repository secrets. Unset,
the APK still builds and runs on the in-memory repositories; sign-in, linking
and syncing simply do not reach a server. The run summary says which of the two
you got, and so does the log, as a `WIRED-TO:` line.

The key is accepted as **either** `SUPABASE_PUBLISHABLE_KEY` or
`SUPABASE_ANON_KEY`. Both names exist because Supabase renamed the thing: the
repository had it stored as the former while this workflow asked for the
latter, so the secret was present and every APK was still built without a key —
a mismatch that fails silently, since a keyless build is a supported
configuration rather than an error. The `--dart-define` is unrelated to either
name; it is what `SupabaseConfig.fromEnvironment` reads and it stays
`SUPABASE_ANON_KEY`.

## com.jalboine.app

Settled 2026-10-26. It was the Flutter template's `com.example.app` until
then, and that one string was holding up four separate things: Play refuses
`com.example.*` outright, Firebase registers an app *by* its id, and both the
Google and the Kakao OAuth redirect URIs are built from it. Picking it unblocks
all four at once, which is why it was worth doing before any of them.

**It can never be changed again** once a listing exists — Play ties the listing
to the id for good — so this is the one value in the project with no second
attempt.

It lives in three places that cannot see each other:

| | |
|---|---|
| `android/app/build.gradle.kts` | `namespace` and `applicationId` — what the APK is built with |
| `android/app/src/main/kotlin/com/jalboine/app/` | the Kotlin package, which has to be the directory it is in |
| `guardian_pairing_controller.dart` | `const applicationId`, the Play link a guardian texts their parent |

`AndroidManifest.xml` is the exception: it names the activity `.MainActivity`,
relative to the namespace, so it needed no change.

**A mismatch between the Dart copy and the Gradle copy fails silently and in
the worst place.** The APK builds, the guardian's message looks right, and the
parent taps through to a store page for an app that does not exist — on 경로 A,
the path whose whole point is that nobody has to be standing next to them.
`flutter analyze` does not read Gradle and `flutter test` does not build the
APK, so `test/core/application_id_test.dart` reads `build.gradle.kts` off disk
and compares the two, checks the namespace agrees, and checks `MainActivity.kt`
is in the directory its package declares. Flipping the Gradle value by one
character fails it.

`ios/`, `macos/`, `linux/` and `windows/` still carry the template's
`com.example.app`. None of them is built — this is an Android launcher, and
iOS does not let an app be the home screen — so they were left alone rather
than changed to look finished.

What the id does **not** unblock: the upload key, the Play Console account, the
privacy-policy URL and Play Billing are all still to do, and the Firebase
project still has to be created against this id by hand.

## Firebase

Registered 2026-10-26, project `jalboine-7db89` under `blakelee0708@gmail.com`,
Spark plan. It exists for **소리 울리기 and nothing else** — the one thing in
the app that is triggered remotely. Everything else the guardian changes is
read by the parent's phone the next time it asks, which is fine because none of
it is urgent; a phone nobody is holding cannot wait for the next resume.

**Google Analytics is deliberately off.** Half this app's users are seniors
who did not install it, cannot be asked about anything on a screen, and whose
*home screen* this is. Adding telemetry to that is the thing the whole 위치
decision was about, and it would have put IP-derived 대략적 위치 into an app
whose privacy policy is about to say it collects no location. It can be turned
on later from the console if that is ever argued for; it cannot be un-collected.

**No notification permission is needed.** The payload is a **data message**,
not a notification — Android 13's `POST_NOTIFICATIONS` is for notifications,
and a status-bar entry is the one place a senior who cannot find their contacts
app will not look. What arrives is drawn as `SeniorRingLayer`, full screen,
saying who is asking before it says anything else.

`google-services.json` **is committed**, which is correct and not an oversight:
it ships inside every APK, so it is not a secret, and leaving it out means CI
cannot build. The thing that *is* secret is the service-account key the sender
needs, and that has no business in a repository.

### The token rides on the check-in

`senior_devices.push_token` (`20261026020000_push_token.sql`, applied live),
written by `touch_senior_device` with the same `coalesce` as the battery.

It is not a call of its own because **a token rotates** — reinstall, restore to
a new handset, and occasionally for Firebase's own reasons — and the check-in
is the one thing that already runs at start-up and on every resume. Registering
once at pairing would have gone stale silently, which is how 소리 울리기 fails
on the day it matters.

Two things in `SeniorPresenceReporter` are load-bearing:

- **The token read and the battery read are started separately.** Chained, the
  token sat behind a platform channel that is not obliged to answer — and
  `flutter test` is such a phone, so it was never read at all. The test caught
  it. A battery percentage must not be able to cost a family their ring.
- **A new token gets a call of its own**, where the battery waits for the next
  resume. One resume of staleness costs a percentage nobody is watching; here
  it costs *the address the ring is sent to*, and the window it leaves open is
  the one right after a phone is set up, which is exactly when the family is
  trying things out.

**A guardian in the family can read the token column, and that is accepted.**
RLS is row-level and their policy already selects their parent's device row; a
column cannot be carved out of the table-level SELECT grant `authenticated`
holds, so `revoke select (push_token)` is a no-op — tried, checked, and written
into the migration so nobody tries it twice. Enforcing it means revoking the
table grant and re-granting column by column, after which every new column
breaks every read until somebody remembers. That is a trap, and the thing it
would protect is inert: a token sends nothing without the service-account key.
What is done instead is to not hand it out — `activeDevice` names its columns.

### The gate is SQL; the Edge Function only sends

`request_phone_ring` (`20261026030000_request_ring.sql`, applied live) answers
every question about whether a ring is allowed — guardian of *this* parent,
link still `active`, `care_is_active` (a subscription **and** the senior's
consent), which phone, and what the screen will say.
`supabase/functions/ring-phone/index.ts` mints a Google OAuth token from the
service account and POSTs to FCM v1. That is all it does.

The split is the point. The gate is then checkable from an environment that
cannot deploy or run Deno — `tool/verify_supabase_ring.py`, 13 checks against
the live project — and the subscription rule does not end up living in two
languages with one copy nobody can test. It also keeps the service key out of
the authorization path: the function forwards **the caller's own JWT** to the
gate, because it reads `auth.uid()`, and holds the service key only for
talking to Google.

Two refusals in it are worth keeping: a **removed** guardian cannot ring a
phone they no longer look after, which is the single worst thing this feature
could be used for; and a phone that never checked in returns no row rather
than a null token, so the sender cannot POST `to: null` and read the rejection
as a delivery failure.

`google-services.json` is committed and the **service account is not** —
`.gitignore` carries `*-firebase-adminsdk-*.json` so it cannot be added by
accident. It lives in Edge Function secrets as `FCM_SERVICE_ACCOUNT`.

The sending chain is **deployed and proven**, as of 2026-10-27:
`ring-phone` is ACTIVE with `verify_jwt`, the secret is set, and
`tool/verify_ring_function.py` walks it end to end against the live project.
It sends to a deliberately fake device token and reads the reply, because the
one thing the SQL gate cannot tell you is whether the sender works.

That is why the two failure modes carry different `reason` codes, and the
distinction is load-bearing rather than convenience: a service account that
cannot mint a token means *every ring for every family is failing*, while a
device token FCM rejects means *that one phone is unreachable*, which is
ordinary. Collapsed into one 502 — which is how it was first written — a
misconfigured sender looks exactly like a parent whose phone is off, forever,
and nobody goes looking. The verifier reads `sender_unconfigured` as a failure
and `INVALID_ARGUMENT` as success, which is the only way to tell them apart
from outside. `error` stays the one line a guardian reads.

### What is still missing

1. **The background wake-up.** `PushMessaging.messages()` is
   `FirebaseMessaging.onMessage`, which delivers only **while the app is in
   the foreground**. A launcher is in the foreground most of the time, but not
   with the screen off — and a phone in a bag in another room is the case this
   feature exists for. Closing it needs a background handler plus native code
   to bring the activity forward, and on Android 14 that route runs into
   `USE_FULL_SCREEN_INTENT`, which Play grants to calling and alarm apps.
   Unresolved, and unverifiable here.
2. **The guardian's button.** Deliberately not built yet. With (2) open it
   would ring only a phone whose screen is already on, which is the opposite
   of what the feature is for, and putting it on 돌봄 would be selling that.

So the feature is **plumbed and gated, not working**. Nothing on either screen
claims otherwise: 소리 울리기 is still `CareReadiness.planned` and sits in
돌봄's 준비 중 block.

## 폰에 있는 앱, and the two ways in

The six categories are *kinds* of app — the phone opens whichever dialer or
gallery its owner already uses. `AppCategory.installed` is a named package,
because a senior's 고스톱 or their bank has no category and never will have
one. It is the same argument 사람 버튼 rests on: **seniors do not fail at
opening apps, they fail at finding them**, and the app they most want is
rarely one of six kinds.

**No migration.** `app_type` has had `'installed_app'` in its check constraint
and a `package_name` column since Phase 4 — `05_DATA_MODEL` anticipated this
and nothing had ever written one, exactly as with `family_contact`.

**The list is read through a `<queries>` intent, not `QUERY_ALL_PACKAGES`.**
That permission is Play-restricted and its published list of acceptable uses
is device search, antivirus, file managers and browsers — **launchers are not
on it**, which was checked rather than assumed. An intent query needs no
declaration form, and six `<intent>` entries in this manifest already use
`<category>` the same way and open real apps on a real phone.

**The icon lives on the button, not on a channel.** Nothing a senior is
looking at may wait on a platform channel, and this is the slowest one in the
app: a home screen that asked for eighty icons at start-up would open with
blank tiles and fill in a beat later, every time. The bytes sit beside the
label in the saved settings, so drawing stays synchronous.

**The icon is never sent to the server**, which is the whole shape of the
feature. Sending it would hand the guardian a picture of what is installed on
their parent's phone — the thing the 위치 decision ruled out. `activeDevice`
and `homeAppsPayload` both leave it out, and `SeniorSettingsSync` puts the
local bytes **back** onto the rows that come down: without that, every resume
would replace the senior's 고스톱 logo with a grey glyph and leave it there.
Same rule as the device-status columns — *null means the other side could not
say, never that there is nothing.*

### Two ways in, because two different people are stuck

- **경로 1, the senior alone.** The hollow slot on 자세한 화면 → 어떤
  버튼인가요 → 폰에 있는 앱 → the list. Two presses from the home screen.
  That slot used to open 앱 설정 — a list of the buttons they already have,
  with 버튼 추가하기 at the bottom — so it took four screens and two of them
  existed only to be passed through. The step a senior gives up at is never
  the choosing; it is getting to the place where they can choose.
- **경로 2, the senior who cannot do even that.** The guardian places an
  **empty slot** from their own phone, and their parent presses it once and
  picks. The guardian is still never shown the list — they can create the
  slot without being shown what goes in it, which is what keeps the privacy
  property while removing the navigation.

`awaitingChoice` is that state and it adds **no field**: an `installed`
button with no package is one nobody has filled in, the same shape as a
contact with no number. The tile is drawn hollow, like the empty slot,
because the one thing it must not look like is an app — a senior who reads it
as one presses it, nothing opens, and they conclude the phone is broken. On
the guardian's row it says `부모님이 폰에서 고르시면 이름이 나와요`, and
renaming is disabled: the name becomes the app's own the moment they pick, so
anything written now is a label that turns into a lie.

`openHomeButton` and `addHomeButton` are shared by both home screens and both
entry points. The two screens had already grown identical copies of the tap
handler; a third branch in each is where they would have drifted.

## 앱 설정 has a way out that is a word

The only exit was the `←` in the top-left corner: small, in the hardest place
on the screen for a hand to reach, and a symbol rather than a word. A senior
who came to rename one button had to find it.

`첫 화면으로 가기` sits at the bottom now, and **it goes all the way home
rather than popping one screen.** There are two ways into this screen since
the hollow slot on 자세한 화면 started leading here, and popping would leave
half the visitors standing in 설정 with another exit to find. It is also what
makes the label true.

**Every change on this screen is already written** — `_write` saves to disk
the moment it is pressed. So the exit cannot be called 저장 or 완료, and the
line under it says `바꾸시면 바로 바뀌어요`: the change *already happened*,
rather than this button being what does it. The difference is not pedantry.
A button claiming to save makes the `←` the one that **loses** your work,
which is false, and a senior who backs out by accident would redo edits that
were never lost and learn to fear the corner.

`버튼 추가하기` moved into the list as its `footer` and is drawn **hollow**,
which settles two things at once: the guardian's half already learnt that a
pinned add button leaves a field of nothing between the last row and itself
and says nothing about where a new button lands; and hollow makes it the same
object as the 추가하기 slot on the home screen, which is the same act reached
another way. The filled terracotta is left to the exit, so the two largest
buttons on the screen are not the same colour.

## The phone's home-app chooser cannot be changed, so it is explained first

Pressing 첫 화면으로 정하기 opens Android's own `RoleManager` chooser, and
**no part of it is ours** — not the wording, not the order, and not which row
starts selected. It opens on whatever is the home app *now*, which is the
other one. That is deliberate on Android's side: an app that could pre-select
itself is how a launcher gets hijacked. Asked on a real phone whether ours
could come up already chosen, the answer is no, and there is no flag for it.

So the only thing left is what the senior knows before it appears, and until
2026-10-27 that was nothing: a system dialog in system language arrived with
no warning, radio already on the other app.

`HomeAppCoach` is said first, in all three places that open the chooser —
onboarding, 설정 → 첫 화면으로 정하기, and 사용하지 않기, which points the
**other way** and tells them to pick the app they had before.

**It names Samsung's buttons.** The first version named none, on the grounds
that other phones word them differently — true, and it left `오른쪽 아래를
눌러 주세요` for the overwhelming majority holding a Galaxy, where 변경 is
simply what the button says. Vague everywhere is worse than exact for almost
everyone when the reader is this one. The quiet last line covers the rest,
and it is worded as *a button saying something like that will do* rather than
as a second instruction.

**It is two steps, because Samsung's is**: the list comes first, and choosing
a row raises a second dialog with 현재 버전 유지 / 변경. A one-step
instruction strands them on that second dialog, which is where a senior who
has got this far is least able to guess.

**The result comes after the condition, and `그러면` joins them.** It opened
with `홈 버튼을 누르면 그 화면이 나옵니다`, stated as done — and pressing the
button before it changes nothing at all: Android's screen is next and a
person has to finish it. A senior who read it as already done closed the
system screen and found the phone unchanged, which reads as the app being
broken. Same fault as a button claiming to save what was already saved,
pointing the other way.

**Every line is measured, not counted.** `home_app_coach_test` lays the card
out at the real width with the app's own faces loaded and asks each
paragraph for its intrinsic width. Counting glyphs is not enough here, and
the first version proved it: `목록에서 「One UI 홈」을 누르고` is seventeen
characters — the length the consent cards settled on — and still ran 14px
past its box, because 「」 are full width and the latin letters are not. Three
lines wrapped, leaving `고` and `다.` alone on lines of their own, which is
the exact fault the consent cards exist to document.

This is not the screen that was removed for saying 첫 화면으로 정하기 three
times before doing what the row does on tap. A test holds that line: the step
has to contain `잘보이네` and must **not** contain the label of the row that
opened it.

## Back does nothing on the home screens

A launcher's home is the root. Without `PopScope(canPop: false)` the route
popped and the whole home **slid sideways out of view** — on a real phone,
watched. On the screen a phone *sits* on that reads as the app falling over,
and it leaves the senior somewhere they did not ask to be with no way back
they would know. Both homes carry it; `home_is_root_test.dart` fails if
either loses it, and also checks that a screen opened *off* the home still
closes, so the root refusing Back does not make the rest of the app a trap.

## The picker hides kinds the screen already has

Offering 전화 to a home screen that already has 전화 is offering a second
button that opens the same app — a duplicate the senior cannot tell from the
first, on the one screen they cannot fix themselves.

`AppCategoryStyle.repeatable` is the exception and it is two: **사람** and
**폰에 있는 앱**. A family has several people in it and a phone has eighty
apps, so hiding those after the first use would make both features one-shot.
Both halves pass what is already on the screen, because the guardian is
looking at the same home.

## Two buttons that each said the opposite

`원래 화면으로 돌아갈까요?` was answered by `그만두기` and `돌아가기`, and
**both read as the other one**. `그만두기` is the word in the row that opens
it — 잘보이네 사용하지 않기 — so it reads as the confirm; `돌아가기` in a
dialog reads as *go back*, which is the cancel. On the screen that hands a
senior their phone back.

It is `아니요, 그대로 쓸게요` and `네` now. The first cannot be mistaken for
a confirm under any reading; the second is the shortest thing on the card and
**deliberately the quieter of the two** — `seniorInkMuted`, not the
`seniorPrimary` that everywhere else in the app means *this is the thing to
do*. What is being offered here is giving up the home screen, and a
terracotta 네 beside a grey refusal is the app leaning on somebody to take
it.

**It is two cards, and the question is alone on the first.** It carried the
reassurance and the walkthrough as well, which is a wall of text at the
moment a senior is only deciding *whether*. What they are answering is one
sentence long; `HomeAppCoach` follows after 네, and the reassurance moved to
the row itself — `버튼과 글씨 크기는 그대로 있어요`, where it can stop someone
refusing out of fear. A card shown after they have already said 네 cannot do
that job.

The coach card's cancel is `아니요` rather than the `그만두기` the other
direction uses, for the same reason the pair above was rewritten: 그만두기 is
the row's own word — 잘보이네 사용하지 않기 — so on *this* card it reads as
the confirm.

The other pairs were left alone. `그만두기` beside `저장` is not ambiguous —
그만두기 only misreads where the screen itself is about stopping something.

## Conventions

- Tests come before implementation — see `.claude/skills/test-driven-development`.
- Never claim work passes without running the command and reading the output.
- Work on the branch assigned for the session; don't push to `main` directly.
