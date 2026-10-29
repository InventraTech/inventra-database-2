-- ---------------------------------------------------
-- SUPPLIER: PHOTO
-- ---------------------------------------------------
-- Foto do fornecedor (logo ou fachada), no mesmo padrão de tb_product.photo_url e tb_user.photo_url:
-- o arquivo fica no Cloudinary (public_id inventra/suppliers/{id_supplier}) e o banco guarda só a URL.
-- Nula = sem foto (o app mostra as iniciais da razão social).

ALTER TABLE tb_supplier
ADD COLUMN IF NOT EXISTS photo_url VARCHAR(255);

-- ---------------------------------------------------
-- DATA CATALOG
-- ---------------------------------------------------

INSERT INTO tb_catalog_column (id_catalog_table, column_name, description, business_rule, id_access_level, is_personal_data)
SELECT t.id_catalog_table, 'photo_url', 'URL da foto do fornecedor.',
	'Nula quando o fornecedor não tem foto. secure_url do Cloudinary com a versão (public_id inventra/suppliers/{id_supplier}), trocada a cada envio.',
	NULL, false
FROM tb_catalog_table t
WHERE t.table_name = 'tb_supplier'
ON CONFLICT (id_catalog_table, column_name) DO UPDATE
SET description = EXCLUDED.description,
    business_rule = EXCLUDED.business_rule,
    id_access_level = EXCLUDED.id_access_level,
    is_personal_data = EXCLUDED.is_personal_data,
    updated_at = CURRENT_TIMESTAMP;

CALL sp_sync_data_catalog();
