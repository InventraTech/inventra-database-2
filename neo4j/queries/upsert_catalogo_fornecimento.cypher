// Seção 05 de neo4j/docs/COBERTURA_FORNECEDORES.md — upsert do catálogo de fornecimento.
// Parâmetros: $supplierId, $legalName, $rating, $active,
//             $productId, $supplierCode, $referencePrice, $leadTimeDays

MERGE (s:Supplier {id: $supplierId})
SET s.legalName = $legalName, s.rating = $rating, s.active = $active
MERGE (p:Product {id: $productId})
MERGE (s)-[rel:SUPPLIES]->(p)
SET rel.supplierCode = $supplierCode,
    rel.referencePrice = $referencePrice,
    rel.leadTimeDays = $leadTimeDays,
    rel.updatedAt = datetime();

// Remoções também são eventos: ao excluir RequisitionItem ou desvincular ProductSupplier,
// a projeção deve apagar a aresta correspondente. Desativar produto/fornecedor atualiza
// `active`; exclusão física do nó só ocorre quando a política relacional realmente o remover.
