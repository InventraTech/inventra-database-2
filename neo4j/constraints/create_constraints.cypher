// Dicionário das constraints da projeção de cobertura de fornecedores (docs/COBERTURA_FORNECEDORES.md, seção 05).
// Cada nó carrega o ID do PostgreSQL como chave: evita nó duplicado e permite MERGE idempotente.
// A unicidade das arestas vem do MERGE com as chaves relacionais (itemId em REQUESTS; supplier+product em SUPPLIES).
// Uso: cypher-shell -f constraints/create_constraints.cypher

// :Requisition <- tb_requisition.id_requisition
CREATE CONSTRAINT requisition_id IF NOT EXISTS
FOR (r:Requisition) REQUIRE r.id IS UNIQUE;

// :Product <- tb_product.id_product
CREATE CONSTRAINT product_id IF NOT EXISTS
FOR (p:Product) REQUIRE p.id IS UNIQUE;

// :Supplier <- tb_supplier.id_supplier
CREATE CONSTRAINT supplier_id IF NOT EXISTS
FOR (s:Supplier) REQUIRE s.id IS UNIQUE;
