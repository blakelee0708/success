"""End-to-end check of the Phase 4 schema against the live project.

Creates two guardians and one anonymous senior device, then walks the Phase 4
acceptance list: guardian signs in, senior profile is created and linked, the
parent's phone claims it by customer code, and home apps sync both ways.
Finishes by deleting every row and user it created.
"""
import json
import os
import urllib.request
import uuid

# The agent proxy rejects the default Python-urllib user agent with a 403.
urllib.request.install_opener(urllib.request.build_opener())
urllib.request.OpenerDirector.addheaders = [("User-Agent", "curl/8.5.0")]

REF = os.environ["SUPABASE_PROJECT_REF"]
MGMT = os.environ["SUPABASE_ACCESS_TOKEN"]
BASE = f"https://{REF}.supabase.co"


def mgmt_keys():
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{REF}/api-keys?reveal=true",
        headers={"Authorization": f"Bearer {MGMT}", "User-Agent": "curl/8.5.0"},
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
            "User-Agent": "curl/8.5.0",
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


def make_guardian(tag):
    email = f"phase4-{tag}-{uuid.uuid4().hex[:8]}@example.com"
    password = "phase4-test-" + uuid.uuid4().hex[:8]
    st, created = call(
        "/auth/v1/admin/users",
        key=SERVICE,
        body={"email": email, "password": password, "email_confirm": True},
    )
    assert st in (200, 201), (st, created)
    st, sess = call(
        "/auth/v1/token?grant_type=password",
        body={"email": email, "password": password},
    )
    assert st == 200, (st, sess)
    return created["id"], sess["access_token"]


created_users = []
created_profile = None

try:
    # --- guardian can login -------------------------------------------------
    g1_uid, g1 = make_guardian("g1")
    g2_uid, g2 = make_guardian("g2")
    created_users += [g1_uid, g2_uid]
    check("guardian signs in with a real session", bool(g1 and g2))

    st, acct = call("/rest/v1/rpc/ensure_guardian_account", token=g1,
                    body={"p_display_name": "김보호"})
    check("ensure_guardian_account creates the row", st == 200 and acct["display_name"] == "김보호", acct)
    st, again = call("/rest/v1/rpc/ensure_guardian_account", token=g1,
                     body={"p_display_name": "김보호"})
    check("ensure_guardian_account is idempotent", st == 200 and again["id"] == acct["id"], again)

    call("/rest/v1/rpc/ensure_guardian_account", token=g2, body={"p_display_name": "이보호"})

    # --- senior profile can be linked ---------------------------------------
    st, profile = call("/rest/v1/rpc/create_senior_profile", token=g1,
                       body={"p_display_name": "박순자", "p_age_band": "70s"})
    check("create_senior_profile returns a profile", st == 200 and profile.get("id"), profile)
    created_profile = profile["id"]
    code = profile["customer_code"]
    check("customer_code is 8 unambiguous chars",
          len(code) == 8 and not set(code) & set("O0I1"), code)

    # The link starts 'pending' - see `20261029010000_link_consent.sql`. A
    # guardian who makes a profile from their own dashboard sees nothing of it
    # until the parent's phone connects and answers the card, so the read that
    # used to come next is below, after the device has said 허락합니다.
    st, rows = call(f"/rest/v1/senior_profiles?id=eq.{created_profile}", token=g1, method="GET")
    check("a guardian waiting on consent reads nothing", st == 200 and rows == [], rows)

    st, rows = call(f"/rest/v1/senior_profiles?id=eq.{created_profile}", token=g2, method="GET")
    check("unlinked guardian is denied by RLS", st == 200 and rows == [], rows)

    st, links = call("/rest/v1/rpc/pending_guardian_links", token=g1, body={})
    check("and is told somebody has yet to answer", st == 200 and len(links or []) == 1, links)

    # --- senior device creation ---------------------------------------------
    st, anon_sess = call("/auth/v1/signup", body={})
    check("senior phone signs in anonymously", st == 200 and anon_sess.get("access_token"), anon_sess)
    device = anon_sess["access_token"]
    created_users.append(anon_sess["user"]["id"])
    install_id = "install-" + uuid.uuid4().hex[:10]

    st, claimed = call("/rest/v1/rpc/register_senior_device", token=device,
                       body={"p_customer_code": code, "p_install_id": install_id,
                             "p_device_label": "갤럭시 A16", "p_platform": "android",
                             "p_os_version": "14"})
    check("device claims its profile by code", st == 200 and claimed["id"] == created_profile, claimed)

    st, card = call("/rest/v1/rpc/pending_guardian_link", token=device, body={})
    check("the card is waiting the moment the phone connects",
          st == 200 and len(card or []) == 1, (st, card))
    approve(device)

    st, rows = call(f"/rest/v1/senior_profiles?id=eq.{created_profile}", token=g1, method="GET")
    check("the guardian reads the profile once consent is given",
          st == 200 and len(rows) == 1, rows)

    st, links = call(f"/rest/v1/guardian_senior_links?senior_profile_id=eq.{created_profile}",
                     token=g1, method="GET")
    check("link is primary/active", st == 200 and len(links) == 1
          and links[0]["role"] == "primary" and links[0]["status"] == "active", links)

    st, bad = call("/rest/v1/rpc/register_senior_device", token=device,
                   body={"p_customer_code": "ZZZZZZZZ", "p_install_id": install_id})
    check("a wrong code is rejected", st >= 400, bad)

    st, rows = call(f"/rest/v1/senior_profiles?id=eq.{created_profile}", token=device, method="GET")
    check("device reads its own profile", st == 200 and len(rows) == 1, rows)

    # replacing the phone retires the old install
    st, anon2 = call("/auth/v1/signup", body={})
    device2 = anon2["access_token"]
    created_users.append(anon2["user"]["id"])
    call("/rest/v1/rpc/register_senior_device", token=device2,
         body={"p_customer_code": code, "p_install_id": "install-" + uuid.uuid4().hex[:10]})
    st, devices = call(
        f"/rest/v1/senior_devices?senior_profile_id=eq.{created_profile}&select=install_id,is_active",
        token=g1, method="GET")
    active = [d for d in devices if d["is_active"]]
    check("only one device stays active after a phone swap",
          st == 200 and len(devices) == 2 and len(active) == 1, devices)
    check("the retired device loses access",
          call(f"/rest/v1/senior_profiles?id=eq.{created_profile}",
               token=device, method="GET")[1] == [], "old device can still read")

    # --- home app settings sync ---------------------------------------------
    apps = [
        {"client_id": "phone", "label": "전화", "icon_key": "phone", "sort_order": 0, "is_default": True},
        {"client_id": "message", "label": "문자", "icon_key": "message", "sort_order": 1, "is_default": True},
    ]
    st, saved = call("/rest/v1/rpc/replace_home_apps", token=device2,
                     body={"p_senior_profile_id": created_profile, "p_apps": apps})
    check("parent's phone uploads its home apps", st == 200 and len(saved) == 2, saved)

    st, seen = call(
        f"/rest/v1/home_apps?senior_profile_id=eq.{created_profile}&select=client_id,label,sort_order&order=sort_order",
        token=g1, method="GET")
    check("guardian sees the parent's home apps",
          st == 200 and [r["client_id"] for r in seen] == ["phone", "message"], seen)

    # guardian edits: rename, recolour, reorder, remove
    edited = [
        {"client_id": "message", "label": "문자 보내기", "icon_key": "message",
         "button_color": "orange", "sort_order": 0},
        {"client_id": "gallery", "label": "앨범", "icon_key": "gallery", "sort_order": 1},
    ]
    st, saved = call("/rest/v1/rpc/replace_home_apps", token=g1,
                     body={"p_senior_profile_id": created_profile, "p_apps": edited})
    check("guardian rewrites the button list", st == 200 and len(saved) == 2, saved)

    st, seen = call(
        f"/rest/v1/home_apps?senior_profile_id=eq.{created_profile}&select=client_id,label,button_color,sort_order&order=sort_order",
        token=device2, method="GET")
    check("parent's phone picks up the guardian's edit",
          st == 200 and [r["client_id"] for r in seen] == ["message", "gallery"]
          and seen[0]["label"] == "문자 보내기" and seen[0]["button_color"] == "orange", seen)

    st, denied = call("/rest/v1/rpc/replace_home_apps", token=g2,
                      body={"p_senior_profile_id": created_profile, "p_apps": []})
    check("unlinked guardian cannot rewrite the home screen", st >= 400, denied)

    st, seen = call(f"/rest/v1/home_apps?senior_profile_id=eq.{created_profile}", token=g2, method="GET")
    check("unlinked guardian cannot read the home screen", st == 200 and seen == [], seen)

    # screen mode / font size ride on the profile
    st, _ = call(f"/rest/v1/senior_profiles?id=eq.{created_profile}", token=device2,
                 method="PATCH", body={"screen_mode": "easy", "font_size": "extraLarge"})
    st, rows = call(f"/rest/v1/senior_profiles?id=eq.{created_profile}&select=screen_mode,font_size",
                    token=g1, method="GET")
    check("screen mode and font size sync to the guardian",
          st == 200 and rows[0]["screen_mode"] == "easy" and rows[0]["font_size"] == "extraLarge", rows)

finally:
    if created_profile:
        call(f"/rest/v1/senior_profiles?id=eq.{created_profile}", key=SERVICE, method="DELETE")
    for uid in created_users:
        call(f"/auth/v1/admin/users/{uid}", key=SERVICE, method="DELETE")
    print("\ncleaned up", len(created_users), "users and", 1 if created_profile else 0, "profile")

print("\n" + ("ALL CHECKS PASSED" if not failures else f"{len(failures)} FAILED: {failures}"))
raise SystemExit(1 if failures else 0)
