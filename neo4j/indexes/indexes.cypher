// Seção 05 de neo4j/docs/COBERTURA_FORNECEDORES.md — índices de apoio à entrada por requisição/cozinha.
// Idempotente (IF NOT EXISTS).

CREATE INDEX requisition_kitchen IF NOT EXISTS
FOR (r:Requisition) ON (r.kitchenId);

CREATE INDEX supplier_active IF NOT EXISTS
FOR (s:Supplier) ON (s.active);
