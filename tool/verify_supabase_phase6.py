"""End-to-end check of the Phase 6 paid schema against the live project.

Walks the acceptance list: nothing activates before the senior consents, a
refusal refunds and leaves the free features alone, and the family plan is what
unlocks a second parent. Deletes every row and user it created.

Run with:
    SSL_CERT_FILE=/root/.ccr/ca-bundle.crt python3 tool/verify_supabase_phase6.py
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
    out = {}
    for k in json.load(urllib.request.urlopen(req)):
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


created_users, created_profiles = [], []


def guardian(tag):
    email = f"phase6-{tag}-{uuid.uuid4().hex[:8]}@example.com"
    password = "phase6-test-" + uuid.uuid4().hex[:8]
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
    st, sess = call("/auth/v1/signup", body={})
    assert st == 200, (st, sess)
    created_users.append(sess["user"]["id"])
    return sess["access_token"], "install-" + uuid.uuid4().hex[:10]


def paired(guardian_token, name):
    """A parent connected to this guardian, and the phone that holds them."""
    phone, install = device()
    st, link = call("/rest/v1/rpc/start_senior_pairing", token=phone,
                    body={"p_install_id": install})
    assert st == 200, (st, link)
    created_profiles.append(link["senior_profile_id"])
    st, profile = call("/rest/v1/rpc/claim_senior_pairing_code", token=guardian_token,
                       body={"p_code": link["code"], "p_display_name": name})
    approve(phone)
    return profile, phone


try:
    g1 = guardian("g1")
    profile, phone = paired(g1, "어머니")
    check("a parent is connected to start from", isinstance(profile, dict)
          and profile.get("id"), profile)
    pid = profile["id"]

    # --- paid features do not activate before consent ------------------------
    st, sub = call("/rest/v1/rpc/start_care_subscription", token=g1,
                   body={"p_senior_profile_id": pid})
    check("paying leaves the subscription waiting on the senior",
          st == 200 and sub["status"] == "pending_senior_consent", sub)

    st, active = call("/rest/v1/rpc/care_is_active", token=g1,
                      body={"p_senior_profile_id": pid})
    check("nothing is active before the senior answers", st == 200 and active is False, active)

    st, rows = call(f"/rest/v1/senior_profiles?id=eq.{pid}&select=paid_consent_status",
                    token=g1, method="GET")
    check("the profile records that it is pending",
          st == 200 and rows[0]["paid_consent_status"] == "pending", rows)

    st, seen = call(f"/rest/v1/subscriptions?senior_profile_id=eq.{pid}&select=status",
                    token=phone, method="GET")
    check("the senior's phone can see what it is being asked about",
          st == 200 and len(seen) == 1, seen)

    st, twice = call("/rest/v1/rpc/start_care_subscription", token=g1,
                     body={"p_senior_profile_id": pid})
    check("paying twice is refused", st >= 400, twice)

    st, byGuardian = call("/rest/v1/rpc/resolve_care_consent", token=g1,
                          body={"p_senior_profile_id": pid, "p_approve": True})
    check("the guardian cannot answer on the senior's behalf", st >= 400, byGuardian)

    # --- refusal refunds, and leaves the free features alone -----------------
    call("/rest/v1/rpc/replace_home_apps", token=phone,
         body={"p_senior_profile_id": pid, "p_apps": [
             {"client_id": "phone", "label": "전화", "icon_key": "phone", "sort_order": 0}]})

    st, refused = call("/rest/v1/rpc/resolve_care_consent", token=phone,
                       body={"p_senior_profile_id": pid, "p_approve": False})
    check("the senior can refuse on their own phone",
          st == 200 and refused["paid_consent_status"] == "refused", refused)

    st, subs = call(
        f"/rest/v1/subscriptions?senior_profile_id=eq.{pid}&select=status,refunded_at",
        token=g1, method="GET")
    check("a refusal refunds the subscription",
          st == 200 and subs[0]["status"] == "refunded"
          and subs[0]["refunded_at"] is not None, subs)

    st, active = call("/rest/v1/rpc/care_is_active", token=g1,
                      body={"p_senior_profile_id": pid})
    check("the paid features stay off after a refusal", active is False, active)

    st, apps = call(f"/rest/v1/home_apps?senior_profile_id=eq.{pid}&select=client_id",
                    token=phone, method="GET")
    check("the free features are untouched by a refusal",
          st == 200 and [a["client_id"] for a in apps] == ["phone"], apps)

    st, alerts = call(f"/rest/v1/alerts?senior_profile_id=eq.{pid}&select=type,body",
                      token=g1, method="GET")
    check("the guardian is told about the refusal",
          st == 200 and any(a["type"] == "care_consent_refused" for a in alerts), alerts)
    check("and told the money came back",
          any('환불' in (a["body"] or '') for a in alerts), alerts)

    st, again = call("/rest/v1/rpc/resolve_care_consent", token=phone,
                     body={"p_senior_profile_id": pid, "p_approve": True})
    check("answering a refused request again is refused", st >= 400, again)

    # --- approval turns it on -----------------------------------------------
    st, sub2 = call("/rest/v1/rpc/start_care_subscription", token=g1,
                    body={"p_senior_profile_id": pid})
    check("the guardian may buy it again after a refusal", st == 200, sub2)

    st, granted = call("/rest/v1/rpc/resolve_care_consent", token=phone,
                       body={"p_senior_profile_id": pid, "p_approve": True})
    check("the senior can agree", st == 200
          and granted["paid_consent_status"] == "granted", granted)

    st, active = call("/rest/v1/rpc/care_is_active", token=g1,
                      body={"p_senior_profile_id": pid})
    check("only then is 안심 케어 active", active is True, active)

    # --- the family plan unlocks a second parent ----------------------------
    st, blocked = call("/rest/v1/rpc/create_senior_profile", token=g1,
                       body={"p_display_name": "아버지"})
    check("a second parent is refused without the family plan", st >= 400, blocked)

    st, has = call("/rest/v1/rpc/has_family_plan", token=g1, body={})
    check("and the plan is reported as absent", has is False, has)

    st, plan = call("/rest/v1/rpc/start_family_plan", token=g1, body={})
    check("the family plan needs no senior consent — it is about the guardian",
          st == 200 and plan["status"] == "active", plan)

    st, second = call("/rest/v1/rpc/create_senior_profile", token=g1,
                      body={"p_display_name": "아버지"})
    check("a second parent is allowed once the plan is active",
          st == 200 and second.get("id"), second)
    if isinstance(second, dict) and second.get("id"):
        created_profiles.append(second["id"])

    # The second parent has no phone yet, so their link is 'pending' and the
    # dashboard still shows one - see `20261029010000_link_consent.sql`. What
    # the family plan bought is the row, not the consent.
    st, mine = call("/rest/v1/senior_profiles?select=id", token=g1, method="GET")
    check("the parent who agreed is the one on the dashboard",
          st == 200 and len(mine) == 1, mine)
    st, waiting = call("/rest/v1/rpc/pending_guardian_links", token=g1, body={})
    check("and the second parent is waiting on their own phone",
          st == 200 and len(waiting or []) == 1
          and waiting[0]["senior_profile_id"] == second["id"], waiting)

    # A sibling helping with one parent is the free feature, not a paid one.
    st, invite = call("/rest/v1/rpc/create_family_invite", token=g1,
                      body={"p_senior_profile_id": pid})
    g2 = guardian("g2")
    st, joined = call("/rest/v1/rpc/redeem_family_invite", token=g2,
                      body={"p_code": invite["code"]})
    check("a sibling joins one parent with no plan of their own",
          st == 200 and joined["id"] == pid, joined)

    st, hasPlan = call("/rest/v1/rpc/has_family_plan", token=g2, body={})
    check("and they still have no family plan", hasPlan is False, hasPlan)

    st, blocked2 = call("/rest/v1/rpc/create_senior_profile", token=g2,
                        body={"p_display_name": "장모님"})
    check("but a second parent of their own still needs one", st >= 400, blocked2)

    st, otherAlerts = call(f"/rest/v1/alerts?senior_profile_id=eq.{pid}",
                           token=guardian("g3"), method="GET")
    check("an unrelated guardian cannot read the alerts",
          st == 200 and otherAlerts == [], otherAlerts)

finally:
    for pid_ in created_profiles:
        call(f"/rest/v1/senior_profiles?id=eq.{pid_}", key=SERVICE, method="DELETE")
    for uid in created_users:
        call(f"/auth/v1/admin/users/{uid}", key=SERVICE, method="DELETE")
    print(f"\ncleaned up {len(created_users)} users and {len(created_profiles)} profiles")

print("\n" + ("ALL CHECKS PASSED" if not failures else f"{len(failures)} FAILED: {failures}"))
raise SystemExit(1 if failures else 0)
