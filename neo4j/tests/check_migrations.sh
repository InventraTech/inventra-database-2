#!/usr/bin/env bash
# Valida a esteira do Neo4j: aplica a V001 duas vezes (idempotência), compara com o dicionário
# (constraints/ + indexes/), reverte com drop_everything.cypher e reaplica do zero.
# Uso (dentro de um neo4j:5 descartável, com NEO4J_AUTH=none): bash neo4j/tests/check_migrations.sh
# Credenciais e endereço: NEO4J_ADDRESS, NEO4J_USERNAME e NEO4J_PASSWORD (lidos pelo cypher-shell).
# Nunca apontar para o banco real: o rollback apaga a projeção.
set -euo pipefail

cd "$(dirname "$0")/.."
q() { cypher-shell --format plain "$@"; }
apply() { for f in migrations/V*.cypher; do echo "  -> $f"; q -f "$f" > /dev/null; done; }
# Constraints e índices da projeção (os LOOKUP de token são do próprio Neo4j)
schema() {
  q "SHOW CONSTRAINTS YIELD name, type, labelsOrTypes, properties RETURN name, type, labelsOrTypes, properties ORDER BY name;"
  q "SHOW INDEXES YIELD name, type, labelsOrTypes, properties, owningConstraint WHERE type <> 'LOOKUP'
     RETURN name, type, labelsOrTypes, properties, owningConstraint ORDER BY name;"
}
fail() { echo "FALHOU: $1"; shift; printf '%s\n' "$@"; exit 1; }

echo "1/6 aplicando migrations (banco limpo)"; q -f migrations/rollback/drop_everything.cypher > /dev/null; apply
first=$(schema)

echo "2/6 reaplicando (idempotência)"; apply
[ "$(schema)" = "$first" ] || fail "reaplicar a V001 mudou o schema" "$first" "---" "$(schema)"
[ "$(q 'MATCH (m:SchemaMigration) RETURN count(m);' | tail -1)" = "1" ] || fail "SchemaMigration duplicada"

echo "3/6 schema esperado"
for name in requisition_id product_id supplier_id requisition_kitchen supplier_active; do
  grep -q "\"$name\"" <<< "$first" || fail "objeto $name não foi criado pela V001" "$first"
done

echo "4/6 dicionário × migrations"
q -f migrations/rollback/drop_everything.cypher > /dev/null
q -f constraints/create_constraints.cypher > /dev/null
q -f indexes/create_indexes.cypher > /dev/null
dict=$(schema)
[ "$dict" = "$first" ] || fail "constraints/ + indexes/ divergem da V001" "V001:" "$first" "dicionário:" "$dict"

echo "5/6 rollback completo"
q -f constraints/rollback/drop_constraints.cypher > /dev/null
q -f indexes/rollback/drop_indexes.cypher > /dev/null
[ -z "$(schema | grep -v -e '^name' || true)" ] || fail "rollback do dicionário deixou objetos" "$(schema)"
apply
q -f migrations/rollback/drop_everything.cypher > /dev/null
[ -z "$(schema | grep -v -e '^name' || true)" ] || fail "drop_everything deixou objetos" "$(schema)"
[ "$(q 'MATCH (n) WHERE n:Requisition OR n:Product OR n:Supplier OR n:SchemaMigration RETURN count(n);' | tail -1)" = "0" ] || fail "drop_everything deixou nós"

echo "6/6 reaplicando após rollback"; apply
[ "$(schema)" = "$first" ] || fail "schema diferente após rollback + reaplicação" "$first" "---" "$(schema)"
echo "OK"
