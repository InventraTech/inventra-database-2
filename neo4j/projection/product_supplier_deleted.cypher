// Evento PRODUCT_SUPPLIER_DELETED: o vínculo produto ↔ fornecedor saiu de tb_product_supplier.
// A aresta SUPPLIES é apagada; os nós continuam (desativar é active=false, não exclusão física).
// A reconciliação usa este mesmo comando para excluir SUPPLIES órfão.
// Parâmetros: $supplierId, $productId
MATCH (:Supplier {id: $supplierId})-[rel:SUPPLIES]->(:Product {id: $productId})
DELETE rel;
