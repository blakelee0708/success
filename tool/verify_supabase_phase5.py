"""End-to-end check of the Phase 5 pairing schema against the live project.

Walks both pairing paths, recovery, the family-guardian invite and the change
of primary guardian — including the refusals that make each of them mean
something — then deletes every row and user it created.

Run with:
    SSL_CERT_FILE=/root/.ccr/ca-bundle.crt python3 tool/verify_supabase_phase5.py
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


def guardian(tag):
    """A confirmed guardian with a session and a guardian_accounts row."""
    email = f"phase5-{tag}-{uuid.uuid4().hex[:8]}@example.com"
    password = "phase5-test-" + uuid.uuid4().hex[:8]
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
    # --- 경로 B: the parent's phone shows a code, the guardian types it ------
    phone, install = device()
    st, link = call("/rest/v1/rpc/start_senior_pairing", token=phone,
                    body={"p_install_id": install, "p_platform": "android"})
    check("a phone with no guardian can start pairing on its own",
          st == 200 and link.get("code"), link)
    check("the code the senior reads out is 4 digits",
          len(link["code"]) == 4 and link["code"].isdigit(), link.get("code"))
    check("pairing mode is senior_shares_code", link["mode"] == "senior_shares_code", link)
    remember({"id": link["senior_profile_id"]})

    st, again = call("/rest/v1/rpc/start_senior_pairing", token=phone,
                     body={"p_install_id": install})
    check("asking twice does not create a second parent",
          st == 200 and again["senior_profile_id"] == link["senior_profile_id"], again)

    g1 = guardian("g1")
    st, profile = call("/rest/v1/rpc/claim_senior_pairing_code", token=g1,
                       body={"p_code": link["code"], "p_display_name": "어머니",
                             "p_phone_number": "01012345678"})
    check("the guardian claims it and names the parent",
          st == 200 and profile.get("display_name") == "어머니", profile)
    profile_id = profile["id"]

    # Reading out a number says *here is my number*, not *you may see how I
    # am*. The card on the parent's own phone is the second half of 경로 B
    # since `20261029010000_link_consent.sql`.
    st, rows = call(f"/rest/v1/senior_profiles?id=eq.{profile_id}", token=g1, method="GET")
    check("the guardian sees nothing until the parent agrees",
          st == 200 and rows == [], rows)
    approve(phone)

    st, rows = call(f"/rest/v1/senior_profiles?id=eq.{profile_id}", token=g1, method="GET")
    check("the guardian can now read the profile", st == 200 and len(rows) == 1, rows)

    st, links = call(
        f"/rest/v1/guardian_senior_links?senior_profile_id=eq.{profile_id}&select=role,status",
        token=g1, method="GET")
    check("the claiming guardian is primary",
          st == 200 and links[0]["role"] == "primary", links)

    st, reused = call("/rest/v1/rpc/claim_senior_pairing_code", token=guardian("g-thief"),
                      body={"p_code": link["code"], "p_display_name": "가로채기"})
    check("a spent code cannot be claimed again", reused_rejected := st >= 400, reused)

    st, bogus = call("/rest/v1/rpc/claim_senior_pairing_code", token=g1,
                     body={"p_code": "0000", "p_display_name": "없음"})
    check("a code nobody holds is refused", st >= 400, bogus)

    # --- 경로 A: the guardian creates the profile and texts a link ----------
    g2 = guardian("g2")
    st, invite = call("/rest/v1/rpc/create_senior_invite", token=g2,
                      body={"p_display_name": "아버지"})
    check("an invite carries both a token and a code",
          st == 200 and invite.get("token") and invite.get("code"), invite)
    check("the invite code is 6 digits, being read out rather than tapped",
          len(invite["code"]) == 6, invite.get("code"))
    remember({"id": invite["senior_profile_id"]})

    phone2, install2 = device()
    st, claimed = call("/rest/v1/rpc/redeem_senior_invite", token=phone2,
                       body={"p_install_id": install2, "p_token": invite["token"]})
    check("the parent's phone redeems the link's token",
          st == 200 and claimed["id"] == invite["senior_profile_id"], claimed)
    # The link g2 made from their own dashboard has been waiting for a phone
    # to ask; redeeming is when the card appears.
    st, card = call("/rest/v1/rpc/pending_guardian_link", token=phone2, body={})
    check("the card is waiting on the phone that just installed",
          st == 200 and len(card or []) == 1, (st, card))
    approve(phone2)

    # The referrer does not survive every install; the code is the fallback.
    # A fresh guardian, because a second parent for g2 would now need the
    # family plan — Phase 6 put that gate on create_senior_invite.
    st, invite2 = call("/rest/v1/rpc/create_senior_invite", token=guardian("g2b"),
                       body={"p_display_name": "작은아버지"})
    remember({"id": invite2["senior_profile_id"]})
    phone3, install3 = device()
    st, claimed2 = call("/rest/v1/rpc/redeem_senior_invite", token=phone3,
                        body={"p_install_id": install3, "p_code": invite2["code"]})
    check("the same invite works by code when the link did not survive",
          st == 200 and claimed2["id"] == invite2["senior_profile_id"], claimed2)
    approve(phone3)

    st, neither = call("/rest/v1/rpc/redeem_senior_invite", token=phone3,
                       body={"p_install_id": install3})
    check("redeeming with neither a token nor a code is refused", st >= 400, neither)

    # --- Recovery: reinstall restores the existing parent -------------------
    call("/rest/v1/rpc/replace_home_apps", token=phone,
         body={"p_senior_profile_id": profile_id, "p_apps": [
             {"client_id": "phone", "label": "전화", "icon_key": "phone", "sort_order": 0}]})

    st, rec = call("/rest/v1/rpc/create_recovery_code", token=g1,
                   body={"p_senior_profile_id": profile_id})
    check("the guardian can issue a recovery code", st == 200 and rec.get("code"), rec)

    st, denied = call("/rest/v1/rpc/create_recovery_code", token=g2,
                      body={"p_senior_profile_id": profile_id})
    check("an unrelated guardian cannot issue one", st >= 400, denied)

    new_phone, new_install = device()
    st, restored = call("/rest/v1/rpc/redeem_recovery_code", token=new_phone,
                        body={"p_code": rec["code"], "p_install_id": new_install})
    check("a replacement phone restores the existing parent, not a new one",
          st == 200 and restored["id"] == profile_id, restored)

    st, apps = call(
        f"/rest/v1/home_apps?senior_profile_id=eq.{profile_id}&select=client_id",
        token=new_phone, method="GET")
    check("the home screen comes back with it",
          st == 200 and [a["client_id"] for a in apps] == ["phone"], apps)

    st, devices = call(
        f"/rest/v1/senior_devices?senior_profile_id=eq.{profile_id}&select=install_id,is_active",
        token=g1, method="GET")
    active = [d for d in devices if d["is_active"]]
    check("the old phone is deactivated by the recovery",
          st == 200 and len(active) == 1 and active[0]["install_id"] == new_install, devices)
    check("the old phone loses access",
          call(f"/rest/v1/senior_profiles?id=eq.{profile_id}", token=phone,
               method="GET")[1] == [], "old device can still read")

    # --- Family guardians, free ---------------------------------------------
    st, fam = call("/rest/v1/rpc/create_family_invite", token=g1,
                   body={"p_senior_profile_id": profile_id})
    check("the primary guardian can invite family", st == 200 and fam.get("code"), fam)

    g3 = guardian("g3")
    st, joined = call("/rest/v1/rpc/redeem_family_invite", token=g3,
                      body={"p_code": fam["code"]})
    check("a sibling joins with no payment involved",
          st == 200 and joined["id"] == profile_id, joined)
    approve(new_phone)

    st, roles = call(
        f"/rest/v1/guardian_senior_links?senior_profile_id=eq.{profile_id}&select=role",
        token=g3, method="GET")
    check("an invited guardian joins as family, never primary",
          st == 200 and any(r["role"] == "family" for r in roles)
          and sum(1 for r in roles if r["role"] == "primary") == 1, roles)

    # --- Changing the primary guardian --------------------------------------
    st, requested = call("/rest/v1/rpc/request_primary_guardian", token=g3,
                         body={"p_senior_profile_id": profile_id})
    check("a family guardian may ask to become primary", st == 200, requested)

    st, self_approved = call("/rest/v1/rpc/resolve_primary_guardian", token=g3,
                             body={"p_senior_profile_id": profile_id, "p_approve": True})
    check("a guardian cannot approve their own request", st >= 400, self_approved)

    st, other_approved = call("/rest/v1/rpc/resolve_primary_guardian", token=g1,
                              body={"p_senior_profile_id": profile_id, "p_approve": True})
    check("the existing primary cannot approve it either", st >= 400, other_approved)

    st, roles = call(
        f"/rest/v1/guardian_senior_links?senior_profile_id=eq.{profile_id}"
        "&role=eq.primary&select=guardian_account_id", token=g1, method="GET")
    check("nothing changed while it was unapproved", st == 200 and len(roles) == 1, roles)

    st, approved = call("/rest/v1/rpc/resolve_primary_guardian", token=new_phone,
                        body={"p_senior_profile_id": profile_id, "p_approve": True})
    check("the senior's own phone can approve it", st == 200, approved)

    st, after = call(
        f"/rest/v1/guardian_senior_links?senior_profile_id=eq.{profile_id}&select=role",
        token=g1, method="GET")
    check("there is still exactly one primary afterwards",
          st == 200 and sum(1 for r in after if r["role"] == "primary") == 1, after)

    st, nothing = call("/rest/v1/rpc/resolve_primary_guardian", token=new_phone,
                       body={"p_senior_profile_id": profile_id, "p_approve": True})
    check("answering twice is refused", st >= 400, nothing)

    # A refusal has to be possible, not just an approval.
    st, _ = call("/rest/v1/rpc/request_primary_guardian", token=g1,
                 body={"p_senior_profile_id": profile_id})
    st, declined = call("/rest/v1/rpc/resolve_primary_guardian", token=new_phone,
                        body={"p_senior_profile_id": profile_id, "p_approve": False})
    check("the senior can refuse", st == 200
          and declined.get("pending_primary_guardian_id") is None, declined)

    st, after_decline = call(
        f"/rest/v1/guardian_senior_links?senior_profile_id=eq.{profile_id}&select=role",
        token=g1, method="GET")
    check("a refusal leaves the primary where it was",
          st == 200 and sum(1 for r in after_decline if r["role"] == "primary") == 1,
          after_decline)

finally:
    for pid in created_profiles:
        call(f"/rest/v1/senior_profiles?id=eq.{pid}", key=SERVICE, method="DELETE")
    for uid in created_users:
        call(f"/auth/v1/admin/users/{uid}", key=SERVICE, method="DELETE")
    print(f"\ncleaned up {len(created_users)} users and {len(created_profiles)} profiles")

print("\n" + ("ALL CHECKS PASSED" if not failures else f"{len(failures)} FAILED: {failures}"))
raise SystemExit(1 if failures else 0)
