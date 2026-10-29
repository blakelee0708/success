"""End-to-end check of 소리 울리기's gate against the live project.

The Edge Function that talks to FCM is a sender and nothing else. Every
question about *whether this ring is allowed* is answered by
`request_phone_ring`, in SQL, next to the rules it belongs with — which is
also what makes it checkable from here, since the Edge Function is not.

Three things have to be true, and the third is the one that is easy to forget:
paying does not turn 안심 케어 on. `care_is_active` is a subscription *and*
the senior's consent.

Run with:
    SSL_CERT_FILE=/root/.ccr/ca-bundle.crt python3 tool/verify_supabase_ring.py
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
    email = f"ring-{tag}-{uuid.uuid4().hex[:8]}@example.com"
    password = "ring-test-" + uuid.uuid4().hex[:8]
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


def ring(token, profile_id, message=None):
    return call("/rest/v1/rpc/request_phone_ring", token=token,
                body={"p_senior_profile_id": profile_id, "p_message": message})


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
                 body={"p_install_id": install, "p_push_token": "fcm-abc"})
    assert st in (200, 204), st

    # --- the subscription gate ----------------------------------------------
    st, out = ring(g1, profile_id)
    check("an unpaid family cannot ring the phone", st >= 400, (st, out))

    st, sub = call("/rest/v1/rpc/start_care_subscription", token=g1,
                   body={"p_senior_profile_id": profile_id})
    assert st == 200, (st, sub)
    st, out = ring(g1, profile_id)
    check("paying is not enough — the senior has not agreed yet",
          st >= 400, (st, out))

    st, _ = call("/rest/v1/rpc/resolve_care_consent", token=phone,
                 body={"p_senior_profile_id": profile_id, "p_approve": True})
    assert st == 200

    # --- what the sender is handed ------------------------------------------
    st, out = ring(g1, profile_id, "엄마 전화 좀 줘")
    check("a paid family whose parent agreed may ring", st == 200, (st, out))
    row = (out or [{}])[0] if isinstance(out, list) else {}
    check("it carries the phone's address", row.get("push_token") == "fcm-abc", out)
    check("and who is asking", row.get("from_name") == "영희", out)
    check("and their own words", row.get("line") == "엄마 전화 좀 줘", out)

    st, out = ring(g1, profile_id)
    row = (out or [{}])[0] if isinstance(out, list) else {}
    # A phone that starts making a noise with no explanation is frightening to
    # someone who cannot tell a message from a fault. The line is never blank.
    check("a ring with no message still explains itself",
          row.get("line") == "전화 한 번만 주세요.", out)
    st, out = ring(g1, profile_id, "   ")
    row = (out or [{}])[0] if isinstance(out, list) else {}
    check("and whitespace is not a message", row.get("line") == "전화 한 번만 주세요.", out)

    # --- who may not ---------------------------------------------------------
    outsider = guardian("outsider", "남")
    st, out = ring(outsider, profile_id)
    check("a guardian of another family cannot ring this phone",
          st >= 400, (st, out))

    st, out = call("/rest/v1/rpc/request_phone_ring", key=ANON,
                   body={"p_senior_profile_id": profile_id})
    check("a call with no session rings nothing", st >= 400, (st, out))

    st, out = ring(phone, profile_id)
    check("the parent's own phone cannot ring itself", st >= 400, (st, out))

    # A removed guardian keeps their row. Letting them go on making a phone
    # they no longer look after shout at the person holding it is the single
    # worst thing this feature could be used for.
    g2 = guardian("g2", "철수")
    # The pairing code is one-time, so g2 is attached directly — the point of
    # this case is the `removed` status, not how they got there.
    sql(f"""
        insert into public.guardian_senior_links
              (guardian_account_id, senior_profile_id, role, status)
        select ga.id, '{profile_id}', 'family', 'removed'
          from public.guardian_accounts ga
         where ga.display_name = '철수'
        on conflict (guardian_account_id, senior_profile_id)
        do update set status = 'removed';
    """)
    st, out = ring(g2, profile_id)
    check("a removed guardian cannot ring the phone they left",
          st >= 400, (st, out))

    # --- a phone with nothing to ring ---------------------------------------
    sql(f"update public.senior_devices set push_token = null "
        f"where install_id = '{install}'")
    st, out = ring(g1, profile_id)
    check("a phone that never checked in returns no row rather than a null token",
          st == 200 and out == [], (st, out))

finally:
    for pid in created_profiles:
        call(f"/rest/v1/senior_profiles?id=eq.{pid}", key=SERVICE, method="DELETE")
    for uid in created_users:
        call(f"/auth/v1/admin/users/{uid}", key=SERVICE, method="DELETE")
    print(f"\ncleaned up {len(created_users)} users and {len(created_profiles)} profiles")

print("\n" + ("ALL CHECKS PASSED" if not failures else f"{len(failures)} FAILED: {failures}"))
raise SystemExit(1 if failures else 0)
