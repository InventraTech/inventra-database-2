-- Valida a hierarquia de categorias da V019: árvore (vw_category_tree), subárvore
-- (fn_category_descendants), soma do estoque pela árvore (vw_category_stock_rollup) e as travas
-- contra autorreferência, ciclo e exclusão de categoria com filhas.
-- Roda numa transação desfeita no fim: não deixa dado no banco.
-- Uso: psql -v ON_ERROR_STOP=1 -f check_category_hierarchy.sql

BEGIN;

DO $$
DECLARE
    v_root INTEGER;
    v_mid INTEGER;
    v_leaf INTEGER;
    v_other_root INTEGER;
    v_unit INTEGER;
    v_kitchen INTEGER;
    v_product INTEGER;
    v_level INTEGER;
    v_path TEXT;
    v_root_name TEXT;
    v_is_leaf BOOLEAN;
    v_count INTEGER;
    v_value DECIMAL(14,3);
    v_failed BOOLEAN;
BEGIN

    -- Árvore: Teste Raiz > Teste Meio > Teste Folha, e uma segunda raiz solta
    INSERT INTO tb_category (name) VALUES ('Teste Raiz') RETURNING id_category INTO v_root;
    INSERT INTO tb_category (name, id_parent_category) VALUES ('Teste Meio', v_root) RETURNING id_category INTO v_mid;
    INSERT INTO tb_category (name, id_parent_category) VALUES ('Teste Folha', v_mid) RETURNING id_category INTO v_leaf;
    INSERT INTO tb_category (name) VALUES ('Teste Outra Raiz') RETURNING id_category INTO v_other_root;

    -- vw_category_tree: nível, caminho, raiz e folha
    SELECT category_level, category_path, root_category_name, is_leaf
    INTO v_level, v_path, v_root_name, v_is_leaf
    FROM vw_category_tree WHERE id_category = v_leaf;
    IF v_level <> 3 OR v_path <> 'Teste Raiz > Teste Meio > Teste Folha'
       OR v_root_name <> 'Teste Raiz' OR NOT v_is_leaf THEN
        RAISE EXCEPTION 'vw_category_tree: folha deveria ter nível 3, caminho completo e raiz Teste Raiz; veio %, %, %, %',
            v_level, v_path, v_root_name, v_is_leaf;
    END IF;

    SELECT is_leaf INTO v_is_leaf FROM vw_category_tree WHERE id_category = v_root;
    IF v_is_leaf THEN
        RAISE EXCEPTION 'vw_category_tree: categoria com filhas não pode ser folha';
    END IF;

    -- fn_category_descendants: a raiz devolve ela, o meio e a folha (não a outra raiz)
    SELECT COUNT(*) INTO v_count FROM fn_category_descendants(v_root);
    IF v_count <> 3 THEN
        RAISE EXCEPTION 'fn_category_descendants: raiz deveria ter 3 nós (ela + 2), veio %', v_count;
    END IF;

    SELECT relative_level INTO v_level FROM fn_category_descendants(v_root) WHERE id_descendant = v_leaf;
    IF v_level <> 2 THEN
        RAISE EXCEPTION 'fn_category_descendants: folha deveria estar 2 níveis abaixo da raiz, veio %', v_level;
    END IF;

    -- vw_category_stock_rollup: estoque na folha aparece somado na raiz
    INSERT INTO tb_measurement_unit (symbol, description) VALUES ('cth', 'Unidade do teste') RETURNING id_unit INTO v_unit;
    INSERT INTO tb_kitchen (name, code) VALUES ('Cozinha Teste Categoria', 'CTH1') RETURNING id_kitchen INTO v_kitchen;
    INSERT INTO tb_product (name, id_unit, id_category) VALUES ('Produto Teste Categoria', v_unit, v_leaf) RETURNING id_product INTO v_product;
    INSERT INTO tb_stock_batch (id_product, id_kitchen, batch_number, initial_quantity, current_quantity, unit_price, entry_date, expiration_date)
    VALUES (v_product, v_kitchen, 'CTH-L1', 10, 10, 2.5, CURRENT_DATE, CURRENT_DATE + 30);

    SELECT subtree_value, subcategory_count INTO v_value, v_count
    FROM vw_category_stock_rollup WHERE id_category = v_root;
    IF v_value <> 25 OR v_count <> 2 THEN
        RAISE EXCEPTION 'vw_category_stock_rollup: raiz deveria somar 25 em valor e ter 2 subcategorias, veio % e %', v_value, v_count;
    END IF;

    SELECT direct_value INTO v_value FROM vw_category_stock_rollup WHERE id_category = v_root;
    IF v_value <> 0 THEN
        RAISE EXCEPTION 'vw_category_stock_rollup: raiz não tem produto direto, direct_value deveria ser 0, veio %', v_value;
    END IF;

    -- Autorreferência -> recusada (o trigger BEFORE barra antes do CHECK; o CHECK cobre o resto)
    v_failed := false;
    BEGIN
        UPDATE tb_category SET id_parent_category = v_root WHERE id_category = v_root;
    EXCEPTION WHEN check_violation OR raise_exception THEN
        v_failed := true;
    END;
    IF NOT v_failed THEN
        RAISE EXCEPTION 'categoria mãe de si mesma deveria ser recusada';
    END IF;

    -- Ciclo (raiz abaixo da própria folha) -> recusado pelo trigger
    v_failed := false;
    BEGIN
        UPDATE tb_category SET id_parent_category = v_leaf WHERE id_category = v_root;
    EXCEPTION WHEN raise_exception THEN
        v_failed := true;
    END;
    IF NOT v_failed THEN
        RAISE EXCEPTION 'ciclo na hierarquia de categorias deveria ser recusado';
    END IF;

    -- Apagar categoria com filhas -> recusado pela FK (RESTRICT)
    v_failed := false;
    BEGIN
        DELETE FROM tb_category WHERE id_category = v_mid;
    EXCEPTION WHEN foreign_key_violation THEN
        v_failed := true;
    END;
    IF NOT v_failed THEN
        RAISE EXCEPTION 'apagar categoria com subcategorias deveria ser recusado';
    END IF;

    -- Mover uma subárvore para outra raiz continua permitido
    UPDATE tb_category SET id_parent_category = v_other_root WHERE id_category = v_mid;
    SELECT category_path INTO v_path FROM vw_category_tree WHERE id_category = v_leaf;
    IF v_path <> 'Teste Outra Raiz > Teste Meio > Teste Folha' THEN
        RAISE EXCEPTION 'mover subárvore: caminho deveria refletir a nova raiz, veio %', v_path;
    END IF;

    RAISE NOTICE 'V019: árvore, subárvore e soma pela árvore corretas; autorreferência, ciclo e exclusão com filhas recusados.';

END;
$$;

ROLLBACK;
