"""End-to-end check of the 가족 메시지 photo bucket against the live project.

The table half of images has existed since Phase 7 - the column, the quota
that counts them separately, and the RPC that refuses an eleventh on the free
plan. This checks the half that was missing: the bucket the file itself goes
into, and who can read it.

The bucket is private, so every rule here is storage RLS, and storage RLS is
the kind of thing that cannot be proved by reading it. A `public` bucket and
a bucket with policies that never match look identical from the app - both
simply work for the person testing, who is always the one with access.

Cleans up after itself.

Run with:
    SSL_CERT_FILE=/root/.ccr/ca-bundle.crt python3 tool/verify_supabase_images.py
"""
import json
import os
import urllib.error
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



def upload(token, path, *, data=b"\x89PNG\r\n\x1a\n-not-a-real-png", ctype="image/png"):
    """Raw storage upload, because `call` is JSON-only."""
    req = urllib.request.Request(
        f"{BASE}/storage/v1/object/message-images/{path}",
        data=data, method="POST",
        headers={
            "apikey": ANON,
            "Authorization": f"Bearer {token}",
            "Content-Type": ctype,
            "User-Agent": UA,
        },
    )
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, r.read().decode()[:200]
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:200]


def download(token, path):
    req = urllib.request.Request(
        f"{BASE}/storage/v1/object/message-images/{path}",
        headers={"apikey": ANON, "Authorization": f"Bearer {token}", "User-Agent": UA},
    )
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()[:200]


created_objects = []

try:
    g1 = guardian("g1")
    outsider = guardian("outsider")
    phone, install = device()
    st, link = call("/rest/v1/rpc/start_senior_pairing", token=phone,
                    body={"p_install_id": install})
    created_profiles.append(link["senior_profile_id"])
    st, profile = call("/rest/v1/rpc/claim_senior_pairing_code", token=g1,
                       body={"p_code": link["code"], "p_display_name": "어머니"})
    pid = profile["id"]

    # --- the bucket is private, which is the whole point ---------------------
    # Read as the service role: the bucket's own metadata is not something an
    # ordinary guardian can fetch, and a 404 there is the API being right.
    # What a guardian can and cannot *reach* is everything below.
    st, buckets = call("/storage/v1/bucket/message-images", key=SERVICE,
                       method="GET")
    check("the bucket is private", st == 200 and buckets.get("public") is False, buckets)
    check("and it only takes images",
          st == 200 and "image/jpeg" in (buckets.get("allowed_mime_types") or []), buckets)

    # --- the family can put a photo in --------------------------------------
    gpath = f"{pid}/{uuid.uuid4().hex}.png"
    st, body = upload(g1, gpath)
    check("a guardian can upload into their parent's folder", st in (200, 201), (st, body))
    if st in (200, 201):
        created_objects.append(gpath)

    spath = f"{pid}/{uuid.uuid4().hex}.png"
    st, body = upload(phone, spath)
    check("the parent's phone can upload too", st in (200, 201), (st, body))
    if st in (200, 201):
        created_objects.append(spath)

    # --- and read each other's ----------------------------------------------
    st, _ = download(phone, gpath)
    check("the parent can read what their child sent", st == 200, st)
    st, _ = download(g1, spath)
    check("the child can read what their parent sent", st == 200, st)

    # --- nobody else can ----------------------------------------------------
    st, body = download(outsider, gpath)
    check("an unrelated guardian cannot read it", st in (400, 403, 404), (st, body))
    st, body = upload(outsider, f"{pid}/{uuid.uuid4().hex}.png")
    check("an unrelated guardian cannot upload into the folder",
          st in (400, 403), (st, body))

    req = urllib.request.Request(
        f"{BASE}/storage/v1/object/public/message-images/{gpath}",
        headers={"User-Agent": UA},
    )
    try:
        with urllib.request.urlopen(req) as r:
            anon_status = r.status
    except urllib.error.HTTPError as e:
        anon_status = e.code
    check("and the public URL does not serve it", anon_status in (400, 403, 404),
          anon_status)

    # --- a removed guardian loses the photos, the way they lose the ring -----
    call("/rest/v1/rpc/send_family_message", token=g1,
         body={"p_senior_profile_id": pid, "p_body": "x", "p_image_url": gpath})
    st, _ = call(f"/rest/v1/guardian_senior_links?senior_profile_id=eq.{pid}",
                 key=SERVICE, method="PATCH", body={"status": "removed"})
    st, body = download(g1, gpath)
    check("a removed guardian can no longer read them", st in (400, 403, 404),
          (st, body))

    # --- nothing may edit or erase what was said ----------------------------
    req = urllib.request.Request(
        f"{BASE}/storage/v1/object/message-images/{spath}", method="DELETE",
        headers={"apikey": ANON, "Authorization": f"Bearer {phone}", "User-Agent": UA},
    )
    try:
        with urllib.request.urlopen(req) as r:
            del_status = r.status
    except urllib.error.HTTPError as e:
        del_status = e.code
    check("even the sender cannot delete a sent photo", del_status in (400, 403, 404),
          del_status)

finally:
    for path in created_objects:
        req = urllib.request.Request(
            f"{BASE}/storage/v1/object/message-images/{path}", method="DELETE",
            headers={"apikey": SERVICE, "Authorization": f"Bearer {SERVICE}",
                     "User-Agent": UA},
        )
        try:
            urllib.request.urlopen(req)
        except Exception:
            pass
    for pid_ in created_profiles:
        call(f"/rest/v1/senior_profiles?id=eq.{pid_}", key=SERVICE, method="DELETE")
    for uid in created_users:
        call(f"/auth/v1/admin/users/{uid}", key=SERVICE, method="DELETE")
    print(f"\ncleaned up {len(created_users)} users, {len(created_profiles)} profiles, "
          f"{len(created_objects)} objects")

print()
if failures:
    print(f"{len(failures)} CHECK(S) FAILED")
    for f in failures:
        print("  - " + f)
    raise SystemExit(1)
print("ALL CHECKS PASSED")
