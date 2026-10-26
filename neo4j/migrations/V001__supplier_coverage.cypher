// V001: schema da projeção de cobertura de fornecedores (Requisition, Product, Supplier).
// Idempotente (IF NOT EXISTS): reaplicar não muda nada. O mesmo conteúdo está no dicionário
// (constraints/ e indexes/); tests/check_migrations.sh compara os dois.
// Uso: cypher-shell -f migrations/V001__supplier_coverage.cypher

CREATE CONSTRAINT requisition_id IF NOT EXISTS
FOR (r:Requisition) REQUIRE r.id IS UNIQUE;

CREATE CONSTRAINT product_id IF NOT EXISTS
FOR (p:Product) REQUIRE p.id IS UNIQUE;

CREATE CONSTRAINT supplier_id IF NOT EXISTS
FOR (s:Supplier) REQUIRE s.id IS UNIQUE;

CREATE INDEX requisition_kitchen IF NOT EXISTS
FOR (r:Requisition) ON (r.kitchenId);

CREATE INDEX supplier_active IF NOT EXISTS
FOR (s:Supplier) ON (s.active);

// Registro da versão aplicada (mesmo papel do schema_migrations do MongoDB)
MERGE (m:SchemaMigration {version: 'V001'})
ON CREATE SET m.description = 'supplier_coverage', m.appliedAt = datetime();
