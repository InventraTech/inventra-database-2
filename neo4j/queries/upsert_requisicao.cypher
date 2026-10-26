// Seção 05 de neo4j/docs/COBERTURA_FORNECEDORES.md — upsert de uma requisição e seus itens.
// Parâmetros: $requisition {id, kitchenId, type, status}
//             $items [{itemId, productId, productName, productActive, quantity, estimatedPrice, note}]

MERGE (r:Requisition {id: $requisition.id})
SET r.kitchenId = $requisition.kitchenId,
    r.type = $requisition.type,
    r.status = $requisition.status,
    r.updatedAt = datetime();

UNWIND $items AS item
MERGE (p:Product {id: item.productId})
SET p.name = item.productName, p.active = item.productActive
MERGE (r)-[rel:REQUESTS {itemId: item.itemId}]->(p)
SET rel.quantity = item.quantity,
    rel.estimatedPrice = item.estimatedPrice,
    rel.note = item.note,
    rel.updatedAt = datetime();
