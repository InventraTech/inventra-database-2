// Evento REQUISITION_UPSERTED / ITEM_UPSERTED: upsert de uma requisição e seus itens (seção 05).
// Fonte: tb_requisition + tb_requisition_item (+ nome e active de tb_product).
// Parâmetros:
//   $requisition = {id, kitchenId, type, status}
//   $items       = [{itemId, productId, productName, productActive, quantity, estimatedPrice, note}]
//                  lista COMPLETA de itens da requisição no PostgreSQL
// Idempotente: MERGE pelas chaves relacionais; reprocessar o mesmo evento não cria nó nem aresta.

MERGE (r:Requisition {id: $requisition.id})
SET r.kitchenId = $requisition.kitchenId,
    r.type = $requisition.type,
    r.status = $requisition.status,
    r.updatedAt = datetime()

// Item que saiu da requisição no PostgreSQL também sai do grafo (reconciliação de ITEM_DELETED perdido)
WITH r
OPTIONAL MATCH (r)-[old:REQUESTS]->()
WHERE NOT old.itemId IN [i IN $items | i.itemId]
DELETE old

WITH DISTINCT r
UNWIND $items AS item
MERGE (p:Product {id: item.productId})
SET p.name = item.productName, p.active = item.productActive
MERGE (r)-[rel:REQUESTS {itemId: item.itemId}]->(p)
SET rel.quantity = item.quantity,
    rel.estimatedPrice = item.estimatedPrice,
    rel.note = item.note,
    rel.updatedAt = datetime();
