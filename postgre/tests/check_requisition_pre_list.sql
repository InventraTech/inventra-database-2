-- Valida a V021: tb_requisition.id_pre_list liga a compra à pré-lista de origem, e o banco recusa
-- uma segunda requisição ativa da mesma pré-lista. Cancelada ou recusada a primeira, a pré-lista
-- pode ser convertida de novo; requisições sem pré-lista não são afetadas. Só PURCHASE aponta
-- para pré-lista, e da cozinha dela (pré-lista sem cozinha aceita qualquer uma).
-- Roda numa transação desfeita no fim: não deixa dado no banco.
-- Uso: psql -v ON_ERROR_STOP=1 -f check_requisition_pre_list.sql

BEGIN;

DO $$
DECLARE
    v_kitchen INTEGER;
    v_other_kitchen INTEGER;
    v_legacy_list INTEGER;
    v_user UUID := '00000000-0000-0000-0000-0000000000a1';
    v_list INTEGER;
    v_other_list INTEGER;
    v_first INTEGER;
    v_count INTEGER;
    v_failed BOOLEAN;
    v_described BOOLEAN;
BEGIN

    INSERT INTO tb_kitchen (name, code) VALUES ('Cozinha Teste Pré-lista', 'PLQ1') RETURNING id_kitchen INTO v_kitchen;
    INSERT INTO tb_profile (access_type) VALUES ('pre_lista_teste') ON CONFLICT DO NOTHING;
    INSERT INTO tb_user (id_user, name, email, id_profile, id_kitchen)
    SELECT v_user, 'Teste Pré-lista', 'prelista@teste.com', p.id_profile, v_kitchen
    FROM tb_profile p WHERE p.access_type = 'pre_lista_teste';

    INSERT INTO tb_pre_list (list_date, id_kitchen) VALUES (CURRENT_DATE, v_kitchen) RETURNING id_pre_list INTO v_list;
    INSERT INTO tb_pre_list (list_date, id_kitchen) VALUES (CURRENT_DATE, v_kitchen) RETURNING id_pre_list INTO v_other_list;

    -- compra sem pré-lista continua valendo: id_pre_list é opcional e várias podem ficar nulas
    INSERT INTO tb_requisition (requisition_type, origin, id_kitchen, id_requester_user)
    VALUES ('PURCHASE', 'MOBILE_APP', v_kitchen, v_user), ('PURCHASE', 'MOBILE_APP', v_kitchen, v_user);
    SELECT COUNT(*) INTO v_count FROM tb_requisition WHERE id_kitchen = v_kitchen AND id_pre_list IS NULL;
    IF v_count <> 2 THEN
        RAISE EXCEPTION 'requisições sem pré-lista deveriam ser aceitas (id_pre_list nulo), vieram %', v_count;
    END IF;

    -- primeira conversão da pré-lista
    INSERT INTO tb_requisition (requisition_type, origin, id_kitchen, id_requester_user, id_pre_list)
    VALUES ('PURCHASE', 'Pré-lista 28/10', v_kitchen, v_user, v_list) RETURNING id_requisition INTO v_first;

    -- segunda requisição ativa da mesma pré-lista: o banco recusa
    v_failed := FALSE;
    BEGIN
        INSERT INTO tb_requisition (requisition_type, origin, id_kitchen, id_requester_user, id_pre_list)
        VALUES ('PURCHASE', 'Pré-lista 28/10', v_kitchen, v_user, v_list);
    EXCEPTION WHEN unique_violation THEN
        v_failed := TRUE;
    END;
    IF NOT v_failed THEN
        RAISE EXCEPTION 'uq_requisition_prelist_active deveria recusar a segunda requisição ativa da mesma pré-lista';
    END IF;

    -- outra pré-lista, mesmo dia e mesma origem: independente da primeira
    INSERT INTO tb_requisition (requisition_type, origin, id_kitchen, id_requester_user, id_pre_list)
    VALUES ('PURCHASE', 'Pré-lista 28/10', v_kitchen, v_user, v_other_list);

    -- em análise e aprovada ainda contam como "usada"
    UPDATE tb_requisition SET status = 'UNDER_REVIEW' WHERE id_requisition = v_first;
    v_failed := FALSE;
    BEGIN
        INSERT INTO tb_requisition (requisition_type, origin, id_kitchen, id_requester_user, id_pre_list)
        VALUES ('PURCHASE', 'Pré-lista 28/10', v_kitchen, v_user, v_list);
    EXCEPTION WHEN unique_violation THEN
        v_failed := TRUE;
    END;
    IF NOT v_failed THEN
        RAISE EXCEPTION 'requisição em análise deveria manter a pré-lista usada';
    END IF;

    -- cancelada: a pré-lista volta a ficar disponível e o histórico da tentativa fica
    UPDATE tb_requisition SET status = 'CANCELLED' WHERE id_requisition = v_first;
    INSERT INTO tb_requisition (requisition_type, origin, id_kitchen, id_requester_user, id_pre_list)
    VALUES ('PURCHASE', 'Pré-lista 28/10', v_kitchen, v_user, v_list);
    SELECT COUNT(*) INTO v_count FROM tb_requisition WHERE id_pre_list = v_list;
    IF v_count <> 2 THEN
        RAISE EXCEPTION 'a requisição cancelada deveria continuar no histórico (2 linhas da pré-lista), vieram %', v_count;
    END IF;

    -- recusada também libera
    UPDATE tb_requisition SET status = 'REJECTED' WHERE id_pre_list = v_other_list;
    INSERT INTO tb_requisition (requisition_type, origin, id_kitchen, id_requester_user, id_pre_list)
    VALUES ('PURCHASE', 'Pré-lista 28/10', v_kitchen, v_user, v_other_list);

    -- a FK recusa pré-lista que não existe
    v_failed := FALSE;
    BEGIN
        INSERT INTO tb_requisition (requisition_type, origin, id_kitchen, id_requester_user, id_pre_list)
        VALUES ('PURCHASE', 'Pré-lista 28/10', v_kitchen, v_user, -1);
    EXCEPTION WHEN foreign_key_violation THEN
        v_failed := TRUE;
    END;
    IF NOT v_failed THEN
        RAISE EXCEPTION 'fk_requisition_prelist deveria recusar id_pre_list inexistente';
    END IF;

    -- só compra aponta para pré-lista
    v_failed := FALSE;
    BEGIN
        INSERT INTO tb_requisition (requisition_type, origin, id_kitchen, id_requester_user, id_pre_list)
        VALUES ('TRANSFER', 'Pré-lista 28/10', v_kitchen, v_user, v_other_list);
    EXCEPTION WHEN check_violation THEN
        v_failed := TRUE;
    END;
    IF NOT v_failed THEN
        RAISE EXCEPTION 'ck_requisition_prelist_purchase deveria recusar requisição que não é PURCHASE com pré-lista';
    END IF;

    -- compra de outra cozinha não pode apontar para a pré-lista desta cozinha (INSERT nem UPDATE)
    INSERT INTO tb_kitchen (name, code) VALUES ('Cozinha Teste Pré-lista 2', 'PLQ2') RETURNING id_kitchen INTO v_other_kitchen;
    UPDATE tb_requisition SET status = 'CANCELLED' WHERE id_pre_list = v_other_list;
    v_failed := FALSE;
    BEGIN
        INSERT INTO tb_requisition (requisition_type, origin, id_kitchen, id_requester_user, id_pre_list)
        VALUES ('PURCHASE', 'Pré-lista 28/10', v_other_kitchen, v_user, v_other_list);
    EXCEPTION WHEN raise_exception THEN
        v_failed := TRUE;
    END;
    IF NOT v_failed THEN
        RAISE EXCEPTION 'trg_requisition_prelist_consistency deveria recusar compra de outra cozinha';
    END IF;

    v_failed := FALSE;
    BEGIN
        UPDATE tb_requisition SET id_kitchen = v_other_kitchen WHERE id_pre_list = v_list AND status = 'DRAFT';
    EXCEPTION WHEN raise_exception THEN
        v_failed := TRUE;
    END;
    IF NOT v_failed THEN
        RAISE EXCEPTION 'trg_requisition_prelist_consistency deveria recusar mover a compra para outra cozinha';
    END IF;

    -- pré-lista sem cozinha (importada antes da V018) vira compra de qualquer cozinha
    INSERT INTO tb_pre_list (list_date) VALUES (CURRENT_DATE) RETURNING id_pre_list INTO v_legacy_list;
    INSERT INTO tb_requisition (requisition_type, origin, id_kitchen, id_requester_user, id_pre_list)
    VALUES ('PURCHASE', 'Pré-lista 28/10', v_other_kitchen, v_user, v_legacy_list);

    -- catálogo: a coluna está descrita
    SELECT (c.description IS NOT NULL AND c.description <> '') INTO v_described
    FROM tb_catalog_column c
    JOIN tb_catalog_table t ON t.id_catalog_table = c.id_catalog_table
    WHERE t.table_name = 'tb_requisition' AND c.column_name = 'id_pre_list';
    IF v_described IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'tb_requisition.id_pre_list deveria estar descrita no catálogo de dados';
    END IF;

    RAISE NOTICE 'V021: id_pre_list opcional, segunda requisição ativa recusada, cancelada e recusada liberam a pré-lista, só PURCHASE, mesma cozinha, FK e catálogo corretos.';

END;
$$;

ROLLBACK;
