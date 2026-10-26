// Evento SUPPLIER_UPDATED: cadastro do fornecedor mudou em tb_supplier.
// Desativar fornecedor é active=false; ele some do ranking (filtro s.active = true) sem perder as arestas.
// Parâmetros: $supplierId, $legalName, $rating, $active
MERGE (s:Supplier {id: $supplierId})
SET s.legalName = $legalName, s.rating = $rating, s.active = $active;
