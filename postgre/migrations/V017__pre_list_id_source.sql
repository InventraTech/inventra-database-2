-- ---------------------------------------------------
-- PRE-LIST: ORIGEM DA LISTA (id_source)
-- ---------------------------------------------------
-- A integração RPA importa todo dia as pré-listas do banco do 1º ano e precisa saber quais já entraram
-- para não importar a mesma lista duas vezes. id_source guarda o id que a lista tinha no 1º ano.
-- Nulo nas listas criadas direto no Inventra; único nas importadas. Mesmo padrão de tb_user.firebase_uid
-- (UNIQUE em coluna opcional: o banco aceita vários nulos).

-- ---------------------------------------------------
-- COLUMN
-- ---------------------------------------------------

ALTER TABLE tb_pre_list
ADD COLUMN IF NOT EXISTS id_source INTEGER;

-- ---------------------------------------------------
-- UNIQUE CONSTRAINTS
-- ---------------------------------------------------

DO $$
BEGIN
	IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_prelist_id_source') THEN
		ALTER TABLE tb_pre_list
		ADD CONSTRAINT uq_prelist_id_source
		UNIQUE (id_source);
	END IF;
END;
$$;

-- ---------------------------------------------------
-- DATA CATALOG
-- ---------------------------------------------------

INSERT INTO tb_catalog_table (table_name, domain, description, business_rules, id_access_level, data_owner)
SELECT
	'tb_pre_list', 'TRANSACTION',
	'Pré-listas de compra: cabeçalho com a data da lista.',
	'Uma pré-lista tem N itens (1:N). É intenção de compra: não mexe em estoque nem em requisições. A integração RPA grava aqui as listas do banco do 1º ano e usa id_source para não importar a mesma lista duas vezes.',
	al.id_access_level, 'Compras'
FROM tb_catalog_access_level al
WHERE al.code = 'INTERNAL'
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
	('id_source', 'Id da pré-lista no banco do 1º ano (origem da integração RPA).', 'Único (uq_prelist_id_source). Nulo nas listas criadas direto no Inventra; o RPA usa o valor para não importar a mesma lista duas vezes.', false)
) AS v(column_name, description, business_rule, is_personal_data)
JOIN tb_catalog_table t ON t.table_name = 'tb_pre_list'
ON CONFLICT (id_catalog_table, column_name) DO UPDATE
SET description = EXCLUDED.description,
    business_rule = EXCLUDED.business_rule,
    id_access_level = EXCLUDED.id_access_level,
    is_personal_data = EXCLUDED.is_personal_data,
    updated_at = CURRENT_TIMESTAMP;

CALL sp_sync_data_catalog();
