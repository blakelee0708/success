"""End-to-end check of 배터리 부족 알림 and 폰 미사용 알림 against the live project.

Both are named in the PRD's 안심 케어 list, so both are gated on
`care_is_active` — a subscription *and* the senior's consent. With no Play
Billing there is no way to reach either from the app yet, which is exactly why
the gate is the thing most worth checking here rather than on a screen.

The two need opposite machinery: the battery alert fires on a check-in, and
the unused alert fires on the absence of one, so it is driven by pg_cron and
checked here by calling the function the job calls.

Run with:
    SSL_CERT_FILE=/root/.ccr/ca-bundle.crt python3 tool/verify_supabase_alerts.py
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
    email = f"alerts-{tag}-{uuid.uuid4().hex[:8]}@example.com"
    password = "alerts-test-" + uuid.uuid4().hex[:8]
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



def alerts(token, profile_id, kind=None):
    path = (f"/rest/v1/alerts?senior_profile_id=eq.{profile_id}"
            "&select=type,title,body,metadata&order=created_at.desc")
    if kind:
        path += f"&type=eq.{kind}"
    st, rows = call(path, token=token, method="GET")
    return rows or []


def sql(statement):
    """Run as the database owner, for the parts no client may do."""
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{REF}/database/query",
        data=json.dumps({"query": statement}).encode(),
        headers={"Authorization": f"Bearer {MGMT}",
                 "Content-Type": "application/json", "User-Agent": UA},
        method="POST")
    with urllib.request.urlopen(req) as r:
        return json.load(r)


def report(token, install, percent, charging=False):
    return call("/rest/v1/rpc/touch_senior_device", token=token,
                body={"p_install_id": install, "p_battery_percent": percent,
                      "p_is_charging": charging})


try:
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

    # --- unpaid: nothing is written at all -----------------------------------
    st, _ = report(phone, install, 8)
    check("an unpaid family gets no battery alert",
          not alerts(g1, profile_id, "battery_low"),
          alerts(g1, profile_id))

    sql(f"update public.senior_devices set last_seen_at = now() - interval '5 days' "
        f"where install_id = '{install}'")
    rows = sql("select public.check_unused_phones() as n")
    check("and no unused alert either",
          not alerts(g1, profile_id, "phone_unused"), rows)

    # --- paid, but the senior has not agreed ---------------------------------
    # `06_PERMISSION_AND_POLICY` puts the consent after the payment, and
    # care_is_active requires both. A paid subscription with no consent has to
    # behave exactly like no subscription.
    st, sub = call("/rest/v1/rpc/start_care_subscription", token=g1,
                   body={"p_senior_profile_id": profile_id})
    assert st == 200, (st, sub)
    sql(f"update public.senior_devices set battery_low_notified = false "
        f"where install_id = '{install}'")
    st, _ = report(phone, install, 8)
    check("a paid subscription with no consent is still silent",
          not alerts(g1, profile_id, "battery_low"), alerts(g1, profile_id))

    rows = sql("select public.check_unused_phones() as n")
    check("including the unused sweep",
          not alerts(g1, profile_id, "phone_unused"), rows)

    # --- the senior agrees ---------------------------------------------------
    st, _ = call("/rest/v1/rpc/resolve_care_consent", token=phone,
                 body={"p_senior_profile_id": profile_id, "p_approve": True})
    assert st == 200, st

    # --- 배터리 부족 ----------------------------------------------------------
    sql(f"update public.senior_devices set battery_low_notified = false "
        f"where install_id = '{install}'")
    st, _ = report(phone, install, 8)
    low = alerts(g1, profile_id, "battery_low")
    check("once paid and agreed, a low battery is reported", len(low) == 1, low)
    check("and it says the level", low and "8%" in (low[0]["body"] or ""), low)

    # Hysteresis. A phone sitting at 8% reports on every resume; one row per
    # low spell, or it is not an alert, it is a reason to stop reading alerts.
    for _ in range(3):
        report(phone, install, 8)
    check("reporting 8% again does not write a second row",
          len(alerts(g1, profile_id, "battery_low")) == 1,
          alerts(g1, profile_id, "battery_low"))

    report(phone, install, 12)
    check("nor does drifting lower within the same spell",
          len(alerts(g1, profile_id, "battery_low")) == 1,
          alerts(g1, profile_id, "battery_low"))

    # Charging is not a low battery: it is a low battery being dealt with.
    sql(f"update public.senior_devices set battery_low_notified = false "
        f"where install_id = '{install}'")
    st, _ = report(phone, install, 8, charging=True)
    check("8% on the charger raises nothing",
          len(alerts(g1, profile_id, "battery_low")) == 1,
          alerts(g1, profile_id, "battery_low"))

    # Back up past the recovery line, then down again: that is a new spell.
    report(phone, install, 60)
    report(phone, install, 9)
    check("a new low spell after recovering does report again",
          len(alerts(g1, profile_id, "battery_low")) == 2,
          alerts(g1, profile_id, "battery_low"))

    # --- 폰 미사용 ------------------------------------------------------------
    sql(f"update public.senior_devices set last_seen_at = now() - interval '5 days' "
        f"where install_id = '{install}'")
    sql(f"update public.senior_profiles set unused_notified_for = null "
        f"where id = '{profile_id}'")
    rows = sql("select public.check_unused_phones() as n")
    unused = alerts(g1, profile_id, "phone_unused")
    check("a phone quiet for days is reported", len(unused) == 1, (rows, unused))
    check("and it counts the days", unused and "5일째" in (unused[0]["body"] or ""),
          unused)

    sql("select public.check_unused_phones()")
    check("running the sweep again does not repeat it",
          len(alerts(g1, profile_id, "phone_unused")) == 1,
          alerts(g1, profile_id, "phone_unused"))

    # Picking the phone up moves last_seen_at past the mark, which arms the
    # next one with no clearing step.
    report(phone, install, 60)
    sql("select public.check_unused_phones()")
    check("a phone that was picked up is not reported as unused",
          len(alerts(g1, profile_id, "phone_unused")) == 1,
          alerts(g1, profile_id, "phone_unused"))

    sql(f"update public.senior_devices set last_seen_at = now() - interval '4 days' "
        f"where install_id = '{install}'")
    sql("select public.check_unused_phones()")
    check("but a second silence after that is",
          len(alerts(g1, profile_id, "phone_unused")) == 2,
          alerts(g1, profile_id, "phone_unused"))

    # A phone that has never checked in is 연결되기 전, not 미사용.
    sql(f"update public.senior_devices set last_seen_at = null "
        f"where install_id = '{install}'")
    before = len(alerts(g1, profile_id, "phone_unused"))
    sql("select public.check_unused_phones()")
    check("a phone that never checked in is not called unused",
          len(alerts(g1, profile_id, "phone_unused")) == before,
          alerts(g1, profile_id, "phone_unused"))

    # --- the job that calls it ----------------------------------------------
    job = sql("select jobname, schedule, active from cron.job "
              "where jobname = 'check-unused-phones'")
    check("the sweep is actually scheduled",
          job and job[0]["active"] is True, job)

    # --- nobody may call either by hand -------------------------------------
    st, _ = call("/rest/v1/rpc/check_unused_phones", token=g1, body={})
    check("a guardian cannot run the sweep", st >= 400, st)
    st, _ = call("/rest/v1/rpc/raise_battery_alert", token=phone,
                 body={"p_senior_profile_id": profile_id,
                       "p_install_id": install, "p_battery_percent": 1,
                       "p_is_charging": False})
    check("and a phone cannot raise an alert directly", st >= 400, st)

finally:
    for pid in created_profiles:
        call(f"/rest/v1/senior_profiles?id=eq.{pid}", key=SERVICE, method="DELETE")
    for uid in created_users:
        call(f"/auth/v1/admin/users/{uid}", key=SERVICE, method="DELETE")
    print(f"\ncleaned up {len(created_users)} users and {len(created_profiles)} profiles")

print("\n" + ("ALL CHECKS PASSED" if not failures else f"{len(failures)} FAILED: {failures}"))
raise SystemExit(1 if failures else 0)
