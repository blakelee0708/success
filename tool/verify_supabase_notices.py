"""공지 and the app's server settings, against the live project.

A notice reaches phones that will never be updated, which is the whole
reason it lives on the server - so what is checked is what a phone with no
session, or the parent's anonymous one, can and cannot do with it:

- a running notice is readable by anybody, a future or an ended one by
  nobody;
- nothing a client holds can write a notice or flip `app_config`;
- `app_config` reads, and starts with the install link off.

Run with:
    SSL_CERT_FILE=/root/.ccr/ca-bundle.crt python3 tool/verify_supabase_notices.py
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
failures = []


def mgmt_keys():
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{REF}/api-keys?reveal=true",
        headers={"Authorization": f"Bearer {MGMT}", "User-Agent": UA})
    out = {}
    for k in json.load(urllib.request.urlopen(req)):
        if k["name"] == "anon" or k["type"] == "publishable":
            out.setdefault("anon", k["api_key"])
    return out["anon"]


ANON = mgmt_keys()


def call(path, *, token=None, method="GET", body=None, prefer=None):
    headers = {"apikey": ANON, "Authorization": f"Bearer {token or ANON}",
               "Content-Type": "application/json", "User-Agent": UA}
    if prefer:
        headers["Prefer"] = prefer
    req = urllib.request.Request(
        BASE + path, method=method, headers=headers,
        data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def sql(statement):
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{REF}/database/query",
        data=json.dumps({"query": statement}).encode(), method="POST",
        headers={"Authorization": f"Bearer {MGMT}",
                 "Content-Type": "application/json", "User-Agent": UA})
    with urllib.request.urlopen(req) as r:
        return json.load(r)


def check(name, cond, detail=""):
    print(("PASS  " if cond else "FAIL  ") + name + ("" if cond else f"  <- {detail}"))
    if not cond:
        failures.append(name)


tag = "verify-" + uuid.uuid4().hex[:8]
try:
    sql("insert into public.announcements (audience, title, body, starts_at, ends_at) values "
        f"('senior', '{tag}', 'now', now() - interval '1 minute', null), "
        f"('guardian', '{tag}', 'later', now() + interval '1 day', null), "
        f"('both', '{tag}', 'over', now() - interval '2 days', now() - interval '1 day')")

    st, rows = call(f"/rest/v1/announcements?title=eq.{tag}&select=body")
    bodies = sorted(r["body"] for r in (rows or [])) if st == 200 else rows
    check("a running notice is readable with no session at all",
          st == 200 and bodies == ["now"], (st, bodies))
    check("one that has not started is not", "later" not in (bodies or []), bodies)
    check("nor one that has ended", "over" not in (bodies or []), bodies)

    st, sess = call("/auth/v1/signup", method="POST", body={})
    phone = sess["access_token"] if st == 200 else None
    st, rows = call(f"/rest/v1/announcements?title=eq.{tag}&select=body",
                    token=phone)
    check("the parent's anonymous phone reads it too",
          st == 200 and len(rows or []) == 1, (st, rows))

    st, out = call("/rest/v1/announcements", method="POST", token=phone,
                   body={"audience": "both", "title": tag, "body": "x"})
    check("no client can write a notice", st >= 400, (st, out))

    st, out = call("/rest/v1/app_config?id=eq.true", method="PATCH",
                   token=phone, body={"store_listed": True},
                   prefer="return=representation")
    st2, cfg = call("/rest/v1/app_config?select=store_listed,latest_build")
    check("no client can switch the install link on",
          (st >= 400 or not out) and cfg and cfg[0]["store_listed"] is False,
          (st, out, cfg))
    check("and the settings read", st2 == 200 and len(cfg) == 1, (st2, cfg))
    if phone and sess.get("user"):
        user_id = sess["user"]["id"]
finally:
    sql(f"delete from public.announcements where title = '{tag}'")
    try:
        sql(f"delete from auth.users where id = '{user_id}'")
    except NameError:
        pass

print("\n" + ("ALL CHECKS PASSED" if not failures else f"{len(failures)} FAILED: {failures}"))
raise SystemExit(1 if failures else 0)
