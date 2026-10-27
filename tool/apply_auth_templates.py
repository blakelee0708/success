"""The Korean auth mail copy, and the one command that puts it on a project.

**This file exists because the copy had nowhere else to live.** Until it was
written the Korean subjects and bodies existed only as rows in the Singapore
project's auth config - not in this repository, not in any backup - and the
plan is to delete that project once the Korean one is proven. Nobody would
have noticed until a guardian asked for a password reset and got
`Reset your password` in English.

Two templates are Korean and the rest are Supabase's English defaults. Only
these two are sent anything: a reset is the one auth mail that cannot be
switched off, and the confirmation pair is kept ready for the day
`Confirm email` is switched back on.

**The flag is the whole trap.** A stored body is used only when its key in
`mailer_subjects_custom_contents` / `mailer_templates_custom_contents` is
true, and a Korean body sitting behind a false flag sends the English default
with no sign whatever that anything is wrong. So this does not finish on a
2xx: it reads the config back and fails loudly if a flag did not come with
the body.

Run with:
    SSL_CERT_FILE=/root/.ccr/ca-bundle.crt python3 tool/apply_auth_templates.py

It only writes mail copy. The three settings an agent cannot touch here
(`Confirm email`, `uri_allow_list`, `site_url`) are the owner's, and
`docs/SEOUL_MIGRATION.md` lists them.
"""
import json
import os
import urllib.error
import urllib.request

# The agent proxy rejects the default Python-urllib user agent with a 403.
urllib.request.install_opener(urllib.request.build_opener())

REF = os.environ["SUPABASE_PROJECT_REF"]
MGMT = os.environ["SUPABASE_ACCESS_TOKEN"]
UA = "curl/8.5.0"
CONFIG = f"https://api.supabase.com/v1/projects/{REF}/config/auth"

RECOVERY_SUBJECT = "비밀번호를 새로 정해 주세요"

RECOVERY_BODY = """\
<h2 style="margin:0 0 16px;font-size:21px;color:#191F28;">비밀번호를 새로 정해 주세요</h2>
<p style="margin:0 0 14px;font-size:15px;line-height:1.7;color:#4E5968;">
잘보이네 보호자 계정의 비밀번호를 바꾸시려고 요청하셨습니다.<br>
아래 버튼을 누르시면 새 비밀번호를 정하는 화면이 열립니다.
</p>
<p style="margin:0 0 20px;">
<a href="{{ .ConfirmationURL }}" style="display:inline-block;padding:14px 26px;border-radius:12px;background:#0B5FD9;color:#ffffff;font-size:16px;font-weight:bold;text-decoration:none;">새 비밀번호 정하기</a>
</p>
<p style="margin:0 0 10px;font-size:13.5px;line-height:1.7;color:#5F6B7A;">
이 링크는 한 시간 동안만 쓸 수 있습니다.
</p>
<p style="margin:0;font-size:13.5px;line-height:1.7;color:#5F6B7A;">
요청하신 적이 없다면 이 메일은 그냥 두셔도 됩니다. 비밀번호는 그대로입니다.
</p>"""

CONFIRMATION_SUBJECT = "가입을 마무리해 주세요"

CONFIRMATION_BODY = """\
<h2 style="margin:0 0 16px;font-size:21px;color:#191F28;">가입을 마무리해 주세요</h2>
<p style="margin:0 0 14px;font-size:15px;line-height:1.7;color:#4E5968;">
잘보이네 보호자 계정을 만드셨습니다.<br>
아래 버튼을 누르시면 가입이 끝나고 바로 쓰실 수 있습니다.
</p>
<p style="margin:0 0 20px;">
<a href="{{ .ConfirmationURL }}" style="display:inline-block;padding:14px 26px;border-radius:12px;background:#0B5FD9;color:#ffffff;font-size:16px;font-weight:bold;text-decoration:none;">가입 마무리하기</a>
</p>
<p style="margin:0;font-size:13.5px;line-height:1.7;color:#5F6B7A;">
가입하신 적이 없다면 이 메일은 그냥 두셔도 됩니다.
</p>"""

WANTED = {
    "mailer_subjects_recovery": RECOVERY_SUBJECT,
    "mailer_templates_recovery_content": RECOVERY_BODY,
    "mailer_subjects_confirmation": CONFIRMATION_SUBJECT,
    "mailer_templates_confirmation_content": CONFIRMATION_BODY,
}

# Which flag key guards which field. The dashboard writes these itself; this
# is the list the read-back is checked against.
FLAGS = {
    "mailer_subjects_recovery": ("mailer_subjects_custom_contents", "MAILER_SUBJECTS_RECOVERY"),
    "mailer_templates_recovery_content": (
        "mailer_templates_custom_contents",
        "MAILER_TEMPLATES_RECOVERY_CONTENT",
    ),
    "mailer_subjects_confirmation": (
        "mailer_subjects_custom_contents",
        "MAILER_SUBJECTS_CONFIRMATION",
    ),
    "mailer_templates_confirmation_content": (
        "mailer_templates_custom_contents",
        "MAILER_TEMPLATES_CONFIRMATION_CONTENT",
    ),
}

failures = []


def check(label, ok, detail=""):
    print(f"  {'ok  ' if ok else 'FAIL'}  {label}")
    if not ok:
        if detail:
            print(f"        {detail}")
        failures.append(label)


def read_config():
    req = urllib.request.Request(
        CONFIG, headers={"Authorization": f"Bearer {MGMT}", "User-Agent": UA}
    )
    return json.load(urllib.request.urlopen(req))


def patch(body):
    req = urllib.request.Request(
        CONFIG,
        data=json.dumps(body).encode(),
        method="PATCH",
        headers={
            "Authorization": f"Bearer {MGMT}",
            "User-Agent": UA,
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, None
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:400]


def flag_payload(before):
    """The two flag objects, with only the four keys this script owns set true.

    The content fields are gated on these: with the flag false the API takes a
    `mailer_subjects_recovery` and returns 200 having stored nothing, which is
    the exact shape of failure this script was written to catch. So the flags
    go in the same call as the copy, and the other keys in each object are
    sent back as they were rather than being replaced wholesale.
    """
    out = {}
    for obj_key, flag_key in FLAGS.values():
        obj = dict(before.get(obj_key) or {})
        obj[flag_key] = True
        out[obj_key] = obj
    return out


def main():
    print(f"project {REF}")

    print("\nwriting the Korean mail copy, and the flags that decide it is used")
    body = dict(WANTED)
    body.update(flag_payload(read_config()))
    status, err = patch(body)
    check(f"PATCH /config/auth returned {status}", status in (200, 201), err or "")

    print("\nreading it back, because a 2xx is not the question")
    after = read_config()
    for field, want in WANTED.items():
        got = after.get(field) or ""
        check(f"{field} is the Korean copy", got.strip() == want.strip(),
              f"server has: {got[:80]!r}")

    print("\nand the flags, which are what actually decide what is sent")
    for field, (bucket, key) in FLAGS.items():
        on = bool((after.get(bucket) or {}).get(key))
        check(
            f"{bucket}[{key}] is true",
            on,
            "the body is stored but UNUSED - the English default goes out, "
            "silently. Turn this template on in the dashboard's Emails "
            "section (opening the template and saving it sets the flag).",
        )

    print()
    if failures:
        print(f"{len(failures)} CHECK(S) FAILED")
        for f in failures:
            print(f"  - {f}")
        raise SystemExit(1)
    print("ALL CHECKS PASSED")


if __name__ == "__main__":
    main()
