"""End-to-end check of 가족 메시지 against the live project.

The quota is the part worth proving: it counts guardian messages, it resets by
calendar month, 안심 케어 removes it, and it never blocks the senior from
replying. Cleans up after itself.

Run with:
    SSL_CERT_FILE=/root/.ccr/ca-bundle.crt python3 tool/verify_supabase_messages.py
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
    active link. A loop, so any card left waiting is answered too.
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
    email = f"msg-{tag}-{uuid.uuid4().hex[:8]}@example.com"
    password = "msg-test-" + uuid.uuid4().hex[:8]
    st, made = call("/auth/v1/admin/users", key=SERVICE,
                    body={"email": email, "password": password, "email_confirm": True})
    assert st in (200, 201), (st, made)
    created_users.append(made["id"])
    st, sess = call("/auth/v1/token?grant_type=password",
                    body={"email": email, "password": password})
    token = sess["access_token"]
    call("/rest/v1/rpc/ensure_guardian_account", token=token, body={"p_display_name": tag})
    return token


def device():
    st, sess = call("/auth/v1/signup", body={})
    created_users.append(sess["user"]["id"])
    return sess["access_token"], "install-" + uuid.uuid4().hex[:10]


try:
    g1 = guardian("g1")
    phone, install = device()
    st, link = call("/rest/v1/rpc/start_senior_pairing", token=phone,
                    body={"p_install_id": install})
    created_profiles.append(link["senior_profile_id"])
    st, profile = call("/rest/v1/rpc/claim_senior_pairing_code", token=g1,
                       body={"p_code": link["code"], "p_display_name": "어머니"})
    approve(phone)
    pid = profile["id"]

    # --- sending both ways ---------------------------------------------------
    st, sent = call("/rest/v1/rpc/send_family_message", token=g1,
                    body={"p_senior_profile_id": pid, "p_body": "엄마 밥 드셨어요?"})
    check("a guardian can send", st == 200 and sent["body"] == "엄마 밥 드셨어요?", sent)
    check("and the row records who sent it",
          sent["sender_guardian_id"] is not None and sent["sender_device_id"] is None, sent)

    st, replied = call("/rest/v1/rpc/send_family_message", token=phone,
                       body={"p_senior_profile_id": pid, "p_body": "먹었다"})
    check("the parent can reply", st == 200 and replied["body"] == "먹었다", replied)
    check("and their reply is recorded as theirs",
          replied["sender_device_id"] is not None
          and replied["sender_guardian_id"] is None, replied)

    st, seen = call(f"/rest/v1/messages?senior_profile_id=eq.{pid}&select=body",
                    token=phone, method="GET")
    check("both sides see the whole conversation", st == 200 and len(seen) == 2, seen)

    st, empty = call("/rest/v1/rpc/send_family_message", token=g1,
                     body={"p_senior_profile_id": pid, "p_body": "   "})
    check("an empty message is refused", st >= 400, empty)

    st, stranger = call("/rest/v1/rpc/send_family_message", token=guardian("g-other"),
                        body={"p_senior_profile_id": pid, "p_body": "누구세요"})
    check("an unrelated guardian cannot send", st >= 400, stranger)

    # --- the quota -----------------------------------------------------------
    st, quota = call("/rest/v1/rpc/family_message_quota", token=g1,
                     body={"p_senior_profile_id": pid})
    check("the quota counts the guardian's messages",
          st == 200 and quota["text_used"] == 1, quota)
    check("and not the parent's reply", quota["text_used"] == 1, quota)
    check("the free limits are the PRD's",
          quota["text_limit"] == 30 and quota["image_limit"] == 5, quota)
    check("and it is not unlimited yet", quota["unlimited"] is False, quota)

    # Fill the month. 월 30회 / 사진 5장 - see `## 무료와 안심 케어의 경계`.
    for i in range(29):
        call("/rest/v1/rpc/send_family_message", token=g1,
             body={"p_senior_profile_id": pid, "p_body": f"메시지 {i}"})

    st, full = call("/rest/v1/rpc/family_message_quota", token=g1,
                    body={"p_senior_profile_id": pid})
    check("the month fills to the limit", full["text_used"] == 30, full)

    st, blocked = call("/rest/v1/rpc/send_family_message", token=g1,
                       body={"p_senior_profile_id": pid, "p_body": "하나 더"})
    check("the 31st guardian message is refused", st >= 400, blocked)

    # The one that matters.
    st, seniorStill = call("/rest/v1/rpc/send_family_message", token=phone,
                           body={"p_senior_profile_id": pid, "p_body": "왜 답이 없니"})
    check("the parent can still reply with the quota spent",
          st == 200 and seniorStill["body"] == "왜 답이 없니", seniorStill)

    # --- 사진 5장, which nothing had ever counted ---------------------------
    # The text gate and the photo gate are separate counts, and until
    # `20261029020000_message_quota_one_place.sql` both carried their own copy
    # of the number. Nothing sent a sixth photo, so the drift sat there.
    for i in range(5):
        st, _ = call("/rest/v1/rpc/send_family_message", token=g1,
                     body={"p_senior_profile_id": pid,
                           "p_image_url": f"{pid}/photo-{i}.jpg"})
        assert st == 200, (st, i)

    st, photos = call("/rest/v1/rpc/family_message_quota", token=g1,
                      body={"p_senior_profile_id": pid})
    check("the photo allowance fills to five", photos["image_used"] == 5, photos)

    st, sixth = call("/rest/v1/rpc/send_family_message", token=g1,
                     body={"p_senior_profile_id": pid,
                           "p_image_url": f"{pid}/photo-6.jpg"})
    check("the sixth photo is refused", st >= 400, sixth)

    st, seniorPhoto = call("/rest/v1/rpc/send_family_message", token=phone,
                           body={"p_senior_profile_id": pid,
                                 "p_image_url": f"{pid}/from-mother.jpg"})
    check("the parent can still send one", st == 200, seniorPhoto)

    # --- 안심 케어 removes the limit -----------------------------------------
    call("/rest/v1/rpc/start_care_subscription", token=g1,
         body={"p_senior_profile_id": pid})
    call("/rest/v1/rpc/resolve_care_consent", token=phone,
         body={"p_senior_profile_id": pid, "p_approve": True})

    st, unlimited = call("/rest/v1/rpc/family_message_quota", token=g1,
                         body={"p_senior_profile_id": pid})
    check("안심 케어 makes it unlimited", unlimited["unlimited"] is True, unlimited)

    st, afterPaid = call("/rest/v1/rpc/send_family_message", token=g1,
                         body={"p_senior_profile_id": pid, "p_body": "이제 되나"})
    check("and sending works again", st == 200, afterPaid)

    st, stranger2 = call(f"/rest/v1/messages?senior_profile_id=eq.{pid}",
                         token=guardian("g-nosy"), method="GET")
    check("an unrelated guardian cannot read the conversation",
          st == 200 and stranger2 == [], stranger2)

finally:
    for pid_ in created_profiles:
        call(f"/rest/v1/senior_profiles?id=eq.{pid_}", key=SERVICE, method="DELETE")
    for uid in created_users:
        call(f"/auth/v1/admin/users/{uid}", key=SERVICE, method="DELETE")
    print(f"\ncleaned up {len(created_users)} users and {len(created_profiles)} profiles")

print("\n" + ("ALL CHECKS PASSED" if not failures else f"{len(failures)} FAILED: {failures}"))
raise SystemExit(1 if failures else 0)
