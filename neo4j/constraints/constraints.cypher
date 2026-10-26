// Seção 05 de neo4j/docs/COBERTURA_FORNECEDORES.md — constraints da projeção de cobertura de fornecedores.
// Idempotente (IF NOT EXISTS). A unicidade dos relacionamentos é garantida pelo padrão de MERGE
// com as chaves relacionais (itemId em REQUESTS; productId + supplierId em SUPPLIES).

CREATE CONSTRAINT requisition_id IF NOT EXISTS
FOR (r:Requisition) REQUIRE r.id IS UNIQUE;

CREATE CONSTRAINT product_id IF NOT EXISTS
FOR (p:Product) REQUIRE p.id IS UNIQUE;

CREATE CONSTRAINT supplier_id IF NOT EXISTS
FOR (s:Supplier) REQUIRE s.id IS UNIQUE;
