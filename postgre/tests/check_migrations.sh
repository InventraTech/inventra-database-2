#!/usr/bin/env bash
# Valida a esteira de migrations: aplica as migrations (V*.sql) em ordem, reaplicando cada uma logo
# em seguida (idempotência), reverte tudo com drop_everything.sql e reaplica do zero.
# Cada migration é reaplicada no estado em que ela mesma deixou o banco, e não depois de todas: uma
# migration que remove objeto (V022 dropa tb_alert.is_read, ainda citada por V001, V004 e V008) não
# permite reaplicar as anteriores sobre o estado final, e migration aplicada não se edita (checksum do Flyway).
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

apply_twice() {
  for f in V*.sql; do
    echo "  -> $f (2x)"
    "${PSQL[@]}" "$f"
    "${PSQL[@]}" "$f"
  done
}

echo "1/3 aplicando migrations (banco limpo), cada uma duas vezes (idempotência)"; apply_twice
echo "2/3 rollback completo";                                                       "${PSQL[@]}" rollback/drop_everything.sql
echo "3/3 reaplicando após rollback";                                               apply
echo "OK"
