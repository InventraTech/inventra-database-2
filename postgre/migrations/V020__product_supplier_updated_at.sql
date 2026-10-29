-- ---------------------------------------------------
-- PRODUCT-SUPPLIER: DATA DA ÚLTIMA GRAVAÇÃO (updated_at)
-- ---------------------------------------------------
-- O vínculo produto–fornecedor não tinha data, então a lista de fornecedores de um produto
-- (GET /api/products/{id}/suppliers) vinha sem ordem e o app mostrava um fornecedor qualquer
-- como "o fornecedor do produto". A coluna guarda quando o vínculo foi gravado pela última vez,
-- e a API ordena do mais recente para o mais antigo. O INSERT recebe o padrão e todo UPDATE é
-- renovado por trg_product_supplier_updated_at, venha da API ou de qualquer outro caminho (a API
-- regrava o vínculo a cada POST, mesmo com os mesmos dados). Os vínculos que já existem ficam com
-- a data desta migration.

-- ---------------------------------------------------
-- COLUMN
-- ---------------------------------------------------

ALTER TABLE tb_product_supplier
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- ---------------------------------------------------
-- FUNCTION + TRIGGER
-- ---------------------------------------------------

-- Toda alteração do vínculo renova updated_at; um valor escrito à mão é sobrescrito.
CREATE OR REPLACE FUNCTION fn_product_supplier_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS
$$
BEGIN

    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;

END;
$$;

DROP TRIGGER IF EXISTS trg_product_supplier_updated_at
ON tb_product_supplier;

CREATE TRIGGER trg_product_supplier_updated_at
BEFORE UPDATE
ON tb_product_supplier
FOR EACH ROW
EXECUTE FUNCTION fn_product_supplier_updated_at();

-- ---------------------------------------------------
-- DATA CATALOG
-- ---------------------------------------------------

INSERT INTO tb_catalog_table (table_name, domain, description, business_rules, id_access_level, data_owner)
SELECT
	'tb_product_supplier', 'RELATIONSHIP',
	'Associativa N:N entre produto e fornecedor, com condições comerciais.',
	'PK composta (id_product, id_supplier): um fornecedor aparece uma única vez por produto. updated_at diz qual vínculo foi gravado por último (trg_product_supplier_updated_at) e define a ordem em que a API lista os fornecedores do produto.',
	al.id_access_level, 'Compras'
FROM tb_catalog_access_level al
WHERE al.code = 'RESTRICTED'
ON CONFLICT (table_name) DO UPDATE
SET domain = EXCLUDED.domain,
    description = EXCLUDED.description,
    business_rules = EXCLUDED.business_rules,
    id_access_level = EXCLUDED.id_access_level,
    data_owner = EXCLUDED.data_owner,
    updated_at = CURRENT_TIMESTAMP;

INSERT INTO tb_catalog_column (id_catalog_table, column_name, description, business_rule, id_access_level, is_personal_data)
SELECT t.id_catalog_table, v.column_name, v.description, v.business_rule, NULL, v.is_personal_data
FROM (VALUES
	('updated_at', 'Data e hora da última gravação do vínculo.', 'Padrão: momento da inserção. Todo UPDATE renova o valor (trg_product_supplier_updated_at). A API regrava o vínculo a cada POST /api/products/{id}/suppliers, mesmo quando os dados não mudam, e lista os fornecedores do mais recente para o mais antigo. Nos vínculos anteriores à V020, é a data da migration.', false)
) AS v(column_name, description, business_rule, is_personal_data)
JOIN tb_catalog_table t ON t.table_name = 'tb_product_supplier'
ON CONFLICT (id_catalog_table, column_name) DO UPDATE
SET description = EXCLUDED.description,
    business_rule = EXCLUDED.business_rule,
    id_access_level = EXCLUDED.id_access_level,
    is_personal_data = EXCLUDED.is_personal_data,
    updated_at = CURRENT_TIMESTAMP;

CALL sp_sync_data_catalog();
