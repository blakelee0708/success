"""Puts `supabase/migrations/` on a project, in order, and then counts what landed.

Written so the Seoul move is one command rather than a shell loop pasted out
of a chat log. There are thirteen files and the order is the file name order;
getting it wrong does not fail cleanly, because a later migration alters what
an earlier one created.

Three things it does that a loop does not:

- **It refuses to run on a project that already has tables**, unless told
  otherwise. Half-applying a schema over an existing one is the state nobody
  can diagnose afterwards, and `create table` without `if not exists` fails
  partway and leaves the rest unapplied.
- **It creates the `cron` schema first.** `20261021030000_care_alerts.sql`
  calls `create extension if not exists pg_cron with schema cron`, which needs
  that schema to exist. On the Singapore project pg_cron sits in `pg_catalog`
  instead, and `if not exists` does not move an extension that is already
  there - so that file is the one most likely to stop a fresh project, and
  this removes the reason.
- **It counts afterwards.** A migration can return 2xx and still not have
  created what the next one expects, so the run ends with the same five
  numbers `docs/SEOUL_MIGRATION.md` records from the project being replaced.

Run with:
    SSL_CERT_FILE=/root/.ccr/ca-bundle.crt python3 tool/apply_migrations.py

Add `--force` to apply over a project that is not empty. Add `--check` to skip
applying and only print the counts.
"""
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

# The agent proxy rejects the default Python-urllib user agent with a 403.
urllib.request.install_opener(urllib.request.build_opener())

REF = os.environ["SUPABASE_PROJECT_REF"]
MGMT = os.environ["SUPABASE_ACCESS_TOKEN"]
UA = "curl/8.5.0"
QUERY = f"https://api.supabase.com/v1/projects/{REF}/database/query"

MIGRATIONS = pathlib.Path("supabase/migrations")

# Read off the project being replaced on 2026-10-27, by query rather than from
# memory. Only `pg_cron` of the six extensions is created by a migration; the
# rest come with a fresh Supabase project.
EXPECTED = {"tables": 9, "functions": 37, "policies": 14, "extensions": 6, "cron_jobs": 1}

COUNTS_SQL = """
select
 (select count(*) from pg_tables where schemaname = 'public') as tables,
 (select count(*) from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public') as functions,
 (select count(*) from pg_policies where schemaname = 'public') as policies,
 (select count(*) from pg_extension) as extensions;
"""


def run(sql):
    """Returns (ok, payload_or_error)."""
    req = urllib.request.Request(
        QUERY,
        data=json.dumps({"query": sql}).encode(),
        method="POST",
        headers={
            "Authorization": f"Bearer {MGMT}",
            "User-Agent": UA,
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req) as r:
            body = r.read().decode()
            return True, json.loads(body) if body.strip() else []
    except urllib.error.HTTPError as e:
        return False, e.read().decode()[:1200]


def counts():
    ok, rows = run(COUNTS_SQL)
    if not ok:
        print(f"could not read the counts:\n{rows}")
        raise SystemExit(1)
    out = dict(rows[0])
    # pg_cron may not be installed, in which case `cron.job` does not exist
    # and asking for it is an error rather than a zero.
    ok, rows = run("select count(*) as cron_jobs from cron.job;")
    out["cron_jobs"] = dict(rows[0])["cron_jobs"] if ok else 0
    return out


def main():
    force = "--force" in sys.argv
    check_only = "--check" in sys.argv
    print(f"project {REF}")

    if not check_only:
        ok, rows = run(
            "select count(*) as n from pg_tables where schemaname = 'public';"
        )
        if not ok:
            print(f"could not reach the database:\n{rows}")
            raise SystemExit(1)
        existing = dict(rows[0])["n"]
        if existing and not force:
            print(
                f"\npublic already holds {existing} table(s). Refusing to apply "
                "over it.\nRe-run with --force if that is really what you want, "
                "or with --check to only count."
            )
            raise SystemExit(1)

        # The one pre-step, and the reason is in this file's docstring.
        print("\nmaking sure the cron schema exists")
        ok, err = run("create schema if not exists cron;")
        print(f"  {'ok' if ok else 'FAILED'}  create schema if not exists cron")
        if not ok:
            # Not fatal on its own: a project where this is refused may still
            # have a usable `cron` schema, and care_alerts will say so.
            print(f"        {err}")

        files = sorted(MIGRATIONS.glob("*.sql"))
        print(f"\napplying {len(files)} migration(s), in file-name order")
        for f in files:
            ok, err = run(f.read_text())
            print(f"  {'ok  ' if ok else 'FAIL'}  {f.name}")
            if not ok:
                print(f"\n{f.name} failed and nothing after it was applied:\n{err}")
                raise SystemExit(1)

    print("\ncounting what is there")
    got = counts()
    bad = []
    for key, want in EXPECTED.items():
        have = got.get(key)
        same = have == want
        print(f"  {'ok  ' if same else 'FAIL'}  {key}: {have} (expected {want})")
        if not same:
            bad.append(key)

    print()
    if bad:
        print(f"{len(bad)} COUNT(S) DO NOT MATCH: {', '.join(bad)}")
        print("The schema is not the same as the project this replaces.")
        raise SystemExit(1)
    print("SCHEMA MATCHES")
    print("\nNext: the eight verifiers, then tool/apply_auth_templates.py.")
    print("The owner's dashboard settings are in docs/SEOUL_MIGRATION.md -")
    print("anonymous sign-ins above all, or no senior phone can connect.")


if __name__ == "__main__":
    main()
