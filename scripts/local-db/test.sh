#!/usr/bin/env bash
# Exécute les migrations et les tests SQL sur un PostgreSQL 16 jetable,
# sans Docker ni Supabase CLI. En CI, on utilisera `supabase test db`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PGBIN="${PGBIN:-/usr/lib/postgresql/16/bin}"
PORT="${PORT:-54329}"
DATA="$(mktemp -d /tmp/cpia-pg.XXXXXX)"
RUN_AS=""
if [ "$(id -u)" = "0" ]; then
  RUN_AS="runuser -u nobody --"
  chown nobody "$DATA"
fi

$RUN_AS "$PGBIN/initdb" -D "$DATA/db" -U postgres -A trust >/dev/null
$RUN_AS "$PGBIN/pg_ctl" -D "$DATA/db" -o "-p $PORT -k $DATA -c listen_addresses=''" -l "$DATA/log" -w start >/dev/null
trap '$RUN_AS "$PGBIN/pg_ctl" -D "$DATA/db" -m immediate stop >/dev/null 2>&1; rm -rf "$DATA"' EXIT

PSQL=(psql -h "$DATA" -p "$PORT" -U postgres -X -q -v ON_ERROR_STOP=1)
"${PSQL[@]}" -d postgres -c 'create database cpia'
"${PSQL[@]}" -d cpia -f "$ROOT/scripts/local-db/supabase_stub.sql"
"${PSQL[@]}" -d cpia -f "$ROOT/scripts/local-db/tap_shim.sql"

for f in "$ROOT"/supabase/migrations/*.sql; do
  echo "== migration $(basename "$f")"
  "${PSQL[@]}" -d cpia -f "$f"
done

# Les migrations doivent être rejouables sans erreur pour les données de référence
"${PSQL[@]}" -d cpia -f "$ROOT/supabase/migrations/20261030000002_reference_data.sql"

status=0
for t in "$ROOT"/supabase/tests/*.test.sql; do
  echo "== test $(basename "$t")"
  if ! "${PSQL[@]}" -d cpia -t -A -f "$t"; then status=1; fi
done
exit $status
