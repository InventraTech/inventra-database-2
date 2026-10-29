-- ---------------------------------------------------
-- FUNCTION CREATION
-- ---------------------------------------------------

CREATE FUNCTION fn_validate_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
AS
$$
BEGIN

    IF NEW.current_quantity < 0 THEN
        RAISE EXCEPTION
            'O saldo do lote não pode ficar negativo.';
    END IF;

    RETURN NEW;

END;
$$;

CREATE FUNCTION fn_update_batch_status()
RETURNS TRIGGER
LANGUAGE plpgsql
AS
$$
BEGIN

    IF NEW.current_quantity = 0
       AND NEW.status = 'ACTIVE' THEN

        NEW.status := 'WRITTEN_OFF';

    END IF;

    RETURN NEW;

END;
$$;

CREATE FUNCTION fn_calculate_divergence()
RETURNS TRIGGER
LANGUAGE plpgsql
AS
$$
BEGIN

    NEW.divergence :=
        NEW.physical_quantity - NEW.registered_quantity;

    RETURN NEW;

END;
$$;

CREATE FUNCTION fn_requisition_approval()
RETURNS TRIGGER
LANGUAGE plpgsql
AS
$$
BEGIN

    IF NEW.status = 'APPROVED'
       AND OLD.status IS DISTINCT FROM 'APPROVED' THEN

        NEW.approved_at := CURRENT_TIMESTAMP;

    END IF;

    RETURN NEW;

END;
$$;

CREATE FUNCTION fn_stock_alert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS
$$
DECLARE
    v_min_stock DECIMAL(12,3);
    v_total_quantity DECIMAL(12,3);
    v_existing_alert INTEGER;
BEGIN

    SELECT min_stock
    INTO v_min_stock
    FROM tb_product_kitchen_parameter
    WHERE id_product = NEW.id_product
      AND id_kitchen = NEW.id_kitchen;

    IF v_min_stock IS NULL THEN
        RETURN NEW;
    END IF;

    -- trigger AFTER: a linha alterada já aparece com o valor novo nessa soma; lote vencido não conta
    SELECT COALESCE(SUM(current_quantity), 0)
    INTO v_total_quantity
    FROM tb_stock_batch
    WHERE id_product = NEW.id_product
      AND id_kitchen = NEW.id_kitchen
      AND status = 'ACTIVE'
      AND (expiration_date IS NULL OR expiration_date >= CURRENT_DATE);

    IF v_total_quantity < v_min_stock THEN

        SELECT a.id_alert
        INTO v_existing_alert
        FROM tb_alert a
        WHERE a.id_product = NEW.id_product
          AND a.id_kitchen = NEW.id_kitchen
          AND a.type = 'STOCK'
          AND a.is_read = false
          AND NOT EXISTS (
              SELECT 1 FROM tb_alert_read ar
              WHERE ar.id_alert = a.id_alert
          )
        LIMIT 1;

        IF v_existing_alert IS NULL THEN

            INSERT INTO tb_alert
            (
                type,
                severity,
                id_batch,
                id_product,
                id_kitchen,
                message
            )
            VALUES
            (
                'STOCK',
                'HIGH',
                NEW.id_batch,
                NEW.id_product,
                NEW.id_kitchen,
                'Produto abaixo do estoque mínimo.'
            );

        END IF;

    END IF;

    RETURN NEW;

END;
$$;

CREATE FUNCTION fn_expiration_alert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS
$$
DECLARE
    v_existing_alert INTEGER;
BEGIN

    IF NEW.expiration_date IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.expiration_date < CURRENT_DATE THEN

        SELECT a.id_alert
        INTO v_existing_alert
        FROM tb_alert a
        WHERE a.id_batch = NEW.id_batch
          AND a.type = 'EXPIRATION'
          AND a.is_read = false
          AND NOT EXISTS (
              SELECT 1 FROM tb_alert_read ar
              WHERE ar.id_alert = a.id_alert
          )
        LIMIT 1;

        IF v_existing_alert IS NULL THEN

            INSERT INTO tb_alert
            (
                type,
                severity,
                id_batch,
                id_product,
                id_kitchen,
                message
            )
            VALUES
            (
                'EXPIRATION',
                'CRITICAL',
                NEW.id_batch,
                NEW.id_product,
                NEW.id_kitchen,
                'Lote vencido. Verifique a validade do produto.'
            );

        END IF;

    END IF;

    RETURN NEW;

END;
$$;

-- Alerta com lote: produto e cozinha são os do lote. Vazio é preenchido; diferente é recusado.
CREATE FUNCTION fn_alert_batch_consistency()
RETURNS TRIGGER
LANGUAGE plpgsql
AS
$$
DECLARE
    v_id_product INTEGER;
    v_id_kitchen INTEGER;
BEGIN

    IF NEW.id_batch IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT id_product, id_kitchen
    INTO v_id_product, v_id_kitchen
    FROM tb_stock_batch
    WHERE id_batch = NEW.id_batch;

    -- lote inexistente: a FK fk_alert_batch recusa com a mensagem dela
    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    NEW.id_product := COALESCE(NEW.id_product, v_id_product);
    NEW.id_kitchen := COALESCE(NEW.id_kitchen, v_id_kitchen);

    IF NEW.id_product <> v_id_product OR NEW.id_kitchen <> v_id_kitchen THEN
        RAISE EXCEPTION
            'O alerta do lote % precisa ser do produto % e da cozinha %.',
            NEW.id_batch, v_id_product, v_id_kitchen;
    END IF;

    RETURN NEW;

END;
$$;

-- Sobe pelos ancestrais da nova mãe: se a própria categoria aparece, a troca fecharia um ciclo.
-- UNION (e não UNION ALL) para a recursão terminar mesmo se houver um ciclo antigo no banco.
CREATE FUNCTION fn_check_category_cycle()
RETURNS TRIGGER
LANGUAGE plpgsql
AS
$$
BEGIN

    IF NEW.id_parent_category IS NULL THEN
        RETURN NEW;
    END IF;

    IF EXISTS (
        WITH RECURSIVE ancestors AS (
            SELECT c.id_category, c.id_parent_category
            FROM tb_category c
            WHERE c.id_category = NEW.id_parent_category

            UNION

            SELECT c.id_category, c.id_parent_category
            FROM tb_category c
            JOIN ancestors a ON c.id_category = a.id_parent_category
        )
        SELECT 1 FROM ancestors WHERE id_category = NEW.id_category
    ) THEN
        RAISE EXCEPTION
            'A categoria % não pode ficar abaixo da categoria %: isso criaria um ciclo na hierarquia.',
            NEW.id_category, NEW.id_parent_category;
    END IF;

    RETURN NEW;

END;
$$;

-- A categoria e todas as subcategorias abaixo dela (relative_level 0 = a própria).
-- Ex.: produtos de Hortifrúti, com subcategorias:
--   SELECT * FROM tb_product WHERE id_category IN (SELECT id_descendant FROM fn_category_descendants(1));
CREATE FUNCTION fn_category_descendants(p_id_category INTEGER)
RETURNS TABLE (id_descendant INTEGER, relative_level INTEGER)
LANGUAGE sql
STABLE
AS
$$
    WITH RECURSIVE subtree AS (
        SELECT c.id_category, 0 AS lvl
        FROM tb_category c
        WHERE c.id_category = p_id_category

        UNION ALL

        SELECT c.id_category, s.lvl + 1
        FROM tb_category c
        JOIN subtree s ON c.id_parent_category = s.id_category
    )
    SELECT id_category, lvl FROM subtree;
$$;

-- Toda alteração do vínculo produto–fornecedor renova updated_at; um valor escrito à mão é sobrescrito.
CREATE FUNCTION fn_product_supplier_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS
$$
BEGIN

    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;

END;
$$;
