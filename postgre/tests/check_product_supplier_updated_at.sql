-- Valida a V020: tb_product_supplier.updated_at é preenchido no INSERT, renovado em todo UPDATE
-- por trg_product_supplier_updated_at (mesmo quando o UPDATE tenta escrever outro valor) e ordena
-- os vínculos do mais recente para o mais antigo, a ordem de GET /api/products/{id}/suppliers.
-- Confere também que a coluna está no catálogo de dados.
-- Roda numa transação desfeita no fim: não deixa dado no banco.
-- Uso: psql -v ON_ERROR_STOP=1 -f check_product_supplier_updated_at.sql

BEGIN;

DO $$
DECLARE
    v_unit INTEGER;
    v_product INTEGER;
    v_old INTEGER;
    v_new INTEGER;
    v_first INTEGER;
    v_updated TIMESTAMP;
    v_nullable TEXT;
    v_described BOOLEAN;
BEGIN

    INSERT INTO tb_measurement_unit (symbol, description) VALUES ('psu', 'Unidade do teste') RETURNING id_unit INTO v_unit;
    INSERT INTO tb_product (name, id_unit) VALUES ('Produto Teste Fornecedor', v_unit) RETURNING id_product INTO v_product;
    INSERT INTO tb_supplier (legal_name, cnpj) VALUES ('Fornecedor Teste Antigo', '00.000.000/0001-91') RETURNING id_supplier INTO v_old;
    INSERT INTO tb_supplier (legal_name, cnpj) VALUES ('Fornecedor Teste Novo', '00.000.000/0002-72') RETURNING id_supplier INTO v_new;

    -- a coluna é obrigatória e tem padrão: o INSERT sem ela preenche com o momento da gravação
    SELECT is_nullable INTO v_nullable
    FROM information_schema.columns
    WHERE table_name = 'tb_product_supplier' AND column_name = 'updated_at';
    IF v_nullable IS DISTINCT FROM 'NO' THEN
        RAISE EXCEPTION 'tb_product_supplier.updated_at deveria ser NOT NULL, veio %', v_nullable;
    END IF;

    INSERT INTO tb_product_supplier (id_product, id_supplier, reference_price)
    VALUES (v_product, v_old, 10.00);
    SELECT updated_at INTO v_updated FROM tb_product_supplier WHERE id_product = v_product AND id_supplier = v_old;
    IF v_updated IS DISTINCT FROM CURRENT_TIMESTAMP::TIMESTAMP THEN
        RAISE EXCEPTION 'updated_at deveria receber o momento do INSERT, veio %', v_updated;
    END IF;

    -- datas antigas gravadas no INSERT (o trigger é só de UPDATE): o mais antigo há dois dias,
    -- o mais novo há um; o mais recente vem primeiro
    DELETE FROM tb_product_supplier WHERE id_product = v_product AND id_supplier = v_old;
    INSERT INTO tb_product_supplier (id_product, id_supplier, reference_price, updated_at)
    VALUES (v_product, v_old, 10.00, CURRENT_TIMESTAMP - INTERVAL '2 days'),
           (v_product, v_new, 12.50, CURRENT_TIMESTAMP - INTERVAL '1 day');
    SELECT id_supplier INTO v_first
    FROM tb_product_supplier WHERE id_product = v_product
    ORDER BY updated_at DESC, id_supplier DESC LIMIT 1;
    IF v_first <> v_new THEN
        RAISE EXCEPTION 'o vínculo mais recente deveria vir primeiro; veio o fornecedor %', v_first;
    END IF;

    -- regravar o vínculo mais antigo (mudando só o preço) renova a data e o leva para o topo
    UPDATE tb_product_supplier SET reference_price = 9.90
    WHERE id_product = v_product AND id_supplier = v_old;
    SELECT updated_at INTO v_updated FROM tb_product_supplier WHERE id_product = v_product AND id_supplier = v_old;
    IF v_updated IS DISTINCT FROM CURRENT_TIMESTAMP::TIMESTAMP THEN
        RAISE EXCEPTION 'trg_product_supplier_updated_at deveria renovar updated_at no UPDATE, veio %', v_updated;
    END IF;
    SELECT id_supplier INTO v_first
    FROM tb_product_supplier WHERE id_product = v_product
    ORDER BY updated_at DESC, id_supplier DESC LIMIT 1;
    IF v_first <> v_old THEN
        RAISE EXCEPTION 'o vínculo regravado deveria vir primeiro; veio o fornecedor %', v_first;
    END IF;

    -- um UPDATE que tenta escrever uma data antiga à mão é sobrescrito
    UPDATE tb_product_supplier SET updated_at = '2000-01-01'
    WHERE id_product = v_product AND id_supplier = v_new;
    SELECT updated_at INTO v_updated FROM tb_product_supplier WHERE id_product = v_product AND id_supplier = v_new;
    IF v_updated IS DISTINCT FROM CURRENT_TIMESTAMP::TIMESTAMP THEN
        RAISE EXCEPTION 'updated_at escrito à mão deveria ser sobrescrito pelo trigger, veio %', v_updated;
    END IF;

    -- catálogo: a coluna está descrita
    SELECT (c.description IS NOT NULL AND c.description <> '') INTO v_described
    FROM tb_catalog_column c
    JOIN tb_catalog_table t ON t.id_catalog_table = c.id_catalog_table
    WHERE t.table_name = 'tb_product_supplier' AND c.column_name = 'updated_at';
    IF v_described IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'tb_product_supplier.updated_at deveria estar descrita no catálogo de dados';
    END IF;

    RAISE NOTICE 'V020: updated_at no INSERT, renovado em todo UPDATE (inclusive o escrito à mão), vínculo mais recente primeiro e coluna no catálogo.';

END;
$$;

ROLLBACK;
