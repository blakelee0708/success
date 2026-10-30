"""End-to-end check of 끊기, 해지, 폰 교체 and 계정 삭제 against the live project.

**Nothing else can prove any of it.** `flutter test` runs on the in-memory
twins, which have no RLS at all, so a removed guardian reads everything there
and the test passes. What has to be true is that the *server* stops answering
them - the profile, the conversation, the photos, the home buttons and the
paid readings, each refused by its own policy.

Three things in here were written because reading the SQL could not answer
them:

- that a removed guardian is told, which `alerts` cannot do (its policy is
  `guardian_manages`, so an alert about being removed is readable by
  everyone except the person it is about)
- that `care_is_active` goes false when the link goes, which it did not
  before `20261029070000_leaving.sql`
- that deleting a guardian who had sent a message succeeds, which the
  `one_sender` exclusive-or made impossible

Run with:
    SSL_CERT_FILE=/root/.ccr/ca-bundle.crt python3 tool/verify_supabase_leaving.py
"""
import json
import os
import urllib.request
import uuid

# The agent proxy rejects the default Python-urllib user agent with a 403.
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
        BASE + path,
        data=data,
        method=method,
        headers={
            "apikey": key,
            "Authorization": f"Bearer {token or key}",
            "Content-Type": "application/json",
            "User-Agent": UA,
        },
    )
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


def sql(statement):
    """A Management API read, for what no client is allowed to see."""
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{REF}/database/query",
        data=json.dumps({"query": statement}).encode(),
        headers={"Authorization": f"Bearer {MGMT}",
                 "Content-Type": "application/json", "User-Agent": UA},
        method="POST")
    with urllib.request.urlopen(req) as r:
        return json.load(r)


def check(name, cond, detail=""):
    print(("PASS  " if cond else "FAIL  ") + name + ("" if cond else f"  <- {detail}"))
    if not cond:
        failures.append(name)


created_users = []
created_profiles = []


def guardian(tag, name=None):
    email = f"leaving-{tag}-{uuid.uuid4().hex[:8]}@example.com"
    password = "leaving-test-" + uuid.uuid4().hex[:8]
    st, made = call("/auth/v1/admin/users", key=SERVICE,
                    body={"email": email, "password": password,
                          "email_confirm": True})
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


def approve(phone_token):
    """The senior answers the 가족 연결 동의 card, which every attach now
    waits on. One call per guardian, oldest first."""
    st, card = call("/rest/v1/rpc/pending_guardian_link", token=phone_token,
                    body={})
    assert st == 200 and card, (st, card)
    st, ok = call("/rest/v1/rpc/answer_guardian_link", token=phone_token,
                  body={"p_link_id": card[0]["link_id"], "p_approve": True})
    assert st == 200 and ok is True, (st, ok)


def account_id(token):
    st, rows = call("/rest/v1/guardian_accounts?select=id", token=token,
                    method="GET")
    assert st == 200 and rows, (st, rows)
    return rows[0]["id"]


def family(senior_name="어머니", guardian_name="영희"):
    """A parent's phone with a profile, and its one guardian attached and agreed.

    One, because the product is 1대1 - 무조건 자녀 하나, 부모 하나.
    """
    phone, install = device()
    st, pair = call("/rest/v1/rpc/start_senior_pairing", token=phone,
                    body={"p_install_id": install, "p_platform": "android"})
    assert st == 200, (st, pair)
    profile_id = pair["senior_profile_id"]
    created_profiles.append(profile_id)
    g = guardian(f"g-{uuid.uuid4().hex[:4]}", guardian_name)
    st, _ = call("/rest/v1/rpc/claim_senior_pairing_code", token=g,
                 body={"p_code": pair["code"],
                       "p_display_name": senior_name,
                       "p_phone_number": "01012345678"})
    assert st == 200, (st, _)
    approve(phone)
    return phone, install, profile_id, g


def links_of(profile_id):
    st, rows = call(
        "/rest/v1/guardian_senior_links?senior_profile_id=eq." + profile_id
        + "&select=guardian_account_id,role,status",
        key=SERVICE, method="GET")
    return rows or []


def buy_and_agree(guardian_token, phone_token, profile_id):
    st, _ = call("/rest/v1/rpc/start_care_subscription", token=guardian_token,
                 body={"p_senior_profile_id": profile_id})
    assert st == 200, (st, _)
    st, _ = call("/rest/v1/rpc/resolve_care_consent", token=phone_token,
                 body={"p_senior_profile_id": profile_id, "p_approve": True})
    assert st == 200, (st, _)


def used_yesterday(profile_id):
    """Makes the paid month one that was used: a guardian read the paid
    readings yesterday. `started_at` moves back too, because a use day
    before the payment's own date does not count."""
    sql("update public.subscriptions set started_at = now() - interval '2 days' "
        "where senior_profile_id = '%s' and status = 'active'" % profile_id)
    sql("insert into public.care_use_days (subscription_id, used_on) "
        "select id, public.seoul_today() - 1 from public.subscriptions "
        "where senior_profile_id = '%s' and status = 'active' "
        "on conflict do nothing" % profile_id)


def care_on(profile_id):
    rows = sql("select public.care_is_active('%s') as on" % profile_id)
    return rows[0]["on"]


try:
    # ======================================================================
    # 1. 어르신이 끊는다
    # ======================================================================
    phone, install, profile_id, g1 = family()
    g1_id = account_id(g1)

    st, mine = call("/rest/v1/senior_profiles?select=id", token=g1, method="GET")
    check("the guardian can see their parent before anything is cut",
          st == 200 and len(mine or []) == 1, (st, mine))

    buy_and_agree(g1, phone, profile_id)
    check("안심 케어 is on while the family is connected", care_on(profile_id))

    st, out = call("/rest/v1/rpc/remove_guardian_link", token=phone,
                   body={"p_guardian_account_id": g1_id})
    check("the parent's own phone may cut a guardian", st in (200, 204),
          (st, out))

    rows = links_of(profile_id)
    check("the link reads removed rather than disappearing",
          len(rows) == 1 and rows[0]["status"] == "removed", rows)

    # --- the five things a removed guardian must no longer reach -----------
    st, mine = call("/rest/v1/senior_profiles?select=id", token=g1, method="GET")
    check("a removed guardian has no parent", st != 200 or not mine, (st, mine))

    st, msgs = call("/rest/v1/messages?select=id", token=g1, method="GET")
    check("nor the conversation", st != 200 or not msgs, (st, msgs))

    st, apps = call("/rest/v1/home_apps?select=id", token=g1, method="GET")
    check("nor the home buttons", st != 200 or not apps, (st, apps))

    st, dev = call("/rest/v1/senior_devices?select=id", token=g1, method="GET")
    check("nor which phone it is", st != 200 or not dev, (st, dev))

    st, readings = call("/rest/v1/rpc/senior_readings", token=g1,
                        body={"p_senior_profile_id": profile_id})
    check("nor the paid readings", st != 200 or not readings, (st, readings))

    # --- and the money came back -------------------------------------------
    check("안심 케어 goes off with the last link", not care_on(profile_id))
    subs = sql("select status, refunded_at, refund_kind from public.subscriptions "
               "where senior_profile_id = '%s' and plan = 'care'" % profile_id)
    check("a month never used is refunded in full inside the first week, "
          "whoever cut", len(subs) == 1 and subs[0]["status"] == "refunded"
          and subs[0]["refund_kind"] == "full", subs)

    # --- the notice, which `alerts` could not carry ------------------------
    st, notices = call("/rest/v1/guardian_notices?select=type,senior_name,body",
                       token=g1, method="GET")
    check("the removed guardian is told, in one line",
          st == 200 and len(notices or []) == 1
          and notices[0]["type"] == "link_removed", (st, notices))
    check("and the line names the parent, which it had to copy to be able to",
          notices and notices[0]["senior_name"] == "어머니", notices)
    check("and gives no reason", notices
          and "연결이 끊어졌습니다." == notices[0]["body"], notices)

    st, alerts = call("/rest/v1/alerts?select=id", token=g1, method="GET")
    check("`alerts` really is unreadable to them, which is why the table exists",
          st != 200 or not alerts, (st, alerts))

    # --- 되돌릴 수 있다 ------------------------------------------------------
    st, pair2 = call("/rest/v1/rpc/start_senior_pairing", token=phone,
                     body={"p_install_id": install, "p_platform": "android"})
    assert st == 200, (st, pair2)
    st, _ = call("/rest/v1/rpc/claim_senior_pairing_code", token=g1,
                 body={"p_code": pair2["code"], "p_display_name": "어머니"})
    check("the same guardian may be connected again", st == 200, (st, _))
    approve(phone)
    st, mine = call("/rest/v1/senior_profiles?select=id", token=g1, method="GET")
    check("and the old conversation is theirs again",
          st == 200 and len(mine or []) == 1, (st, mine))

    # ======================================================================
    # 2. 안심 케어를 산 자녀
    # ======================================================================
    phone2, _i2, profile2, a2 = family("아버지", "철수")
    a2_id = account_id(a2)
    buy_and_agree(a2, phone2, profile2)
    check("the child who paid has 안심 케어 on", care_on(profile2))

    # ======================================================================
    # 3. 누가 끊을 수 있는가
    # ======================================================================
    st, out = call("/rest/v1/rpc/remove_guardian_link", token=a2,
                   body={"p_guardian_account_id": a2_id})
    check("a guardian cannot cut a link from their own phone", st >= 400,
          (st, out))

    stranger = guardian("stranger")
    st, out = call("/rest/v1/rpc/remove_guardian_link", token=stranger,
                   body={"p_guardian_account_id": a2_id})
    check("nor can an unrelated account", st >= 400, (st, out))

    st, out = call("/rest/v1/rpc/remove_guardian_link", key=ANON,
                   body={"p_guardian_account_id": a2_id})
    check("nor a caller with no session at all", st >= 400, (st, out))

    st, out = call("/rest/v1/rpc/leave_senior", token=stranger,
                   body={"p_senior_profile_id": profile2})
    check("leaving a parent who is not yours changes nothing",
          st in (200, 204) and len(
              [r for r in links_of(profile2) if r["status"] == "active"]) == 1,
          (st, links_of(profile2)))

    # ======================================================================
    # 4. 자녀가 끊는다
    # ======================================================================
    st, out = call("/rest/v1/rpc/leave_senior", token=a2,
                   body={"p_senior_profile_id": profile2})
    check("a guardian may leave on their own", st in (200, 204), (st, out))
    check("and their 안심 케어 stops with them", not care_on(profile2))
    subs = sql("select status, refund_kind from public.subscriptions "
               "where senior_profile_id = '%s' and plan = 'care'" % profile2)
    check("an unused month is refunded when the child leaves too",
          len(subs) == 1 and subs[0]["status"] == "refunded"
          and subs[0]["refund_kind"] == "full", subs)

    st, cards = call("/rest/v1/rpc/pending_guardian_link", token=phone2, body={})
    check("the parent is not asked anything about it",
          st == 200 and not cards, (st, cards))

    # **Who cut does not decide the money, use does.** 그럼 부모님께
    # 끊으라고 하겠지 - so a used month cut by the parent refunds exactly as
    # much as one the child cancelled: nothing, and its days stand.
    phone5, install5, profile5, e1 = family("외할머니")
    e1_id = account_id(e1)
    buy_and_agree(e1, phone5, profile5)
    used_yesterday(profile5)
    st, out = call("/rest/v1/rpc/remove_guardian_link", token=phone5,
                   body={"p_guardian_account_id": e1_id})
    assert st in (200, 204), (st, out)
    subs = sql("select status, refunded_at from public.subscriptions "
               "where senior_profile_id = '%s' and plan = 'care'" % profile5)
    check("a used month the parent cut refunds nothing",
          len(subs) == 1 and subs[0]["status"] == "canceled"
          and subs[0]["refunded_at"] is None, subs)
    check("and is off while there is no link", not care_on(profile5))
    st, pair5 = call("/rest/v1/rpc/start_senior_pairing", token=phone5,
                     body={"p_install_id": install5, "p_platform": "android"})
    assert st == 200, (st, pair5)
    st, _ = call("/rest/v1/rpc/claim_senior_pairing_code", token=e1,
                 body={"p_code": pair5["code"], "p_display_name": "외할머니"})
    assert st == 200, (st, _)
    approve(phone5)
    rows = sql("select paid_consent_status as c from public.senior_profiles "
               "where id = '%s'" % profile5)
    check("reconnecting asks the parent about 안심 케어 again",
          rows[0]["c"] == "pending", rows)
    check("and nothing is on until they answer", not care_on(profile5))
    st, out = call("/rest/v1/rpc/start_care_subscription", token=e1,
                   body={"p_senior_profile_id": profile5})
    check("buying again while they are being asked is refused", st >= 400,
          (st, out))
    st, _ = call("/rest/v1/rpc/resolve_care_consent", token=phone5,
                 body={"p_senior_profile_id": profile5, "p_approve": True})
    check("their 허락 brings the remaining days back",
          st == 200 and care_on(profile5), (st, _))
    subs = sql("select count(*) as n from public.subscriptions "
               "where senior_profile_id = '%s' and plan = 'care'" % profile5)
    check("on the same subscription, not a new one", subs[0]["n"] == 1, subs)

    # The same, answered 거절. Refunding here would reopen the hole one step
    # longer: 끊었다가 다시 연결하고 거절해 줘.
    phone6, install6, profile6, f1 = family("큰어머니")
    f1_id = account_id(f1)
    buy_and_agree(f1, phone6, profile6)
    used_yesterday(profile6)
    st, out = call("/rest/v1/rpc/remove_guardian_link", token=phone6,
                   body={"p_guardian_account_id": f1_id})
    assert st in (200, 204), (st, out)
    st, pair6 = call("/rest/v1/rpc/start_senior_pairing", token=phone6,
                     body={"p_install_id": install6, "p_platform": "android"})
    assert st == 200, (st, pair6)
    st, _ = call("/rest/v1/rpc/claim_senior_pairing_code", token=f1,
                 body={"p_code": pair6["code"], "p_display_name": "큰어머니"})
    assert st == 200, (st, _)
    approve(phone6)
    st, _ = call("/rest/v1/rpc/resolve_care_consent", token=phone6,
                 body={"p_senior_profile_id": profile6, "p_approve": False})
    check("the parent may say no the second time", st == 200, (st, _))
    subs = sql("select status, refunded_at from public.subscriptions "
               "where senior_profile_id = '%s' and plan = 'care'" % profile6)
    check("and a used month still refunds nothing",
          len(subs) == 1 and subs[0]["status"] == "canceled"
          and subs[0]["refunded_at"] is None, subs)
    check("and stays off", not care_on(profile6))
    st, alerts6 = call("/rest/v1/alerts?select=body&type=eq.care_consent_refused",
                       token=f1, method="GET")
    check("the guardian is told there is no refund, not that there was one",
          st == 200 and alerts6 and "환불은 없습니다" in alerts6[0]["body"],
          (st, alerts6))

    # 해지하기 on a used month keeps the days already paid for.
    phone3, _i3, profile3, c1 = family("할머니")
    buy_and_agree(c1, phone3, profile3)
    used_yesterday(profile3)
    st, out = call("/rest/v1/rpc/cancel_care_subscription", token=c1,
                   body={"p_senior_profile_id": profile3})
    check("해지하기 keeps the days already paid for",
          st == 200 and care_on(profile3), (st, out))
    subs = sql("select status, refunded_at from public.subscriptions "
               "where senior_profile_id = '%s' and plan = 'care'" % profile3)
    check("and refunds nothing, because the month was used",
          len(subs) == 1 and subs[0]["status"] == "canceled"
          and subs[0]["refunded_at"] is None, subs)

    # A cancelled month that has run out was delivered in full. Leaving
    # afterwards must not record a refund for it - which the first version
    # of `settle_care_after_leaving` did, for every 'canceled' row.
    sql("update public.subscriptions set current_period_end = now() - "
        "interval '1 day' where senior_profile_id = '%s' and plan = 'care'"
        % profile3)
    st, out = call("/rest/v1/rpc/leave_senior", token=c1,
                   body={"p_senior_profile_id": profile3})
    assert st in (200, 204), (st, out)
    subs = sql("select status, refunded_at from public.subscriptions "
               "where senior_profile_id = '%s' and plan = 'care'" % profile3)
    check("leaving after a used-up cancelled month refunds nothing",
          len(subs) == 1 and subs[0]["status"] == "canceled"
          and subs[0]["refunded_at"] is None, subs)

    # ======================================================================
    # 5. 부모님이 폰을 바꾸셨을 때
    # ======================================================================
    phone4, old_install, profile4, d1 = family("어머니")
    st, _ = call("/rest/v1/rpc/send_family_message", token=d1,
                 body={"p_senior_profile_id": profile4, "p_body": "잘 계세요?"})
    assert st == 200, (st, _)

    new_phone, new_install = device()
    st, pair_new = call("/rest/v1/rpc/start_senior_pairing", token=new_phone,
                        body={"p_install_id": new_install,
                              "p_platform": "android"})
    assert st == 200, (st, pair_new)
    created_profiles.append(pair_new["senior_profile_id"])
    check("a new handset pressing 번호 보여주기 makes a second, empty parent",
          pair_new["senior_profile_id"] != profile4, pair_new)

    st, moved = call("/rest/v1/rpc/move_senior_to_new_phone", token=d1,
                     body={"p_code": pair_new["code"],
                           "p_senior_profile_id": profile4})
    check("the child answers 폰을 바꿨어요 and the phone moves",
          st == 200 and moved and moved["id"] == profile4, (st, moved))

    devs = sql("select install_id, is_active from public.senior_devices "
               "where senior_profile_id = '%s' order by is_active desc"
               % profile4)
    check("the new handset is the active one",
          [d for d in devs if d["is_active"]]
          and devs[0]["install_id"] == new_install, devs)
    check("and the old handset steps down rather than being deleted",
          any(d["install_id"] == old_install and not d["is_active"]
              for d in devs), devs)

    st, msgs = call("/rest/v1/messages?select=body", token=new_phone,
                    method="GET")
    check("the conversation came with it",
          st == 200 and len(msgs or []) == 1, (st, msgs))

    gone = sql("select count(*) as n from public.senior_profiles where id = '%s'"
               % pair_new["senior_profile_id"])
    check("and the empty profile is gone, so the child has one parent again",
          gone[0]["n"] == 0, gone)

    # The new phone still has the empty profile's id saved, and nothing
    # tells it otherwise - so the app asks the one question it can: which
    # profile is my own device row on now. That read is
    # `profileOfThisPhone`, and it has to work under RLS.
    st, mine = call("/rest/v1/senior_devices?select=senior_profile_id"
                    "&install_id=eq.%s&is_active=eq.true" % new_install,
                    token=new_phone, method="GET")
    check("the moved phone can read which profile it is on now",
          st == 200 and mine and mine[0]["senior_profile_id"] == profile4,
          (st, mine))

    # --- only an empty one may be absorbed ---------------------------------
    phone5, _i5, profile5, e1 = family("남의 어머니")
    st, pair5 = call("/rest/v1/rpc/start_senior_pairing", token=phone5,
                     body={"p_install_id": _i5, "p_platform": "android"})
    assert st == 200, (st, pair5)
    st, out = call("/rest/v1/rpc/move_senior_to_new_phone", token=d1,
                   body={"p_code": pair5["code"],
                         "p_senior_profile_id": profile4})
    check("a profile that already has a family cannot be swallowed",
          st >= 400, (st, out))

    st, pair6 = call("/rest/v1/rpc/start_senior_pairing", token=new_phone,
                     body={"p_install_id": new_install,
                           "p_platform": "android"})
    assert st == 200, (st, pair6)
    st, out = call("/rest/v1/rpc/move_senior_to_new_phone", token=stranger,
                   body={"p_code": pair6["code"],
                         "p_senior_profile_id": profile4})
    check("and only an active guardian of that parent may answer", st >= 400,
          (st, out))

    # ======================================================================
    # 6. 계정 삭제
    # ======================================================================
    phone7, _i7, profile7, f1 = family("아버지", "영희")
    f1_id = account_id(f1)
    st, _ = call("/rest/v1/rpc/send_family_message", token=f1,
                 body={"p_senior_profile_id": profile7, "p_body": "아버지 안녕"})
    assert st == 200, (st, _)
    buy_and_agree(f1, phone7, profile7)

    st, out = call("/rest/v1/rpc/delete_guardian_account", token=f1, body={})
    check("a guardian who has sent a message can still delete their account",
          st in (200, 204), (st, out))

    rows = sql("select count(*) as n from public.guardian_accounts "
               "where id = '%s'" % f1_id)
    check("the account row is gone, not deactivated", rows[0]["n"] == 0, rows)
    rows = sql("select count(*) as n from public.guardian_senior_links "
               "where guardian_account_id = '%s'" % f1_id)
    check("and so are their links", rows[0]["n"] == 0, rows)
    rows = sql("select count(*) as n from public.subscriptions "
               "where guardian_account_id = '%s'" % f1_id)
    check("and their subscription", rows[0]["n"] == 0, rows)

    msgs = sql("select body, sender_guardian_id, sender_device_id "
               "from public.messages where senior_profile_id = '%s'" % profile7)
    check("their message stays, because the parent received it too",
          len(msgs) == 1 and msgs[0]["body"] == "아버지 안녕", msgs)
    check("with nobody's name on it",
          msgs and msgs[0]["sender_guardian_id"] is None
          and msgs[0]["sender_device_id"] is None, msgs)

    rows = sql("select count(*) as n from public.senior_profiles where id = '%s'"
               % profile7)
    check("the parent's profile survives, because they are still holding "
          "that phone", rows[0]["n"] == 1, rows)
    st, mine = call("/rest/v1/senior_profiles?select=id", token=phone7,
                    method="GET")
    check("and the parent's own phone still reads it",
          st == 200 and len(mine or []) == 1, (st, mine))

    # --- the half-made profile nobody ever used ----------------------------
    g_alone = guardian("alone", "막내")
    st, made = call("/rest/v1/rpc/create_senior_profile", token=g_alone,
                    body={"p_display_name": "연결 안 된 아버지"})
    assert st == 200, (st, made)
    created_profiles.append(made["id"])
    st, out = call("/rest/v1/rpc/delete_guardian_account", token=g_alone,
                   body={})
    assert st in (200, 204), (st, out)
    rows = sql("select count(*) as n from public.senior_profiles where id = '%s'"
               % made["id"])
    check("a parent no phone ever connected to goes with the last account",
          rows[0]["n"] == 0, rows)

    st, out = call("/rest/v1/rpc/delete_guardian_account", key=ANON, body={})
    check("deleting with no session is refused", st >= 400, (st, out))

finally:
    for pid in created_profiles:
        call(f"/rest/v1/senior_profiles?id=eq.{pid}", key=SERVICE,
             method="DELETE")
    for uid in created_users:
        call(f"/auth/v1/admin/users/{uid}", key=SERVICE, method="DELETE")
    print(f"\ncleaned up {len(created_users)} users and "
          f"{len(created_profiles)} profiles")

print("\n" + ("ALL CHECKS PASSED" if not failures
              else f"{len(failures)} FAILED: {failures}"))
raise SystemExit(1 if failures else 0)
