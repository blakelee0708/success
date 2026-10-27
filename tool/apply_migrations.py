"""Puts `supabase/migrations/` on a project, in order, and then counts what landed.

Written so the Seoul move is one command rather than a shell loop pasted out
of a chat log. There are fourteen files and the order is the file name order;
getting it wrong does not fail cleanly, because a later migration alters what
an earlier one created.

Three things it does that a loop does not:

- **It refuses to run on a project that already has tables**, unless told
  otherwise. Half-applying a schema over an existing one is the state nobody
  can diagnose afterwards, and `create table` without `if not exists` fails
  partway and leaves the rest unapplied.
- **It clears an empty `cron` schema first.** `20261021030000_care_alerts.sql`
  calls `create extension if not exists pg_cron with schema cron`, and
  `create extension` **creates** that schema itself - it does not want one
  already there. Handed an existing `cron` it fails with 42P06
  `schema "cron" already exists`, which is what stopped the Seoul project on
  2026-10-27: an earlier version of this pre-step created the schema, on the
  belief that the extension needed it, and so broke the file it meant to
  unblock. So the pre-step now goes the other way - if pg_cron is not
  installed, an empty `cron` schema is dropped. It drops with RESTRICT, so a
  schema somebody has put something in refuses rather than being destroyed,
  and a project that already has pg_cron is left alone.
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
#
# 38 rather than that day's 37: `20261027000000_message_images.sql` adds
# `message_image_profile`, which the photo bucket's storage policies read the
# senior's profile id out of a file path with. The 14 policies are `public`
# only - the two on `storage.objects` are counted by that migration's own
# verifier, not here.
EXPECTED = {"tables": 9, "functions": 38, "policies": 14, "extensions": 6, "cron_jobs": 1}

# The function count asks about *our* schema, so it leaves out the event-trigger
# helpers the platform installs into `public` itself. A newer project ships
# `rls_auto_enable`, which enables RLS on any table created in `public`; the
# 2026-10-27 project predates it, so counting every function made a fresh Seoul
# project read 38 against an expected 37 with nothing whatever wrong. None of
# the thirteen migrations declares an event trigger, so the filter cannot hide
# one of ours.

# `create extension ... with schema cron` creates that schema and fails 42P06
# if it is already there, so an empty one left by anything else has to go.
# A project that already has pg_cron is left exactly as it is, and a `cron`
# holding objects refuses to drop rather than being destroyed.
CRON_PRESTEP_SQL = """
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    return;
  end if;
  if exists (select 1 from pg_namespace where nspname = 'cron') then
    drop schema cron;
  end if;
end $$;
"""

COUNTS_SQL = """
select
 (select count(*) from pg_tables where schemaname = 'public') as tables,
 (select count(*) from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prorettype <> 'pg_catalog.event_trigger'::regtype) as functions,
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
        print("\nclearing an empty cron schema, if pg_cron is not installed yet")
        ok, err = run(CRON_PRESTEP_SQL)
        print(f"  {'ok' if ok else 'FAILED'}  cron schema ready for pg_cron")
        if not ok:
            # Not fatal on its own: this refuses rather than destroys when the
            # schema holds something, and care_alerts will then say so.
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
