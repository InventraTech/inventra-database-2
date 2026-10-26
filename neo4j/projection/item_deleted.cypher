// Evento ITEM_DELETED: um RequisitionItem foi excluído no PostgreSQL; a aresta REQUESTS correspondente sai.
// Remoções também são eventos (seção 05). O nó Product continua: outras requisições e fornecedores apontam para ele.
// Parâmetros: $requisitionId, $itemId (tb_requisition_item.id_requisition_item)
MATCH (:Requisition {id: $requisitionId})-[rel:REQUESTS {itemId: $itemId}]->(:Product)
DELETE rel;
