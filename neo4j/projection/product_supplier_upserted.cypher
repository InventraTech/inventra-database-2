// Evento PRODUCT_SUPPLIER_UPSERTED: upsert do catálogo de fornecimento (seção 05).
// Fonte: tb_product_supplier (+ legal_name, rating e active de tb_supplier).
// Preço e prazo ficam na aresta: pertencem à capacidade do fornecedor atender o produto, não aos nós.
// CNPJ, e-mail e WhatsApp não entram no grafo: a decisão não precisa deles.
// Parâmetros: $supplierId, $legalName, $rating, $active, $productId, $supplierCode, $referencePrice, $leadTimeDays
MERGE (s:Supplier {id: $supplierId})
SET s.legalName = $legalName, s.rating = $rating, s.active = $active
MERGE (p:Product {id: $productId})
MERGE (s)-[rel:SUPPLIES]->(p)
SET rel.supplierCode = $supplierCode,
    rel.referencePrice = $referencePrice,
    rel.leadTimeDays = $leadTimeDays,
    rel.updatedAt = datetime();
