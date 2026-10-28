"""Checks 문의하기's number - `ensure_senior_support_code` - against the live project.

The number an elderly person reads out to the support desk. The case it exists
for is the one nothing else in the app covers: a senior with **no family on
the phone at all**, who has nobody to ask why their phone is doing something,
on an app that *is* their home screen.

Two things here cannot be proved by reading the SQL, and both are why this
script exists. One, every profile has a number whichever path created it -
the trigger is what makes that true, and a line in each creating function
would have missed whichever one was added next. Two, a phone with no profile
**gets one**, because the senior this is for has never had one made for them.

Deletes every row and user it created.

Run with:
    SSL_CERT_FILE=/root/.ccr/ca-bundle.crt python3 tool/verify_supabase_support_code.py
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


def check(name, cond, detail=""):
    print(("PASS  " if cond else "FAIL  ") + name + ("" if cond else f"  <- {detail}"))
    if not cond:
        failures.append(name)


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




try:
    # --- a phone with no profile gets a number, and a profile with it -------
    # The senior this is for. Nobody has ever connected them, so nothing has
    # created a profile; 번호 보여주기 does it the same way, and 연결됨 has
    # never meant that a profile exists.
    phone, install = device()
    st, code = call("/rest/v1/rpc/ensure_senior_support_code", token=phone,
                    body={"p_install_id": install})
    check("a phone with no family gets a number", st == 200 and code, (st, code))
    check("it is six digits", isinstance(code, str) and code.isdigit()
          and len(code) == 6, code)
    check("and it does not open with a zero", str(code)[0] != "0", code)

    st, rows = call(f"/rest/v1/senior_profiles?support_code=eq.{code}&select=id",
                    key=SERVICE, method="GET")
    check("the profile was created", st == 200 and len(rows) == 1, rows)
    lone_profile = rows[0]["id"] if rows else None
    if lone_profile:
        created_profiles.append(lone_profile)

    # --- asking twice is the same number -----------------------------------
    # A senior reading it out to the desk may well put the phone down and open
    # the card again. A number that changed between the two would send them
    # back to the start of a telephone call they have already had.
    st, again = call("/rest/v1/rpc/ensure_senior_support_code", token=phone,
                     body={"p_install_id": install})
    check("asking again gives the same number", again == code, (code, again))

    st2, dupes = call("/rest/v1/senior_devices?install_id=eq." + install
                      + "&select=id", key=SERVICE, method="GET")
    check("and does not make a second phone row", len(dupes) == 1, dupes)

    # --- every creating path fills it ---------------------------------------
    # The trigger is the reason, and the reason for the trigger: four
    # functions insert a profile and the one that gets forgotten is the one
    # added next.
    g1 = guardian("support")
    st, made = call("/rest/v1/rpc/create_senior_profile", token=g1,
                    body={"p_display_name": "어머니"})
    remember(made)
    check("create_senior_profile fills it",
          st == 200 and str(made.get("support_code", "")).isdigit(), made)

    # A second guardian, because the family plan gates a *second* parent and
    # g1 has just made one.
    g2 = guardian("invite")
    st, invite = call("/rest/v1/rpc/create_senior_invite", token=g2,
                      body={"p_display_name": "아버지"})
    assert st == 200, (st, invite)
    st, rows = call("/rest/v1/senior_profiles?id=eq."
                    + invite["senior_profile_id"] + "&select=id,support_code",
                    key=SERVICE, method="GET")
    if rows:
        created_profiles.append(rows[0]["id"])
    check("create_senior_invite fills it",
          rows and str(rows[0]["support_code"]).isdigit(), rows)

    other, other_install = device()
    st, pair = call("/rest/v1/rpc/start_senior_pairing", token=other,
                    body={"p_install_id": other_install})
    assert st == 200, (st, pair)
    st, rows = call("/rest/v1/senior_profiles?id=eq."
                    + pair["senior_profile_id"] + "&select=id,support_code",
                    key=SERVICE, method="GET")
    if rows:
        created_profiles.append(rows[0]["id"])
    check("start_senior_pairing fills it",
          rows and str(rows[0]["support_code"]).isdigit(), rows)

    # --- it is a profile's number, not a phone's ----------------------------
    # One profile, two handsets over its life. The number the senior has
    # already read out to somebody must survive the new phone.
    st, recovery = call("/rest/v1/rpc/create_recovery_code", token=g1,
                        body={"p_senior_profile_id": made["id"]})
    assert st == 200, (st, recovery)
    new_phone, new_install = device()
    st, claimed = call("/rest/v1/rpc/redeem_recovery_code", token=new_phone,
                       body={"p_code": recovery["code"],
                             "p_install_id": new_install})
    assert st == 200, (st, claimed)
    st, moved = call("/rest/v1/rpc/ensure_senior_support_code", token=new_phone,
                     body={"p_install_id": new_install})
    check("a replaced phone reads the same number",
          moved == made["support_code"], (made["support_code"], moved))

    # --- 문의하기 mints no secret ------------------------------------------
    # It is not a way of connecting anybody. A 4-digit pair code nobody asked
    # for, live for ten minutes, would be a secret created by a screen with no
    # use for one.
    st, links = call("/rest/v1/pair_links?senior_profile_id=eq."
                     + str(lone_profile) + "&select=id",
                     key=SERVICE, method="GET")
    check("the 문의 number creates no pair link",
          st == 200 and len(links) == 0, links)

    # --- the refusals -------------------------------------------------------
    st, denied = call("/rest/v1/rpc/ensure_senior_support_code",
                      body={"p_install_id": install})
    check("a call with no session is refused", st >= 400, (st, denied))

    st, denied = call("/rest/v1/rpc/generate_support_code", token=phone, body={})
    check("the generator is not callable by a client", st >= 400, (st, denied))

    st, denied = call("/rest/v1/rpc/fill_support_code", token=phone, body={})
    check("nor is the trigger function", st >= 400, (st, denied))

    # --- uniqueness ---------------------------------------------------------
    st, all_rows = call("/rest/v1/senior_profiles?select=support_code",
                        key=SERVICE, method="GET")
    codes = [r["support_code"] for r in all_rows]
    check("every profile has one", all(codes), all_rows)
    check("and no two share it", len(codes) == len(set(codes)), len(codes))

finally:
    for pid in created_profiles:
        call(f"/rest/v1/senior_profiles?id=eq.{pid}", key=SERVICE, method="DELETE")
    for uid in created_users:
        call(f"/auth/v1/admin/users/{uid}", key=SERVICE, method="DELETE")
    print(f"\ncleaned up {len(created_users)} users and {len(created_profiles)} profiles")

print("\n" + ("ALL CHECKS PASSED" if not failures else f"{len(failures)} FAILED: {failures}"))
raise SystemExit(1 if failures else 0)
