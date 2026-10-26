// Evento PRODUCT_UPDATED: nome ou active mudou em tb_product.
// A especificação pede que desativar produto atualize active; este evento cobre o caso em que o produto muda
// sem que nenhuma requisição seja reprojetada. Produto inativo vira lacuna para todos os fornecedores.
// Parâmetros: $productId, $name, $active
MERGE (p:Product {id: $productId})
SET p.name = $name, p.active = $active;
