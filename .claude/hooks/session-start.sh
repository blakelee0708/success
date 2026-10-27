#!/bin/bash
# SessionStart hook: make `flutter analyze` and `flutter test` work in
# Claude Code on the web, where no Flutter SDK is present by default.
#
# Safe to re-run: an SDK already at the pinned revision is left alone.
set -euo pipefail

# Local machines already have their own Flutter; only set up the remote container.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Bump this when .metadata's revision changes (i.e. after `flutter upgrade`).
FLUTTER_VERSION="3.38.9"
FLUTTER_HOME="/opt/flutter"
ARCHIVE="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
BASE_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# The SDK ships as a git checkout owned by root; without this every flutter
# command dies on "detected dubious ownership".
allow_git() { git config --global --add safe.directory "$FLUTTER_HOME" 2>/dev/null || true; }

# .metadata is the project's source of truth for which SDK build to run.
want_rev="$(awk '/^  revision:/ {gsub(/"/, "", $2); print $2}' "$PROJECT_DIR/.metadata")"
have_rev() { git -C "$FLUTTER_HOME" rev-parse HEAD 2>/dev/null || true; }

allow_git
if [ -z "$want_rev" ] || [ "$(have_rev)" != "$want_rev" ]; then
  echo "Installing Flutter ${FLUTTER_VERSION}..."
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL -o "$tmp/$ARCHIVE" "$BASE_URL/$ARCHIVE"
  rm -rf "$FLUTTER_HOME"
  tar -xJf "$tmp/$ARCHIVE" -C "$(dirname "$FLUTTER_HOME")"
  allow_git

  if [ -n "$want_rev" ] && [ "$(have_rev)" != "$want_rev" ]; then
    echo "WARNING: installed Flutter ${FLUTTER_VERSION} is revision $(have_rev)," >&2
    echo "         but .metadata pins $want_rev." >&2
    echo "         Update FLUTTER_VERSION in $0 to match." >&2
  fi
else
  echo "Flutter ${FLUTTER_VERSION} already installed."
fi

export PATH="$FLUTTER_HOME/bin:$PATH"

# Persist PATH so later tool calls in this session find flutter/dart.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$FLUTTER_HOME/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi

# Analyzer and tests both need the package config resolved.
cd "$PROJECT_DIR"
flutter pub get

flutter --version

# ---------------------------------------------------------------------------
# Supabase: say at the top of every session whether this container can reach
# the project, because the alternative is finding out halfway through.
#
# The ref lives in `supabase/project.ref`, NOT in the environment. It is not a
# secret - it is in the dashboard URL, in every APK's SUPABASE_URL and in
# site/reset.html's source - and keeping it in the repo means the only thing
# the owner has to set is the token. `SUPABASE_PROJECT_REF` is exported from
# the file below, so all nine tool/ scripts target the right project even when
# the environment still holds an older value. That exact mismatch cost a
# session on 2026-10-27.
#
# Nothing here fails the session. A container that cannot reach Supabase can
# still run the tests, write the screens and do most of the work; refusing to
# start would be worse than saying so.
# ---------------------------------------------------------------------------
supabase_status() {
  local ref_file="$PROJECT_DIR/supabase/project.ref"
  [ -f "$ref_file" ] || return 0
  local want
  want="$(tr -d '[:space:]' < "$ref_file")"
  [ -n "$want" ] || return 0

  echo
  echo "Supabase: project $want (from supabase/project.ref)"

  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo "export SUPABASE_PROJECT_REF=\"$want\"" >> "$CLAUDE_ENV_FILE"
  fi
  if [ -n "${SUPABASE_PROJECT_REF:-}" ] && [ "$SUPABASE_PROJECT_REF" != "$want" ]; then
    echo "  note: the environment says $SUPABASE_PROJECT_REF; the repo wins."
  fi
  export SUPABASE_PROJECT_REF="$want"

  if [ -z "${SUPABASE_ACCESS_TOKEN:-}" ]; then
    echo "  NOT CONNECTED: no SUPABASE_ACCESS_TOKEN in this environment."
    echo "  Add it to the cloud environment settings (the one this session"
    echo "  runs in), then start a new session - a running one cannot pick"
    echo "  it up. See docs/SEOUL_MIGRATION.md."
    return 0
  fi

  local body code region
  body="$(curl -s -m 20 -w '\n%{http_code}' \
            -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
            -H 'User-Agent: curl/8.5.0' \
            "https://api.supabase.com/v1/projects/$want" 2>/dev/null || true)"
  code="$(printf '%s' "$body" | tail -1)"

  case "$code" in
    200)
      region="$(printf '%s' "$body" | sed -n 's/.*"region":"\([^"]*\)".*/\1/p')"
      echo "  CONNECTED. region: ${region:-unknown}"
      # site/privacy.html tells Play and every reader that the database is in
      # Korea. ap-northeast-2 is Seoul; ap-northeast-1 is Tokyo and would make
      # that sentence false.
      if [ -n "$region" ] && [ "$region" != "ap-northeast-2" ]; then
        echo "  WARNING: site/privacy.html says the database is in 대한민국,"
        echo "           but this project is in $region. Either the project is"
        echo "           in the wrong region or that sentence has to change."
      fi
      ;;
    403)
      echo "  NOT CONNECTED: 403. The project exists, but this token's account"
      echo "  cannot see it. The token has to be made on the account that owns"
      echo "  $want. See docs/SEOUL_MIGRATION.md."
      ;;
    404)
      echo "  NOT CONNECTED: 404. No project with this ref. Check"
      echo "  supabase/project.ref against the dashboard URL."
      ;;
    *)
      echo "  could not reach the Management API (HTTP ${code:-none})."
      ;;
  esac
}

supabase_status || true
