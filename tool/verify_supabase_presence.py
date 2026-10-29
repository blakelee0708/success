"""End-to-end check of 안부 신호 — `touch_senior_device` — against the live project.

The parent's phone reports that it is in use; the guardian reads how long ago.
Checks that a report lands, that it moves `last_seen_at` and nothing else, that
one phone cannot report for another, that a retired phone cannot take the
profile back by reporting, and that a call with no session touches nothing.
Deletes every row and user it created.

Run with:
    SSL_CERT_FILE=/root/.ccr/ca-bundle.crt python3 tool/verify_supabase_presence.py
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
    """A Management API read, for the two questions no client can answer:
    whether a column exists and whether a function does."""
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


def approve(phone_token):
    """The senior says 허락합니다 on their own phone.

    Every path that attaches a guardian writes `pending` since
    `20261029010000_link_consent.sql`, so a script standing in for the
    parent's phone has to answer the card before anything that needs an
    active link. A loop, so any card left waiting is answered too.
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


def guardian(tag):
    """A confirmed guardian with a session and a guardian_accounts row."""
    email = f"presence-{tag}-{uuid.uuid4().hex[:8]}@example.com"
    password = "presence-test-" + uuid.uuid4().hex[:8]
    st, made = call("/auth/v1/admin/users", key=SERVICE,
                    body={"email": email, "password": password, "email_confirm": True})
    assert st in (200, 201), (st, made)
    created_users.append(made["id"])
    st, sess = call("/auth/v1/token?grant_type=password",
                    body={"email": email, "password": password})
    assert st == 200, (st, sess)
    token = sess["access_token"]
    call("/rest/v1/rpc/ensure_guardian_account", token=token, body={"p_display_name": tag})
    return token


def device():
    """A parent's phone: an anonymous session and a fresh install id."""
    st, sess = call("/auth/v1/signup", body={})
    assert st == 200, (st, sess)
    created_users.append(sess["user"]["id"])
    return sess["access_token"], "install-" + uuid.uuid4().hex[:10]


def remember(profile):
    if isinstance(profile, dict) and profile.get("id"):
        created_profiles.append(profile["id"])
    return profile


def device_row(token, profile_id):
    st, rows = call(
        f"/rest/v1/senior_devices?senior_profile_id=eq.{profile_id}"
        "&select=install_id,last_seen_at,is_active,battery_percent,is_charging,"
        "ringer_mode,status_read_at",
        token=token, method="GET")
    return st, rows


def active(rows):
    return [r for r in rows if r["is_active"]][0]


try:
    # A parent's phone, paired the 경로 B way, with a guardian attached.
    phone, install = device()
    st, link = call("/rest/v1/rpc/start_senior_pairing", token=phone,
                    body={"p_install_id": install, "p_platform": "android"})
    assert st == 200, (st, link)
    profile_id = link["senior_profile_id"]
    remember({"id": profile_id})
    g1 = guardian("g1")
    st, _ = call("/rest/v1/rpc/claim_senior_pairing_code", token=g1,
                 body={"p_code": link["code"], "p_display_name": "어머니"})
    approve(phone)
    assert st == 200

    st, rows = device_row(g1, profile_id)
    before = rows[0]["last_seen_at"]
    check("the guardian can read the parent's check-in at all",
          st == 200 and len(rows) == 1, rows)

    # --- the report itself ---------------------------------------------------
    st, _ = call("/rest/v1/rpc/touch_senior_device", token=phone,
                 body={"p_install_id": install})
    check("the parent's phone may report that it is in use", st in (200, 204), st)

    st, rows = device_row(g1, profile_id)
    check("the report moves last_seen_at forward",
          st == 200 and rows[0]["last_seen_at"] > before,
          (before, rows[0]["last_seen_at"]))
    check("reporting does not disturb is_active", rows[0]["is_active"] is True, rows)

    # --- 기기 상태 rides on the same call ------------------------------------
    st, _ = call("/rest/v1/rpc/touch_senior_device", token=phone,
                 body={"p_install_id": install, "p_battery_percent": 61,
                       "p_is_charging": False, "p_ringer_mode": "vibrate",
                       "p_status_read_at": "2026-10-20T14:30:00Z"})
    check("the check-in carries the battery and the ringer", st in (200, 204), st)

    st, rows = device_row(g1, profile_id)
    r = active(rows)
    check("the guardian reads the battery the phone sent",
          r["battery_percent"] == 61 and r["ringer_mode"] == "vibrate"
          and r["is_charging"] is False, r)
    check("the reading keeps the time the phone took it, not the time it arrived",
          r["status_read_at"].startswith("2026-10-20T14:30"), r["status_read_at"])

    # A phone that could read nothing must not erase what it reported before.
    # Writing the nulls through would take the card from 61% to
    # 아직 받지 못했어요 for no reason the guardian could see.
    st, _ = call("/rest/v1/rpc/touch_senior_device", token=phone,
                 body={"p_install_id": install})
    st, rows = device_row(g1, profile_id)
    kept = active(rows)
    check("a check-in with no reading leaves the last one standing",
          kept["battery_percent"] == 61 and kept["ringer_mode"] == "vibrate", kept)
    check("and it is still a check-in", kept["last_seen_at"] > r["last_seen_at"],
          (r["last_seen_at"], kept["last_seen_at"]))

    # The column refuses nonsense rather than storing it for the card to draw.
    st, refused = call("/rest/v1/rpc/touch_senior_device", token=phone,
                       body={"p_install_id": install, "p_battery_percent": 140})
    check("a battery over 100 is refused", st >= 400, (st, refused))
    st, refused = call("/rest/v1/rpc/touch_senior_device", token=phone,
                       body={"p_install_id": install, "p_ringer_mode": "loud"})
    check("a ringer mode nobody defined is refused", st >= 400, (st, refused))

    st, rows = device_row(g1, profile_id)
    check("and neither refusal disturbed the stored reading",
          active(rows)["battery_percent"] == 61, rows)

    # --- the ring's address is gone, and so is the gate ---------------------
    # 소리 울리기 is out of the product. An FCM token is an address, and with
    # nothing left to send to it, holding one would be collecting something
    # for no purpose - so `20261029060000_drop_ring.sql` takes the column and
    # the gate away. The guardian's own token is untouched: theirs is what
    # tells a child their parent wrote to them.
    cols = sql("select column_name from information_schema.columns "
               "where table_schema = 'public' "
               "and table_name = 'senior_devices' "
               "and column_name = 'push_token'")
    check("the parent's phone has nowhere to store a push token", cols == [],
          cols)

    fns = sql("select p.proname from pg_proc p "
              "join pg_namespace n on n.oid = p.pronamespace "
              "where n.nspname = 'public' "
              "and p.proname = 'request_phone_ring'")
    check("and the gate that rang it no longer exists", fns == [], fns)

    guardian_col = sql("select column_name from information_schema.columns "
                       "where table_schema = 'public' "
                       "and table_name = 'guardian_accounts' "
                       "and column_name = 'push_token'")
    check("the child's own token is untouched", len(guardian_col) == 1,
          guardian_col)

    st, _ = call("/rest/v1/rpc/touch_senior_device", token=phone,
                 body={"p_install_id": install, "p_push_token": "fcm-1"})
    check("a check-in still carrying one is refused rather than ignored",
          st >= 400, st)

    # --- one phone may not report for another -------------------------------
    other, _other_install = device()
    st, _ = call("/rest/v1/rpc/touch_senior_device", token=other,
                 body={"p_install_id": install})
    st2, rows2 = device_row(g1, profile_id)
    check("another phone naming this install changes nothing",
          st2 == 200 and active(rows2)["last_seen_at"] == active(rows)["last_seen_at"],
          (active(rows)["last_seen_at"], active(rows2)["last_seen_at"]))

    # --- a retired phone cannot take the profile back -----------------------
    # The parent replaces the handset. The old one still has the app on it and
    # will still resume; a report from it must not flip is_active back, or the
    # unique index on one active device per profile starts rejecting the real
    # phone.
    st, recovery = call("/rest/v1/rpc/create_recovery_code", token=g1,
                        body={"p_senior_profile_id": profile_id})
    assert st == 200, (st, recovery)
    new_phone, new_install = device()
    st, claimed = call("/rest/v1/rpc/redeem_recovery_code", token=new_phone,
                       body={"p_code": recovery["code"],
                             "p_install_id": new_install})
    check("the new phone takes over", st == 200, claimed)

    st, _ = call("/rest/v1/rpc/touch_senior_device", token=phone,
                 body={"p_install_id": install})
    st, rows = device_row(g1, profile_id)
    live = [r for r in rows if r["is_active"]]
    check("a report from the retired phone leaves exactly one active phone",
          st == 200 and len(live) == 1, rows)
    check("and it is the new one",
          live and live[0]["install_id"] == new_install, live)
    check("the new phone starts with no reading of its own, not the old one's",
          live and live[0]["battery_percent"] is None, live)

    # --- an unauthenticated caller gets nowhere ------------------------------
    st, _ = call("/rest/v1/rpc/touch_senior_device",
                 body={"p_install_id": new_install})
    st2, rows2 = device_row(g1, profile_id)
    after = active(rows2)["last_seen_at"]
    check("a call with no session touches nothing",
          active(rows)["last_seen_at"] == after, (st, after))

finally:
    for pid in created_profiles:
        call(f"/rest/v1/senior_profiles?id=eq.{pid}", key=SERVICE, method="DELETE")
    for uid in created_users:
        call(f"/auth/v1/admin/users/{uid}", key=SERVICE, method="DELETE")
    print(f"\ncleaned up {len(created_users)} users and {len(created_profiles)} profiles")

print("\n" + ("ALL CHECKS PASSED" if not failures else f"{len(failures)} FAILED: {failures}"))
raise SystemExit(1 if failures else 0)
