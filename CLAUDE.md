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
- 보이스피싱 의심 전화 — PRD excludes call-content analysis; the feature is
  scoped to numbers absent from the contact list and is named for that.
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

- **The hero never reassures on no evidence.** It shows the time the parent's
  phone last checked in, or it says there is none — `아직 / 연결되기 전이에요`.
  The server knows a phone connected; it does not know the parent is well.
  This is the most comforting-looking object on the screen, which is why it is
  the one that must not round a missing check-in up. Same rule that took the
  mocked `배터리 72%` off this tab. There is a test for the empty case.
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

The parts are shared, in `presentation/widgets/guardian_surfaces.dart`:
`GuardianGround`, `GuardianCard`, `GuardianActionCard`, `GuardianFact`,
`GuardianPrimaryButton` and `GuardianHeading`. 홈 and 홈 화면 are both built
from them. The one filled button on the half wears the **hero's gradient**
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
