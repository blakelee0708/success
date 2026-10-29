"""End-to-end check of `guardians_for_senior` against the live project.

Who may know who is looking after this parent. Before this function existed,
`guardian_accounts` had one policy — auth_user_id = auth.uid() — and the
embedded read in `guardiansFor` inherited it, so the senior's phone saw
nothing at all about its guardians and each guardian saw only their own row.
긴급 연락's 보호자 button was built on that.

Run with:
    SSL_CERT_FILE=/root/.ccr/ca-bundle.crt python3 tool/verify_supabase_roster.py
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
    email = f"roster-{tag}-{uuid.uuid4().hex[:8]}@example.com"
    password = "roster-test-" + uuid.uuid4().hex[:8]
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



def roster(token, profile_id):
    return call("/rest/v1/rpc/guardians_for_senior", token=token,
                body={"p_senior_profile_id": profile_id})


def by_role(rows):
    return {r["role"]: r for r in (rows or [])}


try:
    # One parent, their phone, and their one child. 무조건 자녀 하나, 부모 하나.
    phone, install = device()
    st, link = call("/rest/v1/rpc/start_senior_pairing", token=phone,
                    body={"p_install_id": install, "p_platform": "android"})
    assert st == 200, (st, link)
    profile_id = link["senior_profile_id"]
    remember({"id": profile_id})

    g1 = guardian("g1")
    call("/rest/v1/rpc/ensure_guardian_account", token=g1,
         body={"p_display_name": "영희", "p_phone_number": "01011110001"})
    st, _ = call("/rest/v1/rpc/claim_senior_pairing_code", token=g1,
                 body={"p_code": link["code"], "p_display_name": "어머니"})
    approve(phone)
    assert st == 200

    # --- the senior's own phone ---------------------------------------------
    # This is the one the SOS button depends on, and the one that used to come
    # back as two rows of nulls.
    st, rows = roster(phone, profile_id)
    check("the parent's phone can read its own roster", st == 200, (st, rows))
    check("it sees its one guardian", len(rows or []) == 1, rows)

    seen = by_role(rows)
    check("with their names", seen.get("primary", {}).get("display_name") == "영희",
          seen.get("primary"))
    check("and the number 긴급 연락 needs",
          seen.get("primary", {}).get("phone_number") == "01011110001",
          seen.get("primary"))
    check("대표 보호자 comes first, because that is who the button calls",
          rows and rows[0]["role"] == "primary", rows)
    check("and no email is handed to the phone",
          all(r.get("email") is None for r in rows), rows)

    # --- the guardian themselves --------------------------------------------
    st, rows = roster(g1, profile_id)
    seen = by_role(rows)
    check("the guardian can read the roster", st == 200 and len(rows) == 1, rows)
    check("and sees their own email",
          seen.get("primary", {}).get("email") is not None, seen.get("primary"))

    # --- nobody else ---------------------------------------------------------
    outsider = guardian("outsider")
    st, rows = roster(outsider, profile_id)
    check("a guardian of another family gets nothing",
          st != 200 or not rows, (st, rows))

    other_phone, _ = device()
    st, rows = roster(other_phone, profile_id)
    check("an unrelated phone gets nothing", st != 200 or not rows, (st, rows))

    st, rows = roster(None, profile_id)
    check("a caller with no session gets nothing", st != 200 or not rows,
          (st, rows))

    # --- a removed guardian leaves the roster -------------------------------
    st, _ = call("/rest/v1/guardian_senior_links?senior_profile_id=eq."
                 + profile_id, key=SERVICE, method="PATCH",
                 body={"status": "removed"})
    st, rows = roster(phone, profile_id)
    check("a removed guardian is not on it", st == 200 and not rows, rows)

finally:
    for pid in created_profiles:
        call(f"/rest/v1/senior_profiles?id=eq.{pid}", key=SERVICE, method="DELETE")
    for uid in created_users:
        call(f"/auth/v1/admin/users/{uid}", key=SERVICE, method="DELETE")
    print(f"\ncleaned up {len(created_users)} users and {len(created_profiles)} profiles")

print("\n" + ("ALL CHECKS PASSED" if not failures else f"{len(failures)} FAILED: {failures}"))
raise SystemExit(1 if failures else 0)
