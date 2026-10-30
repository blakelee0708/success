# Phase Plan For Claude Code

## Important Instruction
Do not implement all phases at once. Each phase must be implemented, reviewed, and tested independently.

## Phase 0: Project Setup
Output:
- Flutter project structure
- routing
- theme base
- local state management choice
- mock repositories

Acceptance:
- app runs
- first screen renders
- no Supabase required

## Phase 1: 피보호자 런처
Output:
- role split first screen
- senior onboarding
- screen mode choice
- easy home
- detailed home
- SOS phone handoff
- return-to-original placeholder

Acceptance:
- user can choose mode
- app shows correct default buttons
- no extra onboarding questions
- SOS opens phone intent, does not auto-call

## Phase 2: Local Settings
Output:
- home apps local model
- add/remove/reorder
- rename
- button color change
- font size change
- screen mode persistence

Acceptance:
- settings survive app restart
- easy and detailed mode render differently
- app buttons are stable across states

## Phase 3: Guardian Dashboard UI
Output:
- guardian login placeholder
- dashboard shell
- parent status card
- home management tab
- message tab
- care tab
- settings tab
- family plan parent switcher UI

Acceptance:
- dashboard can be navigated without backend
- parent switcher renders in mock mode
- empty/loading/error/offline states exist

## Phase 4: Supabase Integration
Output:
- schema migration
- auth integration for guardian
- repositories
- senior profile creation
- senior device creation
- guardian-senior linking

Acceptance:
- guardian can login
- senior profile can be linked
- home app settings sync when parent phone is online

## Phase 5: Pairing And Recovery
Output:
- 4-digit pairing code
- invite link
- recovery link/code
- reconnect parent phone
- old device deactivation
- primary guardian change
- family guardian invite

Acceptance:
- reinstall can restore existing senior profile
- family guardian invite is free
- primary guardian change requires senior phone approval

두 경로가 있다.

경로 A — 보호자가 부모님께 설치 권유:
1. 연락처에서 부모님 선택
2. 설치 링크가 담긴 문자 내용을 미리 채워 문자 앱을 연다
3. 부모님이 설치하면 링크에 담긴 보호자 ID로 자동 연결된다
   - 2026-10-30 현재 이 자동 연결은 만들지 않았다. 출시 전에는 연결 번호
     문자 한 통만 보내고 부모님이 번호를 입력한다. 자동 연결은 출시 후
     업데이트로 넣는다 (새로 설치하는 폰은 항상 최신 버전을 받으므로 충분하다)

경로 B — 부모님이 알려준 4자리 코드 입력:
1. 부모님 폰에 뜬 4자리 코드를 보호자가 입력
2. 코드로는 전화번호를 알 수 없으므로 번호를 추가로 받는다

설계 시 반영해야 할 제약 3가지:

- 설치 직후 자동 연결은 Google Play install referrer에 의존한다. 플레이 스토어를
  거친 설치에서만 동작하므로, 실패 시 경로 B로 떨어지는 길이 반드시 있어야 한다.
- 앱이 문자를 직접 보낼 수 없다. 문자 앱에 내용을 채워 넘기는 것까지만 가능하며,
  실제 발송 여부를 앱이 알 수 없으므로 `문자 발송 완료`라고 표시하면 안 된다.
  SOS의 전화 처리와 같은 원칙이다.
- 보호자 연락처에서 고른 이름은 부모님 이름이다. 어르신 홈 화면의 자녀 버튼과
  SOS에 쓸 자녀 이름은 보호자가 직접 입력받는다. 어르신이 알아보실 호칭
  (`아들`)이 계정 본명(`김철수`)보다 낫다.

## Phase 6: Paid Features
Output:
- subscription model
- care plan
- family plan
- senior consent flow
- refund state for refusal
- 5-minute background sync interface
- location interface
- unknown-contact call alert interface
- app install alert interface

Acceptance:
- paid features do not activate before senior consent
- refusal results in refunded subscription state
- family plan unlocks 2+ parent management

