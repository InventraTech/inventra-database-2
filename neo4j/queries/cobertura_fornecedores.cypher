// Seção 07 de neo4j/docs/COBERTURA_FORNECEDORES.md — traversal principal.
// Entra pela requisição autorizada, materializa sua demanda, encontra fornecedores conectados
// a pelo menos um produto e calcula cobertura e lacunas por fornecedor.
// Parâmetros: $requisitionId, $kitchenId
//
// ATENÇÃO: transcrito literalmente da especificação (PDF, página 8) e REJEITADO pelo Neo4j 5:
// `->(d.product)` não é um node pattern válido. Use cobertura_fornecedores_validada.cypher.
// Mantido só para conferência com o PDF.

MATCH (r:Requisition {id: $requisitionId, kitchenId: $kitchenId})
MATCH (r)-[req:REQUESTS]->(p:Product)
WITH r,
     collect({product: p, request: req}) AS demand,
     count(DISTINCT p) AS totalProducts

UNWIND demand AS d
MATCH (s:Supplier)-[sp:SUPPLIES]->(d.product)
WHERE s.active = true AND d.product.active = true

WITH r, demand, totalProducts, s,
     collect(DISTINCT {
        id: d.product.id,
        name: d.product.name,
        quantity: d.request.quantity,
        referencePrice: sp.referencePrice,
        leadTimeDays: sp.leadTimeDays
     }) AS covered,
     max(sp.leadTimeDays) AS maxLeadTimeDays

WITH r, totalProducts, s, covered, maxLeadTimeDays,
     [d IN demand
      WHERE NOT d.product.id IN [c IN covered | c.id]
      | {id: d.product.id, name: d.product.name}] AS uncovered,
     reduce(cost = 0.0, c IN covered |
        cost + coalesce(c.referencePrice, 0) * c.quantity
     ) AS estimatedCoveredCost

RETURN s.id AS supplierId,
       s.legalName AS supplierName,
       s.rating AS rating,
       size(covered) AS coveredCount,
       totalProducts,
       round(100.0 * size(covered) / totalProducts, 1) AS coveragePercent,
       covered, uncovered, estimatedCoveredCost, maxLeadTimeDays

ORDER BY coveragePercent DESC,
         maxLeadTimeDays ASC,
         rating DESC,
         estimatedCoveredCost ASC,
         supplierName ASC;
