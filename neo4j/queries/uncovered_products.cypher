// Aviso global da análise (seção 03, estado "Sem vínculo cadastrado"): produtos da requisição que
// nenhum fornecedor ativo atende. Complementa supplier_coverage.cypher, que só lista quem cobre algo;
// com esta consulta a interface mostra "Nenhum fornecedor está associado ao produto X" mesmo quando
// o ranking vem vazio.
// Parâmetros: $requisitionId, $kitchenId (mesma validação do traversal principal)
MATCH (r:Requisition {id: $requisitionId, kitchenId: $kitchenId})-[:REQUESTS]->(p:Product)
WHERE NOT EXISTS {
  MATCH (s:Supplier)-[:SUPPLIES]->(p)
  WHERE s.active = true AND p.active = true
}
RETURN DISTINCT p.id AS productId, p.name AS name, p.active AS productActive
ORDER BY name;
