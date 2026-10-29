"""The 1대1 lock, against the live project.

The owner's call on 2026-10-29: 복잡할 거 같아. The app could put several
children on one parent and several parents on one child, and almost
everything awkward in it came from one of those two.

**This is a lock, not a rewrite**, and that is what this file is here to
hold. `guardian_senior_links` is still a join table, the invite and handover
functions are still there, and `20261029080000_one_to_one.sql` changes two
numbers. So the questions worth asking from outside are: does the server
actually refuse, does it refuse on *every* path rather than only where a
button was taken off, and does it still let the things that have to keep
working through.

The last of those is the one that would break a real family. A 끊기 is
reversible, so the seat a removed guardian held has to come free; and a
guardian re-entering a code for the parent they already have is not a second
guardian.

When the lock lifts, this file goes and the checks in the other verifiers
that say "seeded past the gate" go back to using an invite.

Run with:
    SSL_CERT_FILE=/root/.ccr/ca-bundle.crt python3 tool/verify_supabase_one_to_one.py
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


created_users = []
created_profiles = []


def guardian(tag, name=None):
    email = f"onetoone-{tag}-{uuid.uuid4().hex[:8]}@example.com"
    password = "onetoone-test-" + uuid.uuid4().hex[:8]
    st, made = call("/auth/v1/admin/users", key=SERVICE,
                    body={"email": email, "password": password,
                          "email_confirm": True})
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


def show_code(phone, install):
    st, pair = call("/rest/v1/rpc/start_senior_pairing", token=phone,
                    body={"p_install_id": install, "p_platform": "android"})
    assert st == 200, (st, pair)
    return pair


def approve(phone):
    st, card = call("/rest/v1/rpc/pending_guardian_link", token=phone, body={})
    assert st == 200 and card, (st, card)
    st, ok = call("/rest/v1/rpc/answer_guardian_link", token=phone,
                  body={"p_link_id": card[0]["link_id"], "p_approve": True})
    assert st == 200 and ok is True, (st, ok)


def links_of(profile_id):
    st, rows = call(
        "/rest/v1/guardian_senior_links?senior_profile_id=eq." + profile_id
        + "&select=guardian_account_id,status",
        key=SERVICE, method="GET")
    return rows or []


try:
    # --- the two numbers ----------------------------------------------------
    nums = sql("select public.max_guardians_per_senior() as g, "
               "public.max_seniors_per_guardian() as s")
    check("the limits are one each, and are the only thing to change back",
          nums[0]["g"] == 1 and nums[0]["s"] == 1, nums)

    # --- 부모님 한 분에 자녀 한 명 ---------------------------------------------
    phone, install = device()
    pair = show_code(phone, install)
    profile_id = pair["senior_profile_id"]
    created_profiles.append(profile_id)

    g1 = guardian("g1", "영희")
    st, _ = call("/rest/v1/rpc/claim_senior_pairing_code", token=g1,
                 body={"p_code": pair["code"], "p_display_name": "어머니"})
    check("the first child connects as always", st == 200, (st, _))
    approve(phone)

    g2 = guardian("g2", "철수")
    second = show_code(phone, install)
    st, refused = call("/rest/v1/rpc/claim_senior_pairing_code", token=g2,
                       body={"p_code": second["code"], "p_display_name": "어머니"})
    check("a second child typing the number is refused", st >= 400, (st, refused))
    check("and the parent still has exactly one",
          len([r for r in links_of(profile_id) if r["status"] != "removed"]) == 1,
          links_of(profile_id))

    # The other door in. 가족 초대하기 is off every screen, so nothing creates
    # one of these any more - but an invite made before today is live for
    # seven days, and a rule that holds only because no button calls it is a
    # rule waiting for the next button.
    st, inv = call("/rest/v1/rpc/create_family_invite", token=g1,
                   body={"p_senior_profile_id": profile_id})
    assert st == 200, (st, inv)
    st, refused = call("/rest/v1/rpc/redeem_family_invite", token=g2,
                       body={"p_code": inv["code"]})
    check("and an invite does not let them in either", st >= 400, (st, refused))

    # --- 자녀 한 명에 부모님 한 분 ---------------------------------------------
    st, refused = call("/rest/v1/rpc/create_senior_profile", token=g1,
                       body={"p_display_name": "아버지"})
    check("a second parent is refused", st >= 400, (st, refused))

    other_phone, other_install = device()
    other = show_code(other_phone, other_install)
    created_profiles.append(other["senior_profile_id"])
    st, refused = call("/rest/v1/rpc/claim_senior_pairing_code", token=g1,
                       body={"p_code": other["code"], "p_display_name": "아버지"})
    check("nor may they type a second parent's number", st >= 400, (st, refused))

    # **가족 플랜 no longer lifts it**, which is the one behaviour this lock
    # reverses rather than merely hides. The plan, its rows and
    # `has_family_plan()` are all still there.
    st, plan = call("/rest/v1/rpc/start_family_plan", token=g1, body={})
    check("the family plan can still be bought", st == 200, (st, plan))
    st, refused = call("/rest/v1/rpc/create_senior_profile", token=g1,
                       body={"p_display_name": "아버지"})
    check("and buying it changes nothing about the limit", st >= 400,
          (st, refused))

    # --- what must keep working --------------------------------------------
    # The same guardian re-entering a code for the parent they already have.
    # It happens on a reconnect and after an install SMS, and reading it as a
    # second guardian would lock a family out of their own parent.
    again = show_code(phone, install)
    st, ok = call("/rest/v1/rpc/claim_senior_pairing_code", token=g1,
                  body={"p_code": again["code"], "p_display_name": "어머니"})
    check("the same child may re-enter a number for their own parent",
          st == 200, (st, ok))
    check("and is still one link, still active",
          [r["status"] for r in links_of(profile_id)] == ["active"],
          links_of(profile_id))

    # 끊기 frees the seat. It is reversible by design, and a lock that
    # counted removed rows would make it permanent.
    st, who = call("/rest/v1/guardian_accounts?select=id", token=g1,
                   method="GET")
    assert st == 200 and who, (st, who)
    st, _ = call("/rest/v1/rpc/remove_guardian_link", token=phone,
                 body={"p_guardian_account_id": who[0]["id"]})
    assert st in (200, 204), (st, _)

    freed = show_code(phone, install)
    st, ok = call("/rest/v1/rpc/claim_senior_pairing_code", token=g2,
                  body={"p_code": freed["code"], "p_display_name": "어머니"})
    check("a removed child frees the seat for another", st == 200, (st, ok))
    approve(phone)
    check("and the parent has one child again",
          len([r for r in links_of(profile_id) if r["status"] == "active"]) == 1,
          links_of(profile_id))

finally:
    for pid in created_profiles:
        call(f"/rest/v1/senior_profiles?id=eq.{pid}", key=SERVICE,
             method="DELETE")
    for uid in created_users:
        call(f"/auth/v1/admin/users/{uid}", key=SERVICE, method="DELETE")
    print(f"\ncleaned up {len(created_users)} users and "
          f"{len(created_profiles)} profiles")

print("\n" + ("ALL CHECKS PASSED" if not failures
              else f"{len(failures)} FAILED: {failures}"))
raise SystemExit(1 if failures else 0)
