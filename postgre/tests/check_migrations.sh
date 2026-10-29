#!/usr/bin/env bash
# Valida a esteira de migrations: aplica todas as migrations (V*.sql) duas vezes (idempotência),
# reverte tudo com drop_everything.sql e reaplica do zero.
# Uso: PGHOST=... PGUSER=... PGPASSWORD=... PGDATABASE=... ./check_migrations.sh
set -euo pipefail

cd "$(dirname "$0")/../migrations"
PSQL=(psql -v ON_ERROR_STOP=1 --single-transaction -q -f)

apply() {
  for f in V*.sql; do
    echo "  -> $f"
    "${PSQL[@]}" "$f"
  done
}

echo "1/4 aplicando migrations (banco limpo)"; apply
echo "2/4 reaplicando (idempotência)";        apply
echo "3/4 rollback completo";                 "${PSQL[@]}" rollback/drop_everything.sql
echo "4/4 reaplicando após rollback";         apply
echo "OK"
