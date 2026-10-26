// Seção 07 de neo4j/docs/COBERTURA_FORNECEDORES.md — traversal principal, versão executável.
// Mesma lógica de cobertura_fornecedores.cypher (transcrição literal do PDF); a única mudança é
// levar o produto para uma variável (`d.product AS p`) antes do MATCH, porque o Cypher não aceita
// uma expressão de propriedade como node pattern. Validada no Neo4j 5 com o seed da seção 11.
// Parâmetros: $requisitionId, $kitchenId

MATCH (r:Requisition {id: $requisitionId, kitchenId: $kitchenId})
MATCH (r)-[req:REQUESTS]->(p:Product)
WITH r,
     collect({product: p, request: req}) AS demand,
     count(DISTINCT p) AS totalProducts

UNWIND demand AS d
WITH demand, totalProducts, d.product AS p, d.request AS req
MATCH (s:Supplier)-[sp:SUPPLIES]->(p)
WHERE s.active = true AND p.active = true

WITH demand, totalProducts, s,
     collect(DISTINCT {
        id: p.id,
        name: p.name,
        quantity: req.quantity,
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
