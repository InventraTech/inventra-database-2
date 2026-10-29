-- ---------------------------------------------------
-- REQUISITION: PRÉ-LISTA DE ORIGEM (id_pre_list)
-- ---------------------------------------------------
-- A compra gerada a partir de uma pré-lista passa a apontar para ela. Antes, o app identificava a
-- conversão pelo texto "Pré-lista dd/MM" em tb_requisition.origin, e isso falhava: a mesma pré-lista
-- podia virar duas compras (cada comprador só enxerga as próprias requisições) e duas pré-listas do
-- mesmo dia geravam a mesma origem.
-- Uma pré-lista está USADA quando existe requisição com id_pre_list igual ao id dela e status
-- diferente de CANCELLED e REJECTED. Cancelada ou recusada a compra, a pré-lista volta a ficar
-- disponível; as requisições canceladas não são apagadas, então o histórico de tentativas fica.
-- Só compra (PURCHASE) aponta para pré-lista, e da mesma cozinha da pré-lista (a pré-lista sem
-- cozinha, importada antes da V018, pode virar compra de qualquer cozinha).
-- Opcional: as requisições que já existem, e as que não vieram de pré-lista, ficam com id_pre_list nulo.

-- ---------------------------------------------------
-- COLUMN
-- ---------------------------------------------------

ALTER TABLE tb_requisition
ADD COLUMN IF NOT EXISTS id_pre_list INTEGER;

-- ---------------------------------------------------
-- CONSTRAINTS
-- ---------------------------------------------------

DO $$
BEGIN
	IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_requisition_prelist') THEN
		ALTER TABLE tb_requisition
		ADD CONSTRAINT fk_requisition_prelist
		FOREIGN KEY (id_pre_list) REFERENCES tb_pre_list (id_pre_list)
		ON UPDATE NO ACTION ON DELETE NO ACTION;
	END IF;

	IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_requisition_prelist_purchase') THEN
		ALTER TABLE tb_requisition
		ADD CONSTRAINT ck_requisition_prelist_purchase
		CHECK (id_pre_list IS NULL OR requisition_type = 'PURCHASE');
	END IF;
END;
$$;

-- ---------------------------------------------------
-- INDEX CREATION
-- ---------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_requisition_prelist
ON tb_requisition (id_pre_list);

-- Trava de concorrência: no máximo uma requisição ativa por pré-lista. A API já confere antes de
-- converter, mas dois compradores podem tocar ao mesmo tempo; aqui o banco recusa a segunda.
CREATE UNIQUE INDEX IF NOT EXISTS uq_requisition_prelist_active
ON tb_requisition (id_pre_list)
WHERE id_pre_list IS NOT NULL AND status NOT IN ('CANCELLED', 'REJECTED');

-- ---------------------------------------------------
-- FUNCTION + TRIGGER
-- ---------------------------------------------------

-- Compra com pré-lista: a cozinha é a da pré-lista. Pré-lista sem cozinha aceita qualquer uma.
CREATE OR REPLACE FUNCTION fn_requisition_prelist_consistency()
RETURNS TRIGGER
LANGUAGE plpgsql
AS
$$
DECLARE
    v_id_kitchen INTEGER;
BEGIN

    IF NEW.id_pre_list IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT id_kitchen
    INTO v_id_kitchen
    FROM tb_pre_list
    WHERE id_pre_list = NEW.id_pre_list;

    -- pré-lista inexistente: a FK fk_requisition_prelist recusa com a mensagem dela
    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    IF v_id_kitchen IS NOT NULL AND v_id_kitchen <> NEW.id_kitchen THEN
        RAISE EXCEPTION
            'A pré-lista % é da cozinha % e não pode virar compra da cozinha %.',
            NEW.id_pre_list, v_id_kitchen, NEW.id_kitchen;
    END IF;

    RETURN NEW;

END;
$$;

-- só nas colunas da regra: mudar o status (aprovar, cancelar) não paga o custo da consulta
DROP TRIGGER IF EXISTS trg_requisition_prelist_consistency
ON tb_requisition;

CREATE TRIGGER trg_requisition_prelist_consistency
BEFORE INSERT OR UPDATE OF id_pre_list, id_kitchen
ON tb_requisition
FOR EACH ROW
EXECUTE FUNCTION fn_requisition_prelist_consistency();

-- ---------------------------------------------------
-- DATA CATALOG
-- ---------------------------------------------------

INSERT INTO tb_catalog_table (table_name, domain, description, business_rules, id_access_level, data_owner)
SELECT v.table_name, v.domain, v.description, v.business_rules, al.id_access_level, v.data_owner
FROM (VALUES
	('tb_requisition', 'TRANSACTION',
	 'Requisições de compra, transferência ou consumo.',
	 'Fluxo DRAFT -> UNDER_REVIEW -> APPROVED/REJECTED; CANCELLED a partir de DRAFT, UNDER_REVIEW ou APPROVED (estorna o estoque). Compra gerada de uma pré-lista aponta para ela (id_pre_list): só PURCHASE, da cozinha da pré-lista (trg_requisition_prelist_consistency) e no máximo uma ativa por pré-lista. Alterações auditadas em tb_log_requisition.',
	 'INTERNAL', 'Operações'),
	('tb_pre_list', 'TRANSACTION',
	 'Pré-listas de compra: cabeçalho com a data da lista e a cozinha.',
	 'Uma pré-lista tem N itens (1:N) e pertence a uma cozinha (opcional). É intenção de compra: não mexe em estoque. Vira uma requisição de compra pela API (tb_requisition.id_pre_list) e está "usada" enquanto essa requisição não for CANCELLED nem REJECTED. A integração RPA grava aqui as listas do banco do 1º ano e usa id_source para não importar a mesma lista duas vezes.',
	 'INTERNAL', 'Compras')
) AS v(table_name, domain, description, business_rules, access_code, data_owner)
JOIN tb_catalog_access_level al ON al.code = v.access_code
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
	('origin', 'Canal ou origem da requisição (ex.: MOBILE_APP, SYSTEM, "Pré-lista dd/MM").', 'Texto livre, sem CHECK. Só descreve: a pré-lista de origem é identificada por id_pre_list, nunca por este texto.', false),
	('id_pre_list', 'Pré-lista que originou a compra.', 'Opcional (FK fk_requisition_prelist). Nulo nas requisições que não vieram de pré-lista. Só em PURCHASE (ck_requisition_prelist_purchase) e na cozinha da pré-lista, quando ela tem cozinha (trg_requisition_prelist_consistency). A pré-lista está usada quando há requisição com status diferente de CANCELLED e REJECTED; uq_requisition_prelist_active permite no máximo uma. Cancelada ou recusada a compra, a pré-lista volta a ficar disponível.', false)
) AS v(column_name, description, business_rule, is_personal_data)
JOIN tb_catalog_table t ON t.table_name = 'tb_requisition'
ON CONFLICT (id_catalog_table, column_name) DO UPDATE
SET description = EXCLUDED.description,
    business_rule = EXCLUDED.business_rule,
    id_access_level = EXCLUDED.id_access_level,
    is_personal_data = EXCLUDED.is_personal_data,
    updated_at = CURRENT_TIMESTAMP;

CALL sp_sync_data_catalog();
