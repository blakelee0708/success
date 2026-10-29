"""안심 케어 해지, and the month it is a month of, against the live project.

The 안심 케어 tab has promised 언제든 해지할 수 있습니다 since Phase 6 while
nothing in the app or the schema could cancel anything. What is checked here
is the shape Play Billing will arrive in, because the day it lands none of it
should have to be undone:

- the month is the **next month's same day and same hour**, in Seoul, not 30
  days, and 1월 31일 lands on 2월 28일;
- it runs from the senior's 허락합니다, capped three hours after the payment;
- **cancelling switches nothing off** until that month runs out, which is
  what Play does and what `site/terms.html` promises;
- buying again inside that month is 해지 취소, one row, not two.

Run with:
    SSL_CERT_FILE=/root/.ccr/ca-bundle.crt \
      python3 tool/verify_supabase_care_cancel.py
"""
import json
import os
import urllib.request
import uuid

urllib.request.install_opener(urllib.request.build_opener())

REF = os.environ["SUPABASE_PROJECT_REF"]
MGMT = os.environ["SUPABASE_ACCESS_TOKEN"]
BASE = f"https://{REF}.supabase.co"
UA = "curl/8.5.0"


def mgmt_keys():
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{REF}/api-keys?reveal=true",
        headers={"Authorization": f"Bearer {MGMT}", "User-Agent": UA},
    )
    keys = json.load(urllib.request.urlopen(req))
    out = {}
    for k in keys:
        if k["name"] == "anon" or k["type"] == "publishable":
            out.setdefault("anon", k["api_key"])
        if k["name"] == "service_role" or k["type"] == "secret":
            out.setdefault("service", k["api_key"])
    return out["anon"], out["service"]


ANON, SERVICE = mgmt_keys()
failures = []


def call(path, *, token=None, key=None, method="POST", body=None):
    key = key or ANON
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        BASE + path, data=data, method=method,
        headers={"apikey": key, "Authorization": f"Bearer {token or key}",
                 "Content-Type": "application/json", "User-Agent": UA})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw.decode()


def check(name, cond, detail=""):
    print(("PASS  " if cond else "FAIL  ") + name + ("" if cond else f"  <- {detail}"))
    if not cond:
        failures.append(name)


def approve(phone_token):
    """The senior says 허락합니다 on their own phone.

    Every path that attaches a guardian writes `pending` since
    `20261029010000_link_consent.sql`, so a script standing in for the
    parent's phone has to answer the card before anything that needs an
    active link. A loop, because a sibling joining raises a second card.
    """
    while True:
        st, card = call("/rest/v1/rpc/pending_guardian_link",
                        token=phone_token, body={})
        if st != 200 or not card:
            return
        call("/rest/v1/rpc/answer_guardian_link", token=phone_token,
             body={"p_link_id": card[0]["link_id"], "p_approve": True})


created_users = []
created_profiles = []


def guardian(tag, name=None):
    email = f"cancel-{tag}-{uuid.uuid4().hex[:8]}@example.com"
    password = "cancel-test-" + uuid.uuid4().hex[:8]
    st, made = call("/auth/v1/admin/users", key=SERVICE,
                    body={"email": email, "password": password, "email_confirm": True})
    assert st in (200, 201), (st, made)
    created_users.append(made["id"])
    st, sess = call("/auth/v1/token?grant_type=password",
                    body={"email": email, "password": password})
    assert st == 200, (st, sess)
    token = sess["access_token"]
    call("/rest/v1/rpc/ensure_guardian_account", token=token,
         body={"p_display_name": name or tag})
    return token


def device():
    st, sess = call("/auth/v1/signup", body={})
    assert st == 200, (st, sess)
    created_users.append(sess["user"]["id"])
    return sess["access_token"], "install-" + uuid.uuid4().hex[:10]


def sql(statement):
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{REF}/database/query",
        data=json.dumps({"query": statement}).encode(),
        headers={"Authorization": f"Bearer {MGMT}",
                 "Content-Type": "application/json", "User-Agent": UA},
        method="POST")
    with urllib.request.urlopen(req) as r:
        return json.load(r)



def apps(token, profile_id, labels):
    return call("/rest/v1/rpc/replace_home_apps", token=token, body={
        "p_senior_profile_id": profile_id,
        "p_apps": [{"client_id": f"c{i}", "label": l, "app_type": "system_app",
                    "icon_key": "phone"}
                   for i, l in enumerate(labels)],
    })


def quota(token, profile_id):
    return call("/rest/v1/rpc/family_message_quota", token=token,
                body={"p_senior_profile_id": profile_id})


def readings(token, profile_id):
    return call("/rest/v1/rpc/senior_readings", token=token,
                body={"p_senior_profile_id": profile_id})


def mark_read(token, profile_id):
    return call("/rest/v1/rpc/mark_conversation_read", token=token,
                body={"p_senior_profile_id": profile_id})


def read_ats(profile_id):
    rows = sql("select read_at from public.messages "
               f"where senior_profile_id = '{profile_id}' "
               "and sender_guardian_id is not null")
    return [r["read_at"] for r in rows]



def period_end(pid):
    rows = sql("select status, canceled_at, refunded_at, current_period_end "
               f"from public.subscriptions where senior_profile_id = '{pid}' "
               "and plan = 'care'")
    return rows


def active(token, pid):
    st, out = call("/rest/v1/rpc/care_is_active", token=token,
                   body={"p_senior_profile_id": pid})
    return out


try:
    # --- 한 달은 30일이 아니다 -----------------------------------------------
    rows = sql("select public.one_month_after("
               "'2026-01-01 01:00+09'::timestamptz) at time zone 'Asia/Seoul' as e")
    check("1월 1일 01시는 2월 1일 01시에 끝난다",
          rows[0]["e"].startswith("2026-02-01 01:00"), rows)

    rows = sql("select public.one_month_after("
               "'2026-01-31 01:00+09'::timestamptz) at time zone 'Asia/Seoul' as e")
    check("2월 31일은 없으므로 2월 28일이다",
          rows[0]["e"].startswith("2026-02-28 01:00"), rows)

    rows = sql("select public.one_month_after("
               "'2026-02-01 01:00+09'::timestamptz) at time zone 'Asia/Seoul' as e")
    check("28일짜리 달도 다음 달 같은 날로 간다",
          rows[0]["e"].startswith("2026-03-01 01:00"), rows)

    # --- 기준은 동의, 상한은 세 시간 ----------------------------------------
    rows = sql("select public.care_period_anchor("
               "'2026-01-01 01:00+09'::timestamptz,"
               "'2026-01-01 01:40+09'::timestamptz)"
               " at time zone 'Asia/Seoul' as a")
    check("세 시간 안에 동의하면 동의 시각이 기준",
          rows[0]["a"].startswith("2026-01-01 01:40"), rows)

    rows = sql("select public.care_period_anchor("
               "'2026-01-01 01:00+09'::timestamptz,"
               "'2026-01-01 09:00+09'::timestamptz)"
               " at time zone 'Asia/Seoul' as a")
    check("늦게 동의해도 결제 세 시간 뒤가 상한",
          rows[0]["a"].startswith("2026-01-01 04:00"), rows)

    # --- 한 가족 ------------------------------------------------------------
    g1 = guardian("g1", "영희")
    phone, install = device()
    st, link = call("/rest/v1/rpc/start_senior_pairing", token=phone,
                    body={"p_install_id": install})
    assert st == 200, (st, link)
    pid = link["senior_profile_id"]
    created_profiles.append(pid)
    st, _ = call("/rest/v1/rpc/claim_senior_pairing_code", token=g1,
                 body={"p_code": link["code"], "p_display_name": "어머니"})
    assert st == 200
    approve(phone)

    # --- 결제하고 어르신이 허락한다 ------------------------------------------
    st, sub = call("/rest/v1/rpc/start_care_subscription", token=g1,
                   body={"p_senior_profile_id": pid})
    check("결제하면 어르신 답을 기다린다",
          st == 200 and sub["status"] == "pending_senior_consent", (st, sub))
    check("아직 만료일은 없다", sub.get("current_period_end") is None, sub)
    check("아직 켜지지 않았다", active(g1, pid) is False, active(g1, pid))

    st, _ = call("/rest/v1/rpc/resolve_care_consent", token=phone,
                 body={"p_senior_profile_id": pid, "p_approve": True})
    assert st == 200
    check("허락하면 켜진다", active(g1, pid) is True, active(g1, pid))

    rows = period_end(pid)
    check("그리고 만료일이 생긴다", rows[0]["current_period_end"] is not None, rows)

    rows = sql("select (current_period_end > now() + interval '27 days') as far, "
               "(current_period_end < now() + interval '32 days') as near "
               f"from public.subscriptions where senior_profile_id = '{pid}' "
               "and plan = 'care'")
    check("만료일은 한 달 뒤다", rows[0]["far"] and rows[0]["near"], rows)

    # --- 해지해도 이번 달은 그대로 ------------------------------------------
    st, canceled = call("/rest/v1/rpc/cancel_care_subscription", token=g1,
                        body={"p_senior_profile_id": pid})
    check("해지할 수 있다", st == 200 and canceled["status"] == "canceled",
          (st, canceled))
    check("해지한 시각이 남는다", canceled.get("canceled_at") is not None, canceled)
    check("환불로 기록되지 않는다", canceled.get("refunded_at") is None, canceled)
    check("해지해도 이번 달은 켜져 있다", active(g1, pid) is True, active(g1, pid))
    check("만료일은 그대로다", canceled.get("current_period_end") is not None,
          canceled)

    st, again = call("/rest/v1/rpc/cancel_care_subscription", token=g1,
                     body={"p_senior_profile_id": pid})
    check("두 번 해지할 수는 없다", st >= 400, (st, again))

    # --- 기간 안에 다시 사면 해지 취소 --------------------------------------
    st, resumed = call("/rest/v1/rpc/start_care_subscription", token=g1,
                       body={"p_senior_profile_id": pid})
    check("기간 안에 다시 사면 다시 켜진다",
          st == 200 and resumed["status"] == "active", (st, resumed))
    check("어르신에게 다시 묻지 않는다",
          resumed["id"] == canceled["id"], (resumed.get("id"), canceled.get("id")))
    rows = sql("select count(*) as n from public.subscriptions "
               f"where senior_profile_id = '{pid}' and plan = 'care'")
    check("구독 행은 하나뿐이다", rows[0]["n"] == 1, rows)

    # --- 달이 끝나면 꺼진다 --------------------------------------------------
    call("/rest/v1/rpc/cancel_care_subscription", token=g1,
         body={"p_senior_profile_id": pid})
    sql("update public.subscriptions set current_period_end = now() "
        f"- interval '1 minute' where senior_profile_id = '{pid}'")
    check("달이 끝나면 꺼진다", active(g1, pid) is False, active(g1, pid))
    st, after = call("/rest/v1/rpc/start_care_subscription", token=g1,
                     body={"p_senior_profile_id": pid})
    check("그 뒤에 사면 어르신에게 다시 묻는다",
          st == 200 and after["status"] == "pending_senior_consent", (st, after))

    # --- 답을 기다리는 동안의 해지는 환불이다 --------------------------------
    st, withdrawn = call("/rest/v1/rpc/cancel_care_subscription", token=g1,
                         body={"p_senior_profile_id": pid})
    check("답을 기다리는 중에도 해지할 수 있다",
          st == 200 and withdrawn["status"] == "refunded", (st, withdrawn))
    rows = sql("select paid_consent_status from public.senior_profiles "
               f"where id = '{pid}'")
    check("어르신 화면의 질문도 거둬들인다",
          rows[0]["paid_consent_status"] == "none", rows)
    st, nothing = call("/rest/v1/rpc/resolve_care_consent", token=phone,
                       body={"p_senior_profile_id": pid, "p_approve": True})
    check("그러면 어르신은 답할 것이 없다", st >= 400, (st, nothing))

    # --- 남의 가족은 건드리지 못한다 ----------------------------------------
    st, _ = call("/rest/v1/rpc/start_care_subscription", token=g1,
                 body={"p_senior_profile_id": pid})
    assert st == 200
    st, denied = call("/rest/v1/rpc/cancel_care_subscription",
                      token=guardian("stranger"),
                      body={"p_senior_profile_id": pid})
    check("남의 가족 구독은 해지하지 못한다", st >= 400, (st, denied))

    st, denied = call("/rest/v1/rpc/cancel_care_subscription", token=phone,
                      body={"p_senior_profile_id": pid})
    check("어르신 폰도 해지 버튼의 주인은 아니다", st >= 400, (st, denied))

    st, denied = call("/rest/v1/rpc/cancel_care_subscription", token=None,
                      body={"p_senior_profile_id": pid})
    check("세션 없는 호출은 거부된다", st >= 400, (st, denied))

finally:
    for pid_ in created_profiles:
        call(f"/rest/v1/senior_profiles?id=eq.{pid_}", key=SERVICE, method="DELETE")
    for uid in created_users:
        call(f"/auth/v1/admin/users/{uid}", key=SERVICE, method="DELETE")
    print(f"\ncleaned up {len(created_users)} users and "
          f"{len(created_profiles)} profiles")

if failures:
    print(f"\n{len(failures)} FAILED: {failures}")
    raise SystemExit(1)
print("\nALL CHECKS PASSED")
