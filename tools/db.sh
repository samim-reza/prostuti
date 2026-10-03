#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Database helper for maintainers.
#
#   tools/db.sh psql                 # interactive psql session
#   tools/db.sh migrate              # apply pending supabase/migrations/*.sql
#   tools/db.sh sql "select 1"       # run a one-off statement
#   tools/db.sh file path/to.sql     # run a SQL file
#
# Credentials come from the environment (CI) or the git-ignored key.txt:
#   SUPABASE_PROJECT_REF, SUPABASE_DB_PASSWORD, SUPABASE_DB_HOST
# Applied migrations are recorded in supabase_migrations.schema_migrations,
# the same table the Supabase CLI uses, so `supabase db push` stays in sync.
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_FILE="$ROOT/key.txt"

read_key() { [[ -f "$KEY_FILE" ]] && grep -E "^$1[=:]" "$KEY_FILE" | head -1 | sed -E "s/^$1[=:]//" | tr -d '\r' || true; }

REF="${SUPABASE_PROJECT_REF:-$(read_key db_id)}"
PASS="${SUPABASE_DB_PASSWORD:-$(read_key db_pass)}"
HOST="${SUPABASE_DB_HOST:-aws-0-ap-south-1.pooler.supabase.com}"

if [[ -z "$REF" || -z "$PASS" ]]; then
  echo "Missing SUPABASE_PROJECT_REF / SUPABASE_DB_PASSWORD (or key.txt)" >&2
  exit 1
fi

export PGPASSWORD="$PASS" PGCONNECT_TIMEOUT=20
CONN="host=$HOST port=5432 user=postgres.$REF dbname=postgres sslmode=require"

run_psql() { psql "$CONN" -v ON_ERROR_STOP=1 -X -q "$@"; }

case "${1:-}" in
  psql) run_psql ;;
  sql)  run_psql -At -c "$2" ;;
  file) run_psql -f "$2" ;;
  migrate)
    run_psql -c "create schema if not exists supabase_migrations;
                 create table if not exists supabase_migrations.schema_migrations
                   (version text primary key, statements text[], name text);"
    applied="$(run_psql -At -c "select version from supabase_migrations.schema_migrations")"
    for f in "$ROOT"/supabase/migrations/*.sql; do
      base="$(basename "$f" .sql)"; version="${base%%_*}"; name="${base#*_}"
      if grep -qx "$version" <<<"$applied"; then continue; fi
      echo "→ applying $base"
      run_psql --single-transaction -f "$f"
      run_psql -c "insert into supabase_migrations.schema_migrations (version, name) values ('$version', '$name')"
    done
    echo "✓ migrations up to date"
    ;;
  *) sed -n '2,16p' "$0"; exit 1 ;;
esac
