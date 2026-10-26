// Traversal principal (seção 07): ranking de cobertura de fornecedores de uma requisição.
// Requisition -[:REQUESTS]-> Product <-[:SUPPLIES]- Supplier, agregado por fornecedor.
// Parâmetros: $requisitionId e $kitchenId. O kitchenId NUNCA vem do cliente: a API carrega a requisição
// no PostgreSQL, valida com KitchenAccessGuard e só então consulta o grafo com id + kitchenId.
// Regras de explicabilidade:
//   cobertura = produtos distintos cobertos ÷ produtos distintos solicitados
//   prazo     = maior leadTimeDays entre os itens cobertos
//   custo     = referencePrice × quantity só onde há preço (priceMissingCount conta os sem preço)
//   rating    = vem de Supplier; nenhum score composto esconde esses componentes
// Fornecedor sem nenhum produto coberto não aparece; produto sem fornecedor ativo aparece em uncovered de todos.

MATCH (r:Requisition {id: $requisitionId, kitchenId: $kitchenId})
MATCH (r)-[req:REQUESTS]->(p:Product)
// o mesmo produto em dois itens conta uma vez, com a quantidade somada
WITH r, p, sum(req.quantity) AS quantity
WITH r,
     collect({product: p, quantity: quantity}) AS demand,
     count(p) AS totalProducts

UNWIND demand AS d
WITH demand, totalProducts, d, d.product AS product
MATCH (s:Supplier)-[sp:SUPPLIES]->(product)
WHERE s.active = true AND product.active = true

WITH demand, totalProducts, s,
     collect(DISTINCT {
       id: product.id,
       name: product.name,
       quantity: d.quantity,
       referencePrice: sp.referencePrice,
       leadTimeDays: sp.leadTimeDays
     }) AS covered,
     max(sp.leadTimeDays) AS maxLeadTimeDays

WITH totalProducts, s, covered, maxLeadTimeDays,
     [d IN demand
      WHERE NOT d.product.id IN [c IN covered | c.id]
      | {id: d.product.id, name: d.product.name}] AS uncovered,
     reduce(cost = 0.0, c IN covered |
       cost + coalesce(c.referencePrice, 0) * c.quantity
     ) AS coveredCost

RETURN s.id AS supplierId,
       s.legalName AS supplierName,
       s.rating AS rating,
       size(covered) AS coveredCount,
       totalProducts,
       round(100.0 * size(covered) / totalProducts, 1) AS coveragePercent,
       covered, uncovered,
       round(coveredCost, 2) AS estimatedCoveredCost,
       size([c IN covered WHERE c.referencePrice IS NULL]) AS priceMissingCount,
       maxLeadTimeDays

ORDER BY coveragePercent DESC,
         maxLeadTimeDays ASC,
         rating DESC,
         estimatedCoveredCost ASC,
         supplierName ASC;
