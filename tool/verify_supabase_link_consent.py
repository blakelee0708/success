"""End-to-end check of 가족 연결 동의 against the live project.

A guardian typed a number and was connected. Nothing ever asked the person
whose phone it is: on the install-SMS path they did nothing at all, and a
sibling joining by invitation was never mentioned to their mother. Play's
rule for an app that looks at another adult's phone is that the adult knows
and agrees, on their own device.

**This is the only thing that proves it.** `flutter test` runs on the
in-memory twins, and the twin links immediately unless `pendingLinkConsent`
is set - mirroring the server by default would have meant rewriting the
harness of every test that connects a family. So the server rule lives here.

Run with:
    SSL_CERT_FILE=/root/.ccr/ca-bundle.crt python3 tool/verify_supabase_link_consent.py
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




def links_of(profile_id):
    st, rows = call(
        "/rest/v1/guardian_senior_links?senior_profile_id=eq." + profile_id
        + "&select=id,role,status",
        key=SERVICE, method="GET")
    return rows or []


try:
    # --- 경로 B: the number the parent read out ----------------------------
    phone, install = device()
    st, link = call("/rest/v1/rpc/start_senior_pairing", token=phone,
                    body={"p_install_id": install, "p_platform": "android"})
    assert st == 200, (st, link)
    profile_id = link["senior_profile_id"]
    remember({"id": profile_id})

    g1 = guardian("g1")
    call("/rest/v1/rpc/ensure_guardian_account", token=g1,
         body={"p_display_name": "영희"})
    st, _ = call("/rest/v1/rpc/claim_senior_pairing_code", token=g1,
                 body={"p_code": link["code"], "p_display_name": "어머니"})
    check("typing the code attaches a guardian", st == 200, st)

    rows = links_of(profile_id)
    check("and leaves them waiting, not connected",
          len(rows) == 1 and rows[0]["status"] == "pending", rows)

    # --- the guardian sees nothing about the parent yet ---------------------
    st, mine = call("/rest/v1/senior_profiles?select=id", token=g1,
                    method="GET")
    check("a waiting guardian has no parent on their dashboard",
          st != 200 or not mine, (st, mine))

    st, waiting = call("/rest/v1/rpc/pending_guardian_links", token=g1, body={})
    check("but is told somebody is thinking about it",
          st == 200 and len(waiting or []) == 1, (st, waiting))

    # --- the card on the senior's own phone ---------------------------------
    st, card = call("/rest/v1/rpc/pending_guardian_link", token=phone, body={})
    check("the parent's phone is asked, and told who is asking",
          st == 200 and len(card or []) == 1
          and card[0]["guardian_name"] == "영희", (st, card))
    link_id = card[0]["link_id"] if card else None

    # --- nobody else may answer it ------------------------------------------
    st, answered = call("/rest/v1/rpc/answer_guardian_link", token=g1,
                        body={"p_link_id": link_id, "p_approve": True})
    check("the guardian cannot approve their own link",
          st != 200 or answered is False, (st, answered))
    check("and it is still waiting after they tried",
          links_of(profile_id)[0]["status"] == "pending",
          links_of(profile_id))

    other = guardian("intruder")
    st, answered = call("/rest/v1/rpc/answer_guardian_link", token=other,
                        body={"p_link_id": link_id, "p_approve": True})
    check("nor can an unrelated account",
          st != 200 or answered is False, (st, answered))

    st, answered = call("/rest/v1/rpc/answer_guardian_link", token=None,
                        body={"p_link_id": link_id, "p_approve": True})
    check("nor a caller with no session at all",
          st != 200 or answered is False, (st, answered))

    # --- 허락합니다 ----------------------------------------------------------
    st, answered = call("/rest/v1/rpc/answer_guardian_link", token=phone,
                        body={"p_link_id": link_id, "p_approve": True})
    check("the parent's own phone may approve", st == 200 and answered is True,
          (st, answered))
    check("and the link is active", links_of(profile_id)[0]["status"] == "active",
          links_of(profile_id))

    st, mine = call("/rest/v1/senior_profiles?select=id", token=g1,
                    method="GET")
    check("the guardian's dashboard has the parent now",
          st == 200 and len(mine or []) == 1, (st, mine))

    st, card = call("/rest/v1/rpc/pending_guardian_link", token=phone, body={})
    check("and the card is gone", st == 200 and not card, (st, card))

    st, answered = call("/rest/v1/rpc/answer_guardian_link", token=phone,
                        body={"p_link_id": link_id, "p_approve": False})
    check("answering twice changes nothing", st == 200 and answered is False,
          (st, answered))
    check("an answered link is not re-openable",
          links_of(profile_id)[0]["status"] == "active", links_of(profile_id))

    # --- 가족 초대: the gap that was widest --------------------------------
    st, invite = call("/rest/v1/rpc/create_family_invite", token=g1,
                      body={"p_senior_profile_id": profile_id})
    assert st == 200, (st, invite)
    g2 = guardian("g2")
    call("/rest/v1/rpc/ensure_guardian_account", token=g2,
         body={"p_display_name": "철수"})
    st, _ = call("/rest/v1/rpc/redeem_family_invite", token=g2,
                 body={"p_code": invite["code"]})
    check("a sibling joining also waits", st == 200
          and sorted(r["status"] for r in links_of(profile_id))
              == ["active", "pending"], links_of(profile_id))

    st, card = call("/rest/v1/rpc/pending_guardian_link", token=phone, body={})
    check("and the parent is told it is the sibling",
          st == 200 and len(card or []) == 1
          and card[0]["guardian_name"] == "철수", (st, card))

    # --- 아니요 ------------------------------------------------------------
    st, answered = call("/rest/v1/rpc/answer_guardian_link", token=phone,
                        body={"p_link_id": card[0]["link_id"],
                              "p_approve": False})
    check("a refusal is accepted", st == 200 and answered is True,
          (st, answered))
    check("and removes the row rather than marking it",
          len(links_of(profile_id)) == 1, links_of(profile_id))
    check("leaving the guardian who was approved alone",
          links_of(profile_id)[0]["status"] == "active", links_of(profile_id))

    st, mine = call("/rest/v1/senior_profiles?select=id", token=g2,
                    method="GET")
    check("the refused sibling has no parent",
          st != 200 or not mine, (st, mine))

    # --- the install-SMS path ----------------------------------------------
    g3 = guardian("g3")
    call("/rest/v1/rpc/ensure_guardian_account", token=g3,
         body={"p_display_name": "막내"})
    st, made = call("/rest/v1/rpc/create_senior_profile", token=g3,
                    body={"p_display_name": "아버지"})
    assert st == 200, (st, made)
    remember(made)
    check("creating a parent from the dashboard waits too",
          links_of(made["id"])[0]["status"] == "pending", links_of(made["id"]))

finally:
    for pid in created_profiles:
        call(f"/rest/v1/senior_profiles?id=eq.{pid}", key=SERVICE, method="DELETE")
    for uid in created_users:
        call(f"/auth/v1/admin/users/{uid}", key=SERVICE, method="DELETE")
    print(f"\ncleaned up {len(created_users)} users and {len(created_profiles)} profiles")

print("\n" + ("ALL CHECKS PASSED" if not failures else f"{len(failures)} FAILED: {failures}"))
raise SystemExit(1 if failures else 0)
