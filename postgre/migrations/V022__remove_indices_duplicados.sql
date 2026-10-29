-- ---------------------------------------------------
-- LIMPEZA: ÍNDICES DUPLICADOS OU COBERTOS POR OUTRO
-- ---------------------------------------------------
-- Índice que repete outro só paga escrita (INSERT/UPDATE/DELETE mantêm os dois) e ocupa espaço,
-- sem ganho de leitura.
--
-- Duplicam o índice criado pela constraint UNIQUE da própria coluna:
--   idx_user_email           (tb_user.email)
--   idx_product_barcode      (tb_product.barcode)
--
-- São prefixo exato de outro índice (a leitura usa o maior):
--   idx_parameter_product         (id_product)                 -> PK (id_product, id_kitchen)
--   idx_productsupplier_product   (id_product)                 -> PK (id_product, id_supplier) e
--                                                                  idx_productsupplier_product_price
--   idx_batch_kitchen             (id_kitchen)                 -> idx_batch_kitchen_status_expiration
--   idx_requisition_status        (status)                     -> idx_requisition_status_created_at

DROP INDEX IF EXISTS idx_user_email;

DROP INDEX IF EXISTS idx_product_barcode;

DROP INDEX IF EXISTS idx_parameter_product;

DROP INDEX IF EXISTS idx_productsupplier_product;

DROP INDEX IF EXISTS idx_batch_kitchen;

DROP INDEX IF EXISTS idx_requisition_status;
