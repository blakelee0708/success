"""The 무료 / 안심 케어 line, checked against the live project.

Settled with the owner 2026-10-28. `01_PRODUCT_PRD` had said 무료는 부모님
폰이 편해지는 것, 유료는 보호자의 안심 수요 - and the three things that
reassure the **child** were all free, which left two alerts to sell.

One rule runs through every check here: **the senior is never the one
charged.** Their own phone edits its own buttons without limit, and nothing
priced can stop them reaching their family.

Run with:
    SSL_CERT_FILE=/root/.ccr/ca-bundle.crt \
      python3 tool/verify_supabase_pricing.py
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
    email = f"price-{tag}-{uuid.uuid4().hex[:8]}@example.com"
    password = "price-test-" + uuid.uuid4().hex[:8]
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


try:
    phone, install = device()
    st, link = call("/rest/v1/rpc/start_senior_pairing", token=phone,
                    body={"p_install_id": install, "p_platform": "android"})
    assert st == 200, (st, link)
    profile_id = link["senior_profile_id"]
    created_profiles.append(profile_id)
    g1 = guardian("g1", "영희")
    st, _ = call("/rest/v1/rpc/claim_senior_pairing_code", token=g1,
                 body={"p_code": link["code"], "p_display_name": "어머니"})
    approve(phone)
    assert st == 200
    st, _ = call("/rest/v1/rpc/touch_senior_device", token=phone,
                 body={"p_install_id": install, "p_battery_percent": 72,
                       "p_is_charging": False, "p_ringer_mode": "normal"})
    assert st in (200, 204), st

    # --- 1. the message allowance ------------------------------------------
    st, q = quota(g1, profile_id)
    check("the free text allowance is 30", q.get("text_limit") == 30, q)
    check("the free photo allowance is 5", q.get("image_limit") == 5, q)
    check("and it is not unlimited yet", q.get("unlimited") is False, q)

    # --- 2. 자녀 폰에서 홈 화면 정리는 평생 3회 ------------------------------
    # Three, not two, since `20261029000000_home_edits_three.sql`: two is a
    # tight first impression, and the allowance was gone before anybody had
    # decided whether the app was any good.
    st, out = apps(g1, profile_id, ["전화"])
    check("a guardian may rearrange the home screen once", st == 200, (st, out))
    st, out = apps(g1, profile_id, ["전화", "문자"])
    check("and twice", st == 200, (st, out))
    st, out = apps(g1, profile_id, ["전화", "문자", "사진"])
    check("and three times", st == 200, (st, out))
    st, out = apps(g1, profile_id, ["전화", "문자", "사진", "카카오톡"])
    check("the fourth time is refused", st >= 400, (st, out))

    # **The senior is never the one charged.** Their own phone keeps editing
    # its own buttons after the guardian's two are spent, and this is the
    # check that matters most: a parent whose home screen froze because their
    # child used up a quota would be the app failing the person it is for.
    ok = True
    for i in range(4):
        st, out = apps(phone, profile_id, ["전화", "문자", "사진"][:1 + i % 3])
        ok = ok and st == 200
    check("the senior's own phone is never limited", ok, (st, out))

    st, out = apps(g1, profile_id, ["전화"])
    check("and the senior's saves did not count against the guardian",
          st >= 400, (st, out))

    rows = sql("select guardian_home_edits from public.senior_profiles "
               f"where id = '{profile_id}'")
    check("exactly the guardian's three were counted",
          rows[0]["guardian_home_edits"] == 3, rows)

    # --- 3. 안부 신호와 배터리·소리는 첫 1주일 ------------------------------
    st, out = readings(g1, profile_id)
    row = (out or [{}])[0] if isinstance(out, list) else {}
    check("inside the first week the guardian sees the readings",
          st == 200 and row.get("visible") is True
          and row.get("battery_percent") == 72, (st, out))
    check("and is told when the week ends", row.get("trial_ends_at"), out)

    # Age the link past the window. The trial runs from when a family first
    # attached to this parent, not from the guardian's sign-up.
    sql("update public.guardian_senior_links "
        "set created_at = now() - interval '8 days' "
        f"where senior_profile_id = '{profile_id}'")
    st, out = readings(g1, profile_id)
    row = (out or [{}])[0] if isinstance(out, list) else {}
    check("after the week it is withheld", row.get("visible") is False, out)
    # Null rather than no row, so the screen can tell *not allowed to say*
    # from *this phone has never checked in*. One of those is a sales line.
    check("and withheld as nulls, not as a missing phone",
          row.get("battery_percent") is None
          and row.get("last_seen_at") is None
          and row.get("ringer_mode") is None, out)

    st, out = readings(phone, profile_id)
    row = (out or [{}])[0] if isinstance(out, list) else {}
    check("the parent's own phone is not sold its own battery",
          st == 200 and row.get("visible") is False, (st, out))

    outsider = guardian("outsider", "남")
    st, out = readings(outsider, profile_id)
    check("another family's guardian is refused outright", st >= 400, (st, out))

    # --- 4. 읽음 확인 had no gate at all -----------------------------------
    st, msg = call("/rest/v1/rpc/send_family_message", token=g1,
                   body={"p_senior_profile_id": profile_id, "p_body": "엄마"})
    assert st == 200, (st, msg)
    st, marked = mark_read(phone, profile_id)
    check("an unpaid family writes no read receipt",
          st == 200 and marked == 0, (st, marked))
    check("and nothing was written to hide",
          read_ats(profile_id) == [None], read_ats(profile_id))

    # The guardian's own marking clears their unread badge and is always
    # free. Nothing of the senior's is being sold back to them.
    st, smsg = call("/rest/v1/rpc/send_family_message", token=phone,
                    body={"p_senior_profile_id": profile_id, "p_body": "잘 있다"})
    assert st == 200, (st, smsg)
    st, marked = mark_read(g1, profile_id)
    check("the guardian's own unread badge still clears for free",
          st == 200 and marked == 1, (st, marked))

    # --- everything the subscription turns on -------------------------------
    st, sub = call("/rest/v1/rpc/start_care_subscription", token=g1,
                   body={"p_senior_profile_id": profile_id})
    assert st == 200, (st, sub)
    st, out = apps(g1, profile_id, ["전화"])
    check("paying alone does not hand back the home-screen edits",
          st >= 400, (st, out))
    st, out = readings(g1, profile_id)
    row = (out or [{}])[0] if isinstance(out, list) else {}
    check("nor the readings", row.get("visible") is False, out)

    st, _ = call("/rest/v1/rpc/resolve_care_consent", token=phone,
                 body={"p_senior_profile_id": profile_id, "p_approve": True})
    assert st == 200

    st, out = apps(g1, profile_id, ["전화", "문자"])
    check("with the senior's consent the home screen opens up",
          st == 200, (st, out))
    st, out = readings(g1, profile_id)
    row = (out or [{}])[0] if isinstance(out, list) else {}
    check("and the readings come back",
          row.get("visible") is True and row.get("battery_percent") == 72, out)
    st, q = quota(g1, profile_id)
    check("and the messages are unlimited", q.get("unlimited") is True, q)
    st, marked = mark_read(phone, profile_id)
    check("and the read receipt is written", st == 200 and marked == 1,
          (st, marked))

    # Cancelling must not hand back a fresh three. The count keeps rising while
    # a subscription is on, so what is spent stays spent.
    rows = sql("select guardian_home_edits from public.senior_profiles "
               f"where id = '{profile_id}'")
    check("a paid save still counts, so cancelling gives nothing back",
          rows[0]["guardian_home_edits"] == 4, rows)

finally:
    for pid in created_profiles:
        call(f"/rest/v1/senior_profiles?id=eq.{pid}", key=SERVICE, method="DELETE")
    for uid in created_users:
        call(f"/auth/v1/admin/users/{uid}", key=SERVICE, method="DELETE")
    print(f"\ncleaned up {len(created_users)} users and {len(created_profiles)} profiles")

print("\n" + ("ALL CHECKS PASSED" if not failures else f"{len(failures)} FAILED: {failures}"))
raise SystemExit(1 if failures else 0)
