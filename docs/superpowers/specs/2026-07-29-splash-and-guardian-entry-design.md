# Splash And Guardian Entry — Design

**Status:** approved 2026-07-29
**Supersedes:** the first-screen section of `docs/claude-code/04_SCREEN_SPEC.md` and
step 1 of `docs/claude-code/03_USER_FLOWS.md`, both of which are updated to match.

## Goal

Replace the current role-split first screen with the uploaded design, and give the
guardian branch a real entry screen that argues for signing up instead of merely
listing steps.

Two screens plus one routing decision:

1. **Splash** — the senior's entry. Tapping the phone in the illustration starts
   the senior flow.
2. **Guardian start** — reached from the card at the bottom of the splash. Sells
   the product, then offers Kakao and Google sign-in.
3. **Launch gate** — decides, on every app start, whether the splash should be
   shown at all.

## Decisions

These were settled during brainstorming and are the reason the design departs
from the older spec documents.

| Question | Decision |
|---|---|
| Keep the large `시작하기` button? | No. The phone inside the illustration is the tap target. |
| What does the tap do? | Shows the "준비하고 있어요" state for ~0.5s, then navigates. |
| Where does the guardian card lead? | A full guardian-start screen, not a bottom sheet. |
| Sign up and log in as separate actions? | No. `~로 시작하기` covers both. |
| Which providers? | Kakao first, then Google. No email. |
| Name shown on the senior's child button | Guardian types it (so it can read "아들", not "김철수"). Recorded for Phase 5; not built here. |

### Why sign-up and log-in are merged

Social sign-in has no meaningful distinction between the two: the first tap
creates the account, later taps sign in. Offering `회원가입` alongside
`카카오로 시작하기` invents a decision the user cannot make correctly — someone
reinstalling the app has an account but does not know which control is theirs.
The uploaded design carried both; the `계정이 없으신가요? 회원가입` row and the
`시작하기` divider label are dropped.

Email sign-in is dropped for the same reason it was never in the older spec:
it reintroduces a password for an audience (40–60) that already has Kakao.

## Screen 1 — Splash

Route `/`. Replaces `RoleSplitScreen`.

**Background.** Vertical gradient `#FFFDF8 → #FDF6EA (46%) → #F6E8D5`, with two
soft radial washes: warm orange top-left, amber mid-right. Both are decorative
and must not intercept taps.

**Wordmark block**, centred, 78px from the top:
- `잘보이네` in Noto Serif KR 700, 41px, `#35291F`, letter-spacing −2px
- a 7px `#D93516` dot at the baseline's right
- below it, `크게 보고 쉽게 쓰는` at 15px 600 `#7A6450`, letter-spacing 2.4px,
  flanked by two 26×1px rules at 28% opacity

The tagline is a dangling modifier — it modifies the wordmark above it rather
than a noun of its own. Kept as-is: it reads as a caption in position, and the
alternative ("크게 보고 쉽게 쓰는 스마트폰") competes with the wordmark.

**Illustration.** `hand_phone.png` (360×740, transparent) anchored to the bottom,
covering the full width. A bottom scrim (250px, fading to the background colour)
keeps the guardian card legible over it.

**Tap target.** The phone's screen area inside the illustration — 57.6% wide,
54% tall, positioned at 20.2%/29.4% of the illustration box, 26px corner radius.
It holds two states:

- *idle* — a 104px `#D93516` circle with a tap-hand glyph, pulsing, with two
  expanding rings behind it; then `눌러보세요` at 38px 900 `#D93516`, then
  `스마트폰이 / 쉬워져요` at 26px 800 `#7A3D24`
- *entering* — three pulsing 9px dots, then `준비하고 있어요 / 잠시만 기다려 주세요`
  at 20px 700 `#7A3D24`

Tapping moves idle → entering, waits ~0.5s, then navigates to the screen-mode
choice. Repeat taps while entering are ignored.

The half-second is deliberate. Navigating instantly gives no feedback that the
tap registered, and this audience responds to that by tapping again.

**Guardian card**, pinned 34px from the bottom, 20px inset. Translucent
`rgba(255,253,248,.62)` over the scrim, 1.4px border, 18px radius. A 40px
outlined icon box, then `가족 및 보호자분들은` (12.5px 500 `#8A7460`) above
`여기를 눌러주세요` (18px 700 `#3A2E24`), then a chevron. Opens screen 2.

## Screen 2 — Guardian start

Route `/guardian-start`, replacing the current `GuardianLoginPlaceholder` as the
destination of the guardian card. Scrolls; the content is taller than a small
phone.

Back arrow top-left returns to the splash.

**Header.** A 5px `#C4451F` dot beside `보호자 시작하기` (12px 600 `#8C8578`,
letter-spacing 2.2px). Below, the title in Noto Serif KR 700, 29px:
`부모님께 이런 걸 / 해드릴 수 있어요`. Then `연결은 몇 분이면 끝납니다.`
at 14.5px 500 `#7C7568`.

**Three benefit cards**, 18px radius, `rgba(255,255,255,.72)` on a `#EDE7DC`
border, each with a numbered 30px circle:

1. **부모님을 대신해 필요한 앱을 관리해 드릴 수 있어요**
   홈 화면 앱과 버튼 색을 원격으로 정리합니다
2. **부모님과 쉽게 메시지와 사진을 주고받을 수 있어요**
   큰 글씨로 바로 보이는 가족 메시지
3. **부모님의 폰 상태를 확인할 수 있어요**
   배터리 · 소리 · 인터넷 연결을 한눈에

Titles wrap to two lines at this width. That is accepted — the fuller phrasing
carries more warmth than a one-line version would.

Each card fades up from 12px below its resting position, staggered 0.05 / 0.12 /
0.19s, so the eye is walked from 1 to 3.

**Sign-in.** A plain hairline divider (no label), then:

- `카카오로 시작하기` — `#FEE500`, text `#191600`, 56px tall, 16px radius
- `구글로 시작하기` — white, 1.4px `#E3DCCE` border

Kakao is first because effectively every Korean 40–60-year-old has one, and
Google sign-in more often stalls on "which account was mine".

Below, centred at 11.5px `#A79F92`:
`시작하면 서비스 이용약관과 / 개인정보 처리방침에 동의하게 됩니다`

Consent copy is legally required at sign-up in Korea and was missing from the
project docs.

**Behaviour now.** Neither provider is wired — Supabase auth is Phase 4. Both
buttons navigate to the existing guardian login placeholder. The buttons exist
so the layout is real and the wiring is a later, contained change.

Benefits 2 and 3 describe features that do not exist yet (family messaging,
phone status). They are promises this screen makes on the product's behalf, and
they stay unbuilt until Phases 3–4.

## Screen 3 — Launch gate

Route `/` becomes a decision rather than a screen:

```
app start
  ├─ senior screen mode saved?   → that home (easy or detailed)
  ├─ guardian signed in?         → guardian dashboard
  └─ neither                     → splash
```

This matters most for the senior: the app is meant to become the phone's
launcher, so pressing Home must not land on a splash screen.

Neither condition can be evaluated yet — screen-mode persistence is Phase 2 and
sign-in state is Phase 4. The gate is built now with both checks stubbed to
false, so it always falls through to the splash and today's behaviour is
unchanged. Building the seam now avoids reworking navigation twice.

## Assets and fonts

`hand_phone.png` is extracted from the uploaded bundle and added under
`assets/images/`.

The design calls for two families. Android's default Korean face is already Noto
Sans KR, so body text needs no bundled font. Only the two serif runs — the
`잘보이네` wordmark and the guardian-start title — need Noto Serif KR, and
bundling a full Korean serif for them costs several megabytes.

Decision: use the system font everywhere for this change, and treat the serif
wordmark as a follow-up where the font can be subset to the characters actually
used. Layout, colour, and spacing are implemented to spec now; the wordmark's
typeface is the one deferred detail.

## Testing

Widget tests, written before each screen:

- splash renders wordmark, tagline, tap prompt, and guardian card
- tapping the phone area shows the entering state and then navigates
- a second tap during the entering state does not navigate twice
- the guardian card opens the guardian-start screen
- guardian start renders title, all three benefits, and both providers
- guardian start does **not** render a separate sign-up control
- back returns to the splash
- the launch gate falls through to the splash while both checks are false

The two existing first-screen tests in `test/widget_test.dart` assert the old
`시작하기` button and are rewritten, not deleted — the screen still has to render
its name and still has to navigate onward.

## Out of scope

Recorded so they are not lost, and deliberately not built here:

- **Pairing (Phase 5).** Two paths were drafted: inviting a parent by SMS with a
  guardian ID in the link, and entering a 4-digit code. Three constraints found
  during design, to be written up separately before that phase:
  1. Install-time auto-pairing needs Google Play's install referrer, so it only
     works for Play Store installs and must fall back to the 4-digit code.
  2. An app cannot send SMS silently; it can only open the SMS app with the
     message prefilled. The flow therefore cannot claim "문자 발송 완료".
  3. A contact picked from the guardian's phone yields the *parent's* saved
     name, not the child's. The child's name shown on the senior's home must be
     typed by the guardian.
- Kakao and Google sign-in wiring (Phase 4).
- Making the app the actual Android launcher.
- `applicationId` is still `com.example.app`. *(Settled 2026-10-26: it is
  `com.jalboine.app`, and `application_id_test.dart` holds Dart and Gradle
  to the same value.)*
