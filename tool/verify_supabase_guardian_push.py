"""End-to-end check of 자녀 폰 푸시 알림 against the live project.

The Edge Function that talks to FCM is a sender and nothing else; every
question about *whether this notification may be sent* is answered by
`notify_family_message`, in SQL, which is also what makes it checkable from
here - the same split 소리 울리기's gate used before that feature was taken
out, and for the same reason: a rule written in SQL can be checked from a
container that cannot run Deno.

The one worth reading twice is the caller check. This function is reached by
the **parent's own phone**, right after it sends. A guardian who could call it
would be able to make every sibling's phone buzz with a line they wrote
themselves, so being a guardian of the family is not enough - the caller has
to be the device the message was sent from.

Run with:
    SSL_CERT_FILE=/root/.ccr/ca-bundle.crt \
      python3 tool/verify_supabase_guardian_push.py
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
    email = f"gpush-{tag}-{uuid.uuid4().hex[:8]}@example.com"
    password = "gpush-test-" + uuid.uuid4().hex[:8]
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



def notify(token, message_id):
    return call("/rest/v1/rpc/notify_family_message", token=token,
                body={"p_message_id": message_id})


def register(token, value):
    return call("/rest/v1/rpc/register_guardian_push_token", token=token,
                body={"p_token": value})


def stored(name):
    rows = sql("select push_token from public.guardian_accounts "
               f"where display_name = '{name}'")
    return rows[0]["push_token"] if rows else None


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
    assert st == 200
    approve(phone)
    st, _ = call("/rest/v1/rpc/touch_senior_device", token=phone,
                 body={"p_install_id": install})
    assert st in (200, 204), st

    # --- registering ---------------------------------------------------------
    st, out = register(g1, "guardian-fcm-1")
    check("a guardian can report where their phone is", st in (200, 204), (st, out))
    check("and it is stored", stored("영희") == "guardian-fcm-1", stored("영희"))

    register(g1, "guardian-fcm-2")
    check("a rotated token replaces the old one",
          stored("영희") == "guardian-fcm-2", stored("영희"))

    # Null never overwrites — the same rule the battery follows. A phone that
    # could not fetch a token must not wipe the address the last open left,
    # or the guardian stops being reachable with nothing saying so.
    register(g1, "   ")
    check("a blank does not wipe the address",
          stored("영희") == "guardian-fcm-2", stored("영희"))

    st, out = call("/rest/v1/rpc/register_guardian_push_token", key=ANON,
                   body={"p_token": "nobody"})
    check("a call with no session registers nothing", st >= 400, (st, out))

    orphan_email = f"gpush-orphan-{uuid.uuid4().hex[:8]}@example.com"
    st, made = call("/auth/v1/admin/users", key=SERVICE,
                    body={"email": orphan_email, "password": "gpush-orphan-1",
                          "email_confirm": True})
    assert st in (200, 201), (st, made)
    created_users.append(made["id"])
    st, sess = call("/auth/v1/token?grant_type=password",
                    body={"email": orphan_email, "password": "gpush-orphan-1"})
    st, out = register(sess["access_token"], "orphan")
    check("a signed-in user with no guardian account is refused",
          st >= 400, (st, out))

    # --- what the sender is handed ------------------------------------------
    st, msg = call("/rest/v1/rpc/send_family_message", token=phone,
                   body={"p_senior_profile_id": profile_id, "p_body": "잘 있다"})
    assert st == 200, (st, msg)
    message_id = msg["id"]

    st, out = notify(phone, message_id)
    check("the parent's phone may ask for its message to be delivered",
          st == 200, (st, out))
    row = (out or [{}])[0] if isinstance(out, list) else {}
    check("it carries the guardian's address",
          row.get("push_token") == "guardian-fcm-2", out)
    check("the parent's name is the title", row.get("title") == "어머니", out)
    check("and the message is the body", row.get("body") == "잘 있다", out)

    # --- who may not ---------------------------------------------------------
    st, out = notify(g1, message_id)
    check("a guardian cannot push a line they wrote themselves",
          st >= 400, (st, out))

    st, out = call("/rest/v1/rpc/notify_family_message", key=ANON,
                   body={"p_message_id": message_id})
    check("a call with no session notifies nobody", st >= 400, (st, out))

    st, gmsg = call("/rest/v1/rpc/send_family_message", token=g1,
                    body={"p_senior_profile_id": profile_id,
                          "p_body": "엄마 잘 계세요?"})
    assert st == 200, (st, gmsg)
    st, out = notify(phone, gmsg["id"])
    check("a guardian's own message is not pushed back at the family",
          st >= 400, (st, out))

    other_phone, other_install = device()
    st, other = call("/rest/v1/rpc/start_senior_pairing", token=other_phone,
                     body={"p_install_id": other_install, "p_platform": "android"})
    assert st == 200, (st, other)
    created_profiles.append(other["senior_profile_id"])
    st, out = notify(other_phone, message_id)
    check("another family's phone cannot push this message", st >= 400, (st, out))

    st, out = notify(phone, "00000000-0000-0000-0000-000000000000")
    check("a message that does not exist is refused", st >= 400, (st, out))

    # --- who is on the list --------------------------------------------------
    # A guardian whose phone has never opened the dashboard has no address.
    # There is nothing to send and nothing is wrong.
    g2 = guardian("g2", "철수")
    sql(f"""
        insert into public.guardian_senior_links
              (guardian_account_id, senior_profile_id, role, status)
        select ga.id, '{profile_id}', 'family', 'active'
          from public.guardian_accounts ga
         where ga.display_name = '철수'
        on conflict (guardian_account_id, senior_profile_id)
        do update set status = 'active';
    """)
    st, out = notify(phone, message_id)
    check("a guardian who never opened the app is simply not on the list",
          st == 200 and len(out) == 1, (st, out))

    register(g2, "guardian-fcm-3")
    st, out = notify(phone, message_id)
    check("two children both get it",
          st == 200 and len(out) == 2, (st, out))

    # A removed guardian keeps their row, and must not go on being told what
    # the parent says to the family they left.
    sql(f"""
        update public.guardian_senior_links l
           set status = 'removed'
          from public.guardian_accounts ga
         where ga.id = l.guardian_account_id
           and ga.display_name = '철수'
           and l.senior_profile_id = '{profile_id}';
    """)
    st, out = notify(phone, message_id)
    check("a removed guardian is not told what the parent says",
          st == 200 and len(out) == 1, (st, out))

    # --- the two substitutions ----------------------------------------------
    st, photo = call("/rest/v1/rpc/send_family_message", token=phone,
                     body={"p_senior_profile_id": profile_id,
                           "p_image_url": f"{profile_id}/a.jpg"})
    assert st == 200, (st, photo)
    st, out = notify(phone, photo["id"])
    row = (out or [{}])[0] if isinstance(out, list) else {}
    # An image carries no text, and a notification that said nothing would
    # make the guardian open the app to learn nothing had happened.
    check("a photo says so rather than arriving blank",
          row.get("body") == "사진을 보내셨어요", out)

    # `display_name` is `not null`, so the case the coalesce guards against is
    # not a null but a name of spaces — which is reachable, and is what a
    # guardian typing into the field and giving up actually leaves behind.
    sql(f"update public.senior_profiles set display_name = '   ' "
        f"where id = '{profile_id}'")
    st, out = notify(phone, message_id)
    row = (out or [{}])[0] if isinstance(out, list) else {}
    check("a parent whose name is blank is 부모님, never an empty title",
          row.get("title") == "부모님", out)

    # --- the sender itself ---------------------------------------------------
    # The one thing the gate cannot tell you is whether the Edge Function in
    # front of FCM works. The guardian's stored token is a made-up string, so
    # FCM rejects it — and that rejection is the success signal, because
    # reaching FCM at all means the service account minted a Google token.
    #
    # A 500 here is `sender_unconfigured`, which means **every** family's
    # notifications are failing rather than this one fake address. The two
    # must not be read as the same thing.
    sql(f"update public.senior_profiles set display_name = '어머니' "
        f"where id = '{profile_id}'")
    st, out = call("/functions/v1/notify-message", token=phone,
                   body={"message_id": message_id})
    check("the function reached FCM with a real service account",
          st == 200, (st, out))
    check("and reported the fake address as delivered to nobody",
          isinstance(out, dict) and out.get("sent") == 0, (st, out))

    st, out = call("/functions/v1/notify-message", token=g1,
                   body={"message_id": message_id})
    check("the function forwards the caller's own JWT to the gate",
          st == 403, (st, out))

finally:
    for pid in created_profiles:
        call(f"/rest/v1/senior_profiles?id=eq.{pid}", key=SERVICE, method="DELETE")
    for uid in created_users:
        call(f"/auth/v1/admin/users/{uid}", key=SERVICE, method="DELETE")
    print(f"\ncleaned up {len(created_users)} users and {len(created_profiles)} profiles")

print("\n" + ("ALL CHECKS PASSED" if not failures else f"{len(failures)} FAILED: {failures}"))
raise SystemExit(1 if failures else 0)
