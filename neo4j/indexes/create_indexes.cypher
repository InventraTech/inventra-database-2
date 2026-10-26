// Dicionário dos índices da projeção (docs/COBERTURA_FORNECEDORES.md, seção 05).
// As constraints de unicidade já criam índice em id; estes apoiam a entrada por cozinha e o filtro de fornecedor ativo.
// Uso: cypher-shell -f indexes/create_indexes.cypher

// Traversal entra por {id, kitchenId}: filtro defensivo contra vazamento entre cozinhas
CREATE INDEX requisition_kitchen IF NOT EXISTS
FOR (r:Requisition) ON (r.kitchenId);

// Só fornecedores ativos entram no ranking
CREATE INDEX supplier_active IF NOT EXISTS
FOR (s:Supplier) ON (s.active);
