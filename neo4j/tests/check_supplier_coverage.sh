#!/usr/bin/env bash
# Integração do traversal de cobertura (docs/COBERTURA_FORNECEDORES.md, seções 11 e 12) num Neo4j real:
# carrega a massa 4×3 da requisição #842, roda queries/supplier_coverage.cypher e confere ranking,
# percentuais, custo e prazo; depois exercita os eventos de projection/ (idempotência, lacuna,
# desativação, remoção e preço nulo) e o isolamento por cozinha.
# Uso (dentro de um neo4j:5 descartável, com NEO4J_AUTH=none): bash neo4j/tests/check_supplier_coverage.sh
# Nunca apontar para o banco real: o passo 1 apaga a projeção.
set -euo pipefail

cd "$(dirname "$0")/.."
q() { cypher-shell --format plain "$@"; }
event() { q -P "$2" -f "projection/$1.cypher" > /dev/null; }
# Uma linha por fornecedor, na ordem do ranking: nome | cobertura % | custo | prazo máx. | sem preço | lacunas
ranking() {
  local params=${1:-}; [ -n "$params" ] || params='{requisitionId: 842, kitchenId: 12}'
  { echo 'CALL {'; sed -e 's/\r$//' -e '$ s/;[[:space:]]*$//' queries/supplier_coverage.cypher; echo '}'
    echo "WITH *, reduce(s = '', n IN COLLECT { UNWIND uncovered AS u RETURN u.name ORDER BY u.name } | s + CASE s WHEN '' THEN '' ELSE ', ' END + n) AS gaps"
    echo "RETURN supplierName + ' | ' + toString(coveragePercent) + ' | ' + toString(estimatedCoveredCost) + ' | '"
    echo "  + toString(maxLeadTimeDays) + ' | ' + toString(priceMissingCount) + ' | ' + CASE gaps WHEN '' THEN '-' ELSE gaps END AS row;"
  } | q -P "$params" | tail -n +2 | tr -d '"'
}
uncovered() { q -P '{requisitionId: 842, kitchenId: 12}' -f queries/uncovered_products.cypher | tail -n +2 | cut -d, -f2 | sed 's/^ *"//; s/"$//' | paste -sd, -; }
counts() { q "MATCH (n) WHERE n:Requisition OR n:Product OR n:Supplier WITH count(n) AS nodes
              OPTIONAL MATCH ()-[r:REQUESTS|SUPPLIES]->() RETURN nodes, count(r);" | tail -1; }
# Propriedades de negócio de todas as arestas (updatedAt fica de fora: muda a cada evento por desenho)
edges() { q "MATCH (a)-[r:REQUESTS|SUPPLIES]->(b)
             RETURN type(r), a.id, b.id, r.itemId, r.quantity, r.estimatedPrice, r.note, r.supplierCode, r.referencePrice, r.leadTimeDays
             ORDER BY type(r), a.id, b.id;"; }
expect() {
  if [ "$2" != "$3" ]; then echo "FALHOU: $1"; echo "esperado:"; echo "$2"; echo "obtido:"; echo "$3"; exit 1; fi
  echo "  ok  $1"
}

echo "1/8 schema + massa da seção 11"
q -f migrations/rollback/drop_everything.cypher > /dev/null
for f in migrations/V*.cypher; do q -f "$f" > /dev/null; done
q -f seeds/requisition_842.cypher > /dev/null

echo "2/8 ranking da requisição #842"
expect "ordem Alfa, Gama, Beta; 75/75/50; R\$ 486,50 / 465,40 / 138,00" "$(cat <<'EOF'
Distribuidora Alfa | 75.0 | 486.5 | 3 | 0 | Leite
Gama | 75.0 | 465.4 | 7 | 0 | Óleo
Beta | 50.0 | 138.0 | 5 | 0 | Arroz, Feijão
EOF
)" "$(ranking)"
expect "nenhum produto sem fornecedor" "" "$(uncovered)"

echo "3/8 isolamento por cozinha"
expect "kitchenId de outra cozinha não enxerga a requisição" "" "$(ranking '{requisitionId: 842, kitchenId: 99}')"
expect "requisição inexistente devolve ranking vazio" "" "$(ranking '{requisitionId: 999, kitchenId: 12}')"

echo "4/8 idempotência (mesmo evento duas vezes)"
before_counts=$(counts); before_edges=$(edges)
q -f seeds/requisition_842.cypher > /dev/null
ITEMS='{requisition: {id: 842, kitchenId: 12, type: "PURCHASE", status: "UNDER_REVIEW"}, items: [
  {itemId: 1, productId: 10, productName: "Arroz",  productActive: true, quantity: 20, estimatedPrice: null, note: null},
  {itemId: 2, productId: 11, productName: "Óleo",   productActive: true, quantity: 10, estimatedPrice: null, note: null},
  {itemId: 3, productId: 12, productName: "Feijão", productActive: true, quantity: 5,  estimatedPrice: null, note: null},
  {itemId: 4, productId: 13, productName: "Leite",  productActive: true, quantity: 12, estimatedPrice: null, note: null}]}'
event requisition_upserted "$ITEMS"
event requisition_upserted "$ITEMS"
SUPPLY='{supplierId: 31, legalName: "Distribuidora Alfa", rating: 5, active: true, productId: 10, supplierCode: "ALF-010", referencePrice: 18.50, leadTimeDays: 2}'
event product_supplier_upserted "$SUPPLY"
event product_supplier_upserted "$SUPPLY"
expect "contagens de nós e arestas não mudam" "$before_counts" "$(counts)"
expect "propriedades das arestas permanecem iguais" "$before_edges" "$(edges)"

echo "5/8 lacuna: produto sem nenhum SUPPLIES"
event requisition_upserted '{requisition: {id: 842, kitchenId: 12, type: "PURCHASE", status: "UNDER_REVIEW"}, items: [
  {itemId: 1, productId: 10, productName: "Arroz",          productActive: true, quantity: 20, estimatedPrice: null, note: null},
  {itemId: 2, productId: 11, productName: "Óleo",           productActive: true, quantity: 10, estimatedPrice: null, note: null},
  {itemId: 3, productId: 12, productName: "Feijão",         productActive: true, quantity: 5,  estimatedPrice: null, note: null},
  {itemId: 4, productId: 13, productName: "Leite",          productActive: true, quantity: 12, estimatedPrice: null, note: null},
  {itemId: 5, productId: 14, productName: "Leite integral", productActive: true, quantity: 6,  estimatedPrice: null, note: "sem fornecedor"}]}'
expect "aviso global lista o produto sem fornecedor" "Leite integral" "$(uncovered)"
expect "produto aparece como descoberto para todos os candidatos" "$(cat <<'EOF'
Distribuidora Alfa | 60.0 | 486.5 | 3 | 0 | Leite, Leite integral
Gama | 60.0 | 465.4 | 7 | 0 | Leite integral, Óleo
Beta | 40.0 | 138.0 | 5 | 0 | Arroz, Feijão, Leite integral
EOF
)" "$(ranking)"
event item_deleted '{requisitionId: 842, itemId: 5}'
expect "ITEM_DELETED tira o produto da demanda" "$(cat <<'EOF'
Distribuidora Alfa | 75.0 | 486.5 | 3 | 0 | Leite
Gama | 75.0 | 465.4 | 7 | 0 | Óleo
Beta | 50.0 | 138.0 | 5 | 0 | Arroz, Feijão
EOF
)" "$(ranking)"

echo "6/8 item removido no PostgreSQL some no upsert completo"
event requisition_upserted '{requisition: {id: 842, kitchenId: 12, type: "PURCHASE", status: "UNDER_REVIEW"}, items: [
  {itemId: 1, productId: 10, productName: "Arroz",  productActive: true, quantity: 20, estimatedPrice: null, note: null},
  {itemId: 2, productId: 11, productName: "Óleo",   productActive: true, quantity: 10, estimatedPrice: null, note: null},
  {itemId: 3, productId: 12, productName: "Feijão", productActive: true, quantity: 5,  estimatedPrice: null, note: null}]}'
expect "Leite fora da requisição: cobertura recalculada sobre 3 produtos" "$(cat <<'EOF'
Distribuidora Alfa | 100.0 | 486.5 | 3 | 0 | -
Gama | 66.7 | 397.0 | 7 | 0 | Óleo
Beta | 33.3 | 72.0 | 5 | 0 | Arroz, Feijão
EOF
)" "$(ranking)"
q -f seeds/requisition_842.cypher > /dev/null

echo "7/8 desativação e desvínculo"
event supplier_updated '{supplierId: 31, legalName: "Distribuidora Alfa", rating: 5, active: false}'
expect "fornecedor inativo sai do ranking" "$(cat <<'EOF'
Gama | 75.0 | 465.4 | 7 | 0 | Óleo
Beta | 50.0 | 138.0 | 5 | 0 | Arroz, Feijão
EOF
)" "$(ranking)"
event supplier_updated '{supplierId: 31, legalName: "Distribuidora Alfa", rating: 5, active: true}'
event product_updated '{productId: 11, name: "Óleo", active: false}'
expect "produto inativo vira lacuna para todos" "Óleo" "$(uncovered)"
event product_updated '{productId: 11, name: "Óleo", active: true}'
event product_supplier_deleted '{supplierId: 33, productId: 13}'
expect "SUPPLIES removido (reconciliação de órfão) reduz Gama a 50% e o prazo põe Beta na frente" "$(cat <<'EOF'
Distribuidora Alfa | 75.0 | 486.5 | 3 | 0 | Leite
Beta | 50.0 | 138.0 | 5 | 0 | Arroz, Feijão
Gama | 50.0 | 397.0 | 7 | 0 | Leite, Óleo
EOF
)" "$(ranking)"
q -f seeds/requisition_842.cypher > /dev/null

echo "8/8 preço nulo não vira preço zero silencioso"
event product_supplier_upserted '{supplierId: 32, legalName: "Beta", rating: 4, active: true, productId: 11, supplierCode: "BET-011", referencePrice: null, leadTimeDays: 5}'
expect "priceMissingCount sinaliza custo incompleto" "Beta | 50.0 | 66.0 | 5 | 1 | Arroz, Feijão" "$(ranking | grep '^Beta')"
q -f seeds/requisition_842.cypher > /dev/null

echo "OK"
