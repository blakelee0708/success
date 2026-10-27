"""End-to-end check of the deployed `ring-phone` Edge Function.

`verify_supabase_ring.py` covers the SQL gate and deliberately does **not**
need the function deployed. This one needs it, and checks the half that gate
cannot: that the caller's JWT survives the hop, that the service account can
mint a Google token, and that FCM is actually reachable.

It sends to a **fake device token on purpose**. Nothing rings, and the reply
is what matters:

    reason=sender_unconfigured  the service account is wrong or missing.
                                Every ring for every family is failing.
    reason=INVALID_ARGUMENT     the sender works; FCM reached the end of the
                                chain and refused the made-up token, which is
                                the correct answer to a made-up token.
    reason=stale_token          same, if FCM calls it UNREGISTERED.

Those two outcomes look identical from outside the function, which is exactly
why they carry different reasons. Run with:
    SSL_CERT_FILE=/root/.ccr/ca-bundle.crt python3 tool/verify_ring_function.py
"""
import json
import os
import urllib.request
import urllib.error
import uuid

urllib.request.install_opener(urllib.request.build_opener())

REF = os.environ["SUPABASE_PROJECT_REF"]
MGMT = os.environ["SUPABASE_ACCESS_TOKEN"]
BASE = f"https://{REF}.supabase.co"
UA = "curl/8.5.0"

req = urllib.request.Request(
    f"https://api.supabase.com/v1/projects/{REF}/api-keys?reveal=true",
    headers={"Authorization": f"Bearer {MGMT}", "User-Agent": UA})
_keys = json.load(urllib.request.urlopen(req))
ANON = next(k["api_key"] for k in _keys
            if k["name"] == "anon" or k["type"] == "publishable")
SERVICE = next(k["api_key"] for k in _keys
               if k["name"] == "service_role" or k["type"] == "secret")

failures = []


def call(path, *, token=None, key=None, method="POST", body=None):
    key = key or ANON
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
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
            return e.code, raw.decode()[:400]


def check(name, cond, detail=""):
    print(("PASS  " if cond else "FAIL  ") + name + ("" if cond else f"  <- {detail}"))
    if not cond:
        failures.append(name)


users, profiles = [], []
try:
    st, sess = call("/auth/v1/signup", body={})
    assert st == 200, (st, sess)
    users.append(sess["user"]["id"])
    phone, install = sess["access_token"], "ringfn-" + uuid.uuid4().hex[:10]

    st, link = call("/rest/v1/rpc/start_senior_pairing", token=phone,
                    body={"p_install_id": install, "p_platform": "android"})
    assert st == 200, (st, link)
    pid = link["senior_profile_id"]
    profiles.append(pid)

    email = f"ringfn-{uuid.uuid4().hex[:8]}@example.com"
    pw = "ringfn-" + uuid.uuid4().hex[:8]
    st, made = call("/auth/v1/admin/users", key=SERVICE,
                    body={"email": email, "password": pw, "email_confirm": True})
    assert st in (200, 201), (st, made)
    users.append(made["id"])
    st, s2 = call("/auth/v1/token?grant_type=password",
                  body={"email": email, "password": pw})
    g1 = s2["access_token"]
    call("/rest/v1/rpc/ensure_guardian_account", token=g1, body={"p_display_name": "영희"})
    call("/rest/v1/rpc/claim_senior_pairing_code", token=g1,
         body={"p_code": link["code"], "p_display_name": "어머니"})
    call("/rest/v1/rpc/touch_senior_device", token=phone,
         body={"p_install_id": install, "p_push_token": "fake-token-for-probe"})

    def ring(tok, msg=None, key=None):
        return call("/functions/v1/ring-phone", token=tok, key=key,
                    body={"senior_profile_id": pid, "message": msg})

    # The gate's refusals have to survive the hop through the function. If the
    # function ever used the service key here instead of forwarding the
    # caller's JWT, all three of these would start succeeding.
    st, out = ring(g1)
    check("an unpaid family is refused through the function",
          st == 403 and "안심 케어" in str(out), (st, out))

    call("/rest/v1/rpc/start_care_subscription", token=g1,
         body={"p_senior_profile_id": pid})
    st, out = ring(g1)
    check("paying without the senior's consent is still refused",
          st == 403 and "안심 케어" in str(out), (st, out))

    st, out = call("/functions/v1/ring-phone", key=ANON,
                   body={"senior_profile_id": pid})
    check("a call with no session is refused", st >= 400, (st, out))

    call("/rest/v1/rpc/resolve_care_consent", token=phone,
         body={"p_senior_profile_id": pid, "p_approve": True})

    # --- the half the SQL gate cannot cover ---------------------------------
    st, out = ring(g1, "엄마 전화 좀 줘")
    reason = out.get("reason") if isinstance(out, dict) else None
    print(f"\n      실제 응답: {st} {json.dumps(out, ensure_ascii=False)}\n")

    check("the gate let a paid, consented family through",
          st != 403, (st, out))
    check("the service account can authenticate to FCM",
          reason != "sender_unconfigured",
          "FCM_SERVICE_ACCOUNT is missing or wrong")
    check("FCM answered about the device token, which means the chain is whole",
          reason in ("INVALID_ARGUMENT", "stale_token", "UNREGISTERED",
                     "NOT_FOUND") or out.get("delivered") is True,
          f"unexpected reason={reason}")

finally:
    for p in profiles:
        call(f"/rest/v1/senior_profiles?id=eq.{p}", key=SERVICE, method="DELETE")
    for u in users:
        call(f"/auth/v1/admin/users/{u}", key=SERVICE, method="DELETE")
    print(f"cleaned up {len(users)} users and {len(profiles)} profiles")

print("\n" + ("ALL CHECKS PASSED" if not failures else f"{len(failures)} FAILED: {failures}"))
raise SystemExit(1 if failures else 0)
