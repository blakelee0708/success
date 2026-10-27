# 서울 프로젝트로 옮기기 - 런북

2026-10-27에 쓴 것이다. 이 문서는 PRD가 아니라 작업 지시서다. 다 끝나면
지워도 된다.

새 프로젝트 ref는 **`handkezisjufyyumpuma`** 이고, 싱가포르
`jnmvhdmxzonngqyicelx`는 새 쪽이 전부 동작하는 것을 확인할 때까지만 둔다.

## 이제 설정할 것은 토큰 하나다

**ref는 저장소에 있다.** `supabase/project.ref`에 `handkezisjufyyumpuma`가
적혀 있고, 세션 시작 훅이 그것을 읽어 `SUPABASE_PROJECT_REF`로 내보낸다.
비밀이 아니다 - 대시보드 주소에도, APK의 `SUPABASE_URL`에도,
`site/reset.html` 소스에도 들어 있는 값이다. 저장소에 두면 환경변수가
낡아도 `tool/` 스크립트 아홉 개가 전부 올바른 프로젝트를 가리킨다. 그
어긋남이 2026-10-27에 세션 하나를 통째로 썼다.

그래서 환경 설정에 넣을 것은 **`SUPABASE_ACCESS_TOKEN` 하나뿐이다.**

### 훅이 세션 처음에 연동 상태를 말한다

`.claude/hooks/session-start.sh`가 Flutter를 깔고 나서 Management API에
프로젝트를 한 번 물어보고, 네 가지 중 하나를 출력한다. 중간까지 가서
발견하는 대신 맨 위에서 알게 하는 것이 요점이다. **어느 경우에도 세션을
실패시키지는 않는다** - Supabase에 닿지 못해도 테스트와 화면 작업은 전부
할 수 있고, 시작을 막는 쪽이 더 나쁘다.

| 출력 | 뜻 |
|---|---|
| `CONNECTED. region: ap-northeast-2` | 정상 |
| `CONNECTED` + region 경고 | 프로젝트가 서울이 아니다. `site/privacy.html`이 대한민국이라고 적어 두었으므로 둘 중 하나는 고쳐야 한다 |
| `NOT CONNECTED: 403` | 프로젝트는 있는데 **이 토큰의 계정이 볼 수 없다.** 그 프로젝트를 가진 계정에서 토큰을 만들어야 한다 |
| `NOT CONNECTED: no SUPABASE_ACCESS_TOKEN` | 환경에 토큰이 없다 |

네 경로 모두 손으로 돌려 확인했다.

## 2026-10-27, 스키마는 들어갔다

위의 토큰 문제는 해결됐다. 세션 시작 훅이
`CONNECTED. region: ap-northeast-2`를 출력하고, 13개가 전부 적용됐고 다섯
숫자가 전부 맞는다. 남은 것은 **오너가 대시보드에서 해야 하는 두 가지**이고,
그 두 가지가 검증 스크립트 8개와 메일 템플릿 전부를 막고 있다.

### 막혔던 것 1. `cron` 스키마를 미리 만드는 것이 바로 그 원인이었다

`tool/apply_migrations.py`의 사전 단계가 `create schema if not exists cron`을
불렀고, 그것이 `20261021030000_care_alerts.sql`을 42P06
`schema "cron" already exists`로 멈춰 세웠다. **`create extension ... with
schema cron`은 그 스키마를 직접 만든다.** 미리 있는 것을 원하지 않는다. 즉
사전 단계의 전제가 거꾸로였고, 막으려던 파일을 자기가 막았다.

지금은 반대로 간다. pg_cron이 설치돼 있지 않으면 빈 `cron` 스키마를
지운다. RESTRICT로 지우므로 안에 무언가 들어 있는 스키마는 거부하고 파괴하지
않으며, pg_cron이 이미 있는 프로젝트는 손대지 않는다.

### 막혔던 것 2. 함수가 37이 아니라 38로 세어진다

새 프로젝트에는 `public`에 `rls_auto_enable`이 기본으로 들어 있다. `public`에
테이블이 만들어지면 RLS를 켜 주는 Supabase 쪽 이벤트 트리거 함수이고,
우리 마이그레이션 것이 아니다. 비어 있던 시점에 `--check`가 이미
`functions: 1`을 보고했다. 37 더하기 1이 38이다.

2026-10-27 기준값을 읽어 온 그 프로젝트는 이 함수가 생기기 전에 만들어졌다.
그래서 숫자를 38로 올리는 대신 **세는 쪽을 우리 스키마로 한정했다** -
이벤트 트리거를 돌려주는 함수는 세지 않는다. 13개 가운데 이벤트 트리거를
만드는 파일은 없으므로 이 필터가 우리 것을 가릴 수는 없다.

### 지금 막혀 있는 것. 익명 로그인 하나가 8개를 전부 멈춘다

`verify_supabase_*.py` **8개가 전부** 같은 자리에서 멈춘다.

```
422 anonymous_provider_disabled: Anonymous sign-ins are disabled
```

여덟 개가 모두 `device()`로 어르신 폰을 하나 만들고 시작하기 때문이다.
그래서 이것은 8개 가운데 몇 개가 아니라 **8개 전부**이고, 아래 2번의
Anonymous sign-ins을 켜는 것 말고 돌아갈 길이 없다. 에이전트 환경에서는
`external_anonymous_users_enabled` PATCH가 거부된다.

### 메일 템플릿은 SMTP보다 먼저 넣을 수 없다

`tool/apply_auth_templates.py`가 400을 받는다.

```
Email template modification is not available for free tier projects
using the default email provider.
```

**순서가 이 문서에 거꾸로 적혀 있었다.** 템플릿은 에이전트가 넣을 수 있는
것으로, SMTP는 오너가 하는 것으로 나눠 적었는데, 템플릿 쓰기 자체가 커스텀
SMTP가 설정돼 있을 것을 요구한다. 싱가포르에서 통과한 이유는 그 프로젝트에
SMTP가 이미 들어가 있었기 때문이다. 새 프로젝트에서는 **오너가 Resend SMTP를
넣은 다음에** 이 스크립트를 돌린다.

## 왜 2026-10-27 세션에서 끝내지 못했는지

**새 프로젝트가 다른 Supabase 계정에 있었다.** 그 세션의
`SUPABASE_ACCESS_TOKEN`으로 `GET /v1/projects/handkezisjufyyumpuma`를 부르면
403이 돌아왔다. 404가 아니라 403이라는 것이 중요하다 - 없는 게 아니라 권한이
없다는 뜻이고, 실제로 `https://handkezisjufyyumpuma.supabase.co`는 살아서
401을 돌려준다.

토큰은 **대시보드에서 그 프로젝트가 보이는 계정으로 로그인한 상태에서**
만들어야 한다. 그리고 환경변수는 실행 중인 세션에 반영되지 않으므로,
넣은 뒤에는 **새 세션**을 열어야 한다.

비밀값은 채팅에 붙여넣지 않는다. 환경 설정의 Network secrets(구버전 앱에서는
API credentials)에 넣는다.

## 옮길 데이터는 없다

2026-10-27에 싱가포르 프로젝트의 9개 테이블을 전부 세어 봤다. **아홉 개가
모두 0줄이다.** `auth.users`에는 1줄이 있고 그것은 메일 사슬을 확인할 때 만든
오너 본인 계정이다.

그래서 이 작업은 데이터 이전이 아니라 **스키마를 새로 넣는 일**이다. 내보낼
것도, 맞춰 넣을 것도, 순서를 맞출 외래 키도 없다. 새 쪽이 동작하는 것을
확인하면 싱가포르는 그냥 지워도 된다.

## 검증 스크립트는 지금 전부 통과한다

8개를 2026-10-27에 싱가포르에 돌려 **전부 통과**했고, 스스로 만든 데이터를
스스로 지웠다 (실행 후 9개 테이블이 다시 0줄).

이 기준선을 적어 두는 이유는, 새 프로젝트에서 어느 하나가 실패하면 그것이
스크립트 문제가 아니라 **스키마 문제**라는 뜻이 되기 때문이다. 다음 세션이
스크립트를 의심하며 시간을 쓰지 않도록.

## 1. 스키마 넣기

한 줄이다.

```bash
export SSL_CERT_FILE=/root/.ccr/ca-bundle.crt
python3 tool/apply_migrations.py
```

`tool/apply_migrations.py`가 13개를 파일 이름 순서대로 넣고, 끝나면 아래 다섯
숫자를 세어 대조까지 한다. **2026-10-27에 서울 프로젝트에 돌려 13개가 전부
적용되고 다섯 숫자가 전부 맞았다.** 셸 루프를 쓰지 않는 이유는 세 가지다.

- **테이블이 이미 있는 프로젝트에서는 거부한다.** `--force` 없이는 돌지
  않는다. `create table`은 `if not exists`가 아니라서 중간에 실패하고 뒤쪽이
  통째로 안 들어간 상태가 되는데, 그 상태는 나중에 아무도 진단하지 못한다.
- **빈 `cron` 스키마를 먼저 치운다.** `20261021030000_care_alerts.sql`이
  `create extension if not exists pg_cron with schema cron`을 부르고,
  `create extension`은 그 스키마를 **직접 만든다.** 미리 있으면 42P06으로
  실패한다. 이 자리가 새 프로젝트를 멈춰 세울 후보 1순위였던 것은 맞지만
  이유가 반대였고, 실제로 그렇게 한 번 멈췄다. 자세한 것은 위의
  '막혔던 것 1'에 있다.
- **끝나고 센다.** 마이그레이션은 2xx를 돌려주고도 다음 것이 기대하는 것을
  만들어 두지 않을 수 있다.

읽기만 하려면 `--check`를 붙인다. 두 경로 모두 2026-10-27에 싱가포르에
돌려서 확인했다 - `--check`는 다섯 숫자가 전부 맞고, 플래그 없이는 테이블
9개를 보고 거부한다.

### 대조

싱가포르에서 2026-10-27에 직접 센 값이다. 기억이 아니라 쿼리 결과다.

| | |
|---|---|
| 테이블 (public) | 9 |
| 함수 (public) | 37 (이벤트 트리거 함수는 세지 않는다. 위의 '막혔던 것 2') |
| RLS 정책 (public) | 14 |
| cron job | 1 (`check-unused-phones`, `7 0 * * *`) |
| 확장 | 6 (`pg_cron`, `pg_stat_statements`, `pgcrypto`, `plpgsql`, `supabase_vault`, `uuid-ossp`) |

```sql
select
 (select count(*) from pg_tables where schemaname='public') as tables,
 (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public') as functions,
 (select count(*) from pg_policies where schemaname='public') as policies,
 (select count(*) from pg_extension) as extensions;
```

확장 6개 가운데 마이그레이션이 만드는 것은 `pg_cron` 하나뿐이고, 나머지는
새 Supabase 프로젝트에 기본으로 들어 있다. 숫자가 6이 아니면 빠진 쪽을
확인한다.

### 검증 스크립트

`verify_supabase_*.py`는 **6개가 아니라 8개**다. 싱가포르에서 전부 통과하는
것을 위에서 확인해 두었다.

**서울에서도 8개 전부 통과했다.** 2026-10-27, 오너가 Anonymous sign-ins을
켠 직후다. 각자 만든 데이터를 스스로 지웠고, 끝난 뒤 다섯 숫자가 다시 전부
맞는다.

익명 로그인을 켜기 전에 돌리면 8개가 전부 같은 자리에서 422
`anonymous_provider_disabled`로 멈춘다. 스키마 문제가 아니다.

```bash
export SSL_CERT_FILE=/root/.ccr/ca-bundle.crt
for s in phase4 phase5 phase6 messages presence roster alerts ring; do
  echo "== $s"; python3 "tool/verify_supabase_$s.py" || break
done
```

CA 번들과 기본값이 아닌 `User-Agent` 없이는 에이전트 프록시가 파이썬을
403으로 막는다. `tool/verify_ring_function.py`는 아홉 번째이고, Edge
Function을 새 프로젝트에 배포한 **뒤에** 돌린다.

### 한글 메일 템플릿

```bash
python3 tool/apply_auth_templates.py
```

**이 스크립트가 생긴 이유는 그 문구가 다른 데 없었기 때문이다.** 한글 제목과
본문이 싱가포르 프로젝트의 auth 설정에만 있었고 저장소에는 없었다. 그 프로젝트를
지우면 사라지고, 아무도 모른 채로 보호자가 재설정을 요청했을 때 영어 기본값이
나갔을 것이다. 이제 문구가 파일 안에 있다.

재설정 한 쌍과 가입 확인 한 쌍, 넷을 넣고 **플래그를 읽어서 확인한다.** 2xx로
끝내지 않는 것이 요점이다 - 저장된 본문은 플래그가 true일 때만 쓰이고, false인
채로 한글 본문이 앉아 있으면 영어 기본값이 나가는데 아무 신호도 없다. 플래그가
false면 스크립트가 실패하면서 대시보드 Emails에서 그 템플릿을 열어 저장하라고
말한다.

2026-10-27에 싱가포르에 돌려 9개 검사 전부 통과했다 (같은 값을 다시 쓰는
것이므로 아무것도 바뀌지 않는다).

## 2. 오너가 대시보드에서 해야 하는 것

에이전트 환경은 `/config/auth` PATCH를 막는다 - autoconfirm은 보안 완화로,
allow-list는 분류기가 아예 거부한다. 그래서 아래는 사람이 한다.

**싱가포르 프로젝트의 값이 전부 정답이다.** 2026-10-27에 실제로 읽은
것이므로 추측할 필요가 없다. 같은 값을 새 프로젝트에 넣으면 된다.

이 표에서 **두 줄이 다른 작업을 막고 있다.** Anonymous sign-ins는 검증
스크립트 8개 전부를, SMTP 네 줄은 한글 메일 템플릿을 막는다. 나머지는
그 두 가지를 끝낸 뒤에 해도 된다.

| 설정 | 넣을 값 |
|---|---|
| **Anonymous sign-ins** | **켜기** |
| Confirm email | **끄기** |
| SMTP host | `smtp.resend.com` |
| SMTP port | `465` |
| SMTP user | `resend` |
| SMTP pass | Resend API 키 |
| SMTP sender | `noreply@jalboine.com` |
| SMTP sender name | `잘보이네` |
| Email rate limit | `30` / hour |
| Kakao | Enabled + Client ID(REST API 키) + Client Secret + **Allow users without an email 켜기** |

**익명 로그인이 가장 중요하다.** 빠뜨리면 어르신 폰이 하나도 연결되지 않는다.
어르신에게는 계정이 없고, `senior_devices.auth_user_id`가 익명 사용자를
그 프로필에 연결하는 유일한 고리다.

카카오 Client ID와 Secret은 싱가포르 프로젝트의 auth 설정
(`external_kakao_client_id`, `external_kakao_secret`)에 그대로 들어 있으니
거기서 복사한다. 이 문서에는 적지 않는다 - 시크릿은 저장소에 들어가지
않는다. `Allow users without an email`은 API 이름이
`external_kakao_email_optional`이고 싱가포르에서 이미 `true`다. 카카오에서
`account_email`을 받으려면 비즈 앱 전환이 필요한데 받지 않기로 했고,
`guardian_accounts.email`이 null을 허용하고 `ensure_guardian_account`가
coalesce로 처리하므로 이메일 없이도 계정이 만들어진다.

### Redirect URLs

두 개를 `uri_allow_list`에 넣는다.

| | |
|---|---|
| `https://app.jalboine.com/reset.html` | 비밀번호 재설정 링크가 도착하는 자리 |
| `com.jalboine.app://login-callback` | 카카오·구글 로그인 딥링크 |

예전 값 `https://jdnnetwork.github.io/success/reset.html`은 버린다. 저장소가
옮겨져 더 이상 존재하지 않는 주소다.

`site_url`은 `http://localhost:3000`으로 두어도 되지만 **그것은 Confirm
email이 꺼져 있는 동안만 안전하다.** 아무것도 그 주소를 거치지 않기 때문이다.
확인 메일을 다시 켜면 같은 순간에 `site/index.html` 주소를 가리키게 해야
한다.

### 메일 템플릿 - 끝났다, 대시보드에서 할 것이 없다

**완료.** 2026-10-27에 서울 프로젝트에서 9개 검사 전부 통과했다. 다시
돌려도 같은 값을 쓰므로 아무것도 바뀌지 않는다.

두 가지를 알아 두면 된다.

**SMTP가 먼저다.** 무료 플랜에서 기본 발송자를 쓰는 동안은 템플릿 수정
자체가 400으로 거부된다. 그래서 이 스크립트가 통과한다는 것은 커스텀 SMTP가
제대로 들어갔다는 증거도 된다 - 따로 테스트할 것이 없다.

**플래그를 같은 호출에 같이 보내야 한다.** 내용 필드는
`mailer_subjects_custom_contents`와 `mailer_templates_custom_contents`의
해당 키에 걸려 있다. 플래그가 `false`인 채로 `mailer_subjects_recovery`를
보내면 API가 **200을 돌려주고 아무것도 저장하지 않는다.** 이 스크립트가
잡으려고 만들어진 바로 그 모양의 실패다. SMTP를 넣은 직후에 실제로 그렇게
됐다: PATCH는 200, 읽어 보면 영어, 플래그는 전부 false.

싱가포르에서 통과했던 이유는 그 프로젝트의 플래그가 이미 대시보드에서
켜져 있었기 때문이다. 새 프로젝트는 전부 false로 시작한다.

이제 스크립트가 플래그를 같이 보낸다. 각 객체의 다른 키는 읽어서 그대로
돌려주고 자기 네 개만 true로 바꾼다. **그래서 오너가 대시보드 Emails에서
템플릿을 열어 저장할 필요가 없다.** 예전 안내는 그렇게 적혀 있었는데
필요 없는 단계였다.

## CI 의 reset.html 검사는 한 번도 통과한 적이 없다

2026-10-27에 확인했다. 이 검사가 들어온 커밋 이후 run 80, 81, 82, 83, 84가
전부 같은 줄에서 실패했다. 그 사이 `site/reset.html`은 싱가포르였다가
서울로 바뀌었고 **양쪽 다 실패했다.** 즉 `SUPABASE_URL` 시크릿이 두
프로젝트 어느 쪽도 아니다.

진단 출력을 붙인 뒤 시크릿에 대해 알게 된 것은 이것이 전부다.

| | |
|---|---|
| 길이 | 다듬은 뒤 40자 |
| 모양 | `https://`로 시작하고 `.supabase.co`로 끝난다 |
| 값 | 서울도 싱가포르도 아니다 |

**길이로는 더 좁힐 수 없다.** Supabase ref는 모두 20자이므로 모든 프로젝트
주소가 정확히 40자다. 그래서 남는 가능성은 두 가지이고, 고치는 방법은
같다. 다른 프로젝트를 가리키고 있거나, ref 한 글자가 잘못 적혔거나다.
20자 ref의 오타도 40자이고 모양도 멀쩡해 보인다.

이 환경의 토큰은 `projects_read`가 없어서 프로젝트 목록을 볼 수 없다.
그래서 어느 프로젝트인지는 밖에서 알아낼 수 없고, 알아낼 필요도 없다.
오너가 저장소 시크릿에 아래 값을 **다시 입력하면** 된다.

```
SUPABASE_URL                https://handkezisjufyyumpuma.supabase.co
SUPABASE_PUBLISHABLE_KEY    site/reset.html 의 sb_publishable_ 값과 같은 것
```

https://github.com/blakelee0708/success/settings/secrets/actions

키는 `anon`이라고 적힌 긴 JWT가 아니라 짧은 `sb_publishable_` 쪽이다. 한
프로젝트에 두 형식이 다 있으니 틀리기 쉽고, 검사가 그 둘을 구분해서
말해 준다.

### 검사가 이제 스스로 이유를 말한다

예전에는 값을 하나도 출력하지 않았다. 키에 대해서는 맞는 판단이지만 URL
까지 가리면 영구히 빨간 검사가 되고 원인을 볼 방법이 없다. 지금은 비교
전에 앞뒤 공백과 개행을 떼어 내고(붙여넣기할 때 끝에 개행이 붙는 것이 같은
프로젝트를 가리키면서 어긋나는 가장 흔한 경로다), 실패할 때 페이지 자신의
값과 시크릿의 모양을 출력한다. 시크릿 자체는 출력하지 않는다. 여덟 경로를
손으로 돌려 확인했다.

## 3. 주소와 키 교체

| 어디 | 무엇 | 상태 |
|---|---|---|
| `lib/data/remote/guardian_auth_repository.dart` | `passwordResetRedirect` | **완료** - `https://app.jalboine.com/reset.html` |
| `site/reset.html` | `SUPABASE_URL`과 `PUBLISHABLE` | **완료** - 서울, 키는 Management API 에서 읽었다. 표시도 v3 |
| CI 저장소 시크릿 | `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` | 남음 (오너). 위의 '한 번도 통과한 적이 없다' |
| 카카오 콘솔 | Redirect URI를 새 Supabase 주소로 | 남음 (오너) |
| Edge Function | `ring-phone` 재배포 + `FCM_SERVICE_ACCOUNT` 시크릿 | 남음 |
| 한글 메일 템플릿 | `tool/apply_auth_templates.py` | **완료** - 9개 검사 통과, 플래그까지 true |

**`site/reset.html`의 두 값은 같이 바꿔야 한다.** URL만 바꾸고 키를 두면
그 페이지는 조용히 실패한다 - 비밀번호를 잊은 보호자가 다시 들어올 유일한
길이고, 실패가 실패처럼 보이지도 않는 페이지다. 새 URL은
`https://handkezisjufyyumpuma.supabase.co`이고 publishable 키는 새 프로젝트의
API 설정에서 읽어야 한다. 그 키가 손에 들어오는 세션에서 한 번에 바꾼다.
바꾸고 나면 페이지 아래 `v2` 표시도 `v3`으로 올려, 폰이 캐시를 들고 있는
것과 실제로 고장난 것을 눈으로 가를 수 있게 한다.

**이제 잊어버릴 수 없다.** `.github/workflows/android.yml`의 `check` 잡이
`site/reset.html`의 URL과 키를 CI 시크릿과 대조한다. APK는 빌드 때
`--dart-define`으로 프로젝트를 받고 재설정 페이지는 소스에 박아 둔 정적
파일이라 둘이 서로를 볼 수 없는데, 어긋나는 방식이 최악이다 - APK는 A
프로젝트로 로그인시키고, 재설정 메일이 가고, 페이지는 그 토큰을 B 프로젝트에
쓴다. B는 그 계정을 본 적이 없으니 보호자는 링크가 잘못됐다는 말을 듣고,
잊은 계정으로 돌아갈 유일한 길이 아무 기록도 없이 닫힌다.

그래서 **시크릿을 새 프로젝트로 바꾸는 순간 CI가 빨개진다.** 그것이 의도다.
`reset.html`을 같이 고치라는 신호다. 시크릿이 비어 있으면 (키 없는 APK는
어차피 서버에 닿지 않으므로) 검사를 건너뛴다. 네 경로를 모두 손으로
돌려 확인했다: 일치, 프로젝트 불일치, 키만 불일치, 시크릿 없음.

## 4. GitHub Pages - 거의 끝났다

2026-10-27 기준으로 **Source, 브랜치 규칙, 커스텀 도메인 세 가지가 모두
되어 있다.** 아래 목록은 그 전에 쓴 것이다.

확인하는 방법은 Pages 설정 화면이 아니라 **배포 로그**다. 에이전트는 Pages
API에 손이 닿지 않지만, `pages.yml`이 `steps.deployment.outputs.page_url`을
출력하므로 GitHub이 스스로 계산한 주소를 읽을 수 있다. 워크플로를
`workflow_dispatch`로 한 번 돌리면 나온다.

| 로그에 나온 값 | 뜻 |
|---|---|
| `https://app.jalboine.com/` | 전부 끝났다 |
| `http://app.jalboine.com/` | 도메인은 붙었고 **Enforce HTTPS가 꺼져 있다** |
| `https://blakelee0708.github.io/success/` | 커스텀 도메인이 안 붙었다 |

**남은 것은 Enforce HTTPS 하나다.** 19:05 배포가 `http://`로 보고했다.
`passwordResetRedirect`가 `https://app.jalboine.com/reset.html`이므로,
인증서가 없으면 보호자가 그 링크에서 TLS 오류를 본다. 잊은 계정으로 돌아갈
유일한 길이다. 체크박스가 회색이면 인증서 발급이 아직 끝나지 않은 것이고,
켤 수 있게 되면 켠다.

## 4-1. 그 전에 적어 둔 목록

저장소가 `jdnnetwork/success`에서 `blakelee0708/success`로 옮겨졌고 설정이
따라오지 않았다. **에이전트는 Pages API에 손이 닿지 않는다** - 프록시가
`/repos/{owner}/{repo}/pages`를 403으로 막고, `github.io`와
`docs.github.com`도 막혀 있어 배포된 페이지를 열어 볼 수도 없다. 전부 오너가
한다.

- Settings > Pages > Source를 **GitHub Actions**로
- Settings > Environments > `github-pages` > 허용 브랜치에 `claude/*` 추가.
  이것이 없으면 워크플로가 **단계 하나 돌기 전에** 거부된다 - 로그도 없고
  어느 단계에도 오류가 없는 2초 실패다. 실제로 run 1과 2가 그렇게 실패했고
  3, 4, 5는 성공했다.
- Settings > Pages > Custom domain에 **`app.jalboine.com`**

`app.jalboine.com`인 이유: CNAME 한 줄이면 되고 꼭대기 도메인(apex)을
건드리지 않는다. Resend의 반송 경로가 `send.jalboine.com`에 있고 apex는
비어 있으므로, 나중에 `jalboine.com`에 홈페이지를 올리거나
`support@jalboine.com`으로 메일을 받는 것과 충돌하지 않는다. apex를 Pages에
주는 선택은 되돌리기 어렵다.

**DNS 레코드 값은 GitHub이 Settings > Pages에 도메인을 입력하면 화면에
보여 준다. 그 값을 가비아에 넣는다.** 기억으로 IP나 CNAME 대상을 적지
않는다 - 이 환경에서는 `docs.github.com`이 막혀 확인할 수 없다.

도메인이 붙으면 프로젝트 사이트는 `app.jalboine.com/` 뿌리에서 제공된다.
`/success/` 경로는 기본 `*.github.io` 호스트에서만 붙는다. 그래서
`passwordResetRedirect`에 `/success/`가 없다. 도메인을 붙인 뒤 실제 주소가
다르면 그 상수와 `uri_allow_list`를 같이 고친다.

## 5. 개인정보처리방침

`site/privacy.html`에 썼다. 수집 항목은 전부
`supabase/migrations/`와 라이브 스키마에서 읽었다. 두 가지는 틀리기 쉬워서
파일 안 주석에 적어 두었다.

- `senior_devices.permission_status`는 스키마에 있지만 **아무것도 쓰지
  않는다.** 그래서 수집 항목에 넣지 않았다.
- `home_apps.package_name`은 **실제로 서버에 간다.** 아이콘 이미지와 설치된
  앱 목록은 가지 않지만, 어르신이 직접 고른 앱 하나의 이름은 간다.

**국외 이전은 서울로 옮겨도 사라지지 않는다.** 사라지는 것은 Supabase
한 곳이다. Resend(메일), Firebase Cloud Messaging(소리 울리기 푸시 토큰),
Google Play(배포·결제)는 그대로 국외다. 방침은 그렇게 적혀 있다.

남은 것은 **사업자 정보**다. 상호, 대표자, 주소, 개인정보 보호책임자, 문의
이메일, 공고일·시행일 여섯 칸이 `「 」`로 비어 있다. 지어낼 수 없는 값이라
비워 두었고, 페이지 맨 위에 공개 전 초안임을 알리는 띠가 있다. **그 칸들이
채워지기 전에는 Play 심사나 카카오 동의항목에 이 주소를 내지 않는다.**
