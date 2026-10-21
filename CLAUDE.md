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

All six numbered phases are now done. What is left is not a phase: a real
`applicationId`, an upload key, Play Billing, the native side of the four
watchers, 더 보기, the 메시지 탭, and a run on a real phone.

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

### Guardian sign-in is email-only

Kakao and Google have no OAuth client configured on the project, and only the
repo owner can add one. `GuardianStartScreen` still leads with both buttons —
that is a deliberate design decision, see the spec — but with a project attached
they now open a sheet saying the provider is being prepared and offer the email
route at `/guardian-login`. With no project attached they open the dashboard as
they did in Phase 3. Email sign-up needs confirmation (`mailer_autoconfirm` is
false), so signing up returns no session and the screen says to check the inbox.

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

**It cannot be triggered yet.** Remote ringing needs FCM, FCM needs a Firebase
project, and a Firebase project needs an `applicationId` that is not
`com.example.app`. The screen, the controller, the timeout and the dismissal
are built and tested; the trigger is the missing half.

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
  is not a store build — a real upload key, and an `applicationId` that is not
  `com.example.app`, are both still to do.

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

## Conventions

- Tests come before implementation — see `.claude/skills/test-driven-development`.
- Never claim work passes without running the command and reading the output.
- Work on the branch assigned for the session; don't push to `main` directly.
