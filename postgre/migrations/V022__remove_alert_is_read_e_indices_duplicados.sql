-- ---------------------------------------------------
-- LIMPEZA: tb_alert.is_read E ÍNDICES DUPLICADOS
-- ---------------------------------------------------
-- 1) tb_alert.is_read era a leitura do alerta inteiro (modelo antigo). Desde a V008 a leitura é
--    por pessoa, em tb_alert_read, e a API só grava nela: nenhum caminho do banco ou da API marca
--    is_read como true. A coluna, o índice idx_alert_is_read e o filtro "is_read = false" das
--    rotinas e views eram só carga. "Alerta aberto" continua sendo o que ninguém leu ainda
--    (nenhuma linha em tb_alert_read).
--    Antes de remover, o que algum cliente antigo tenha deixado com is_read = true vira leitura
--    de cada destinatário em tb_alert_read (usuários da cozinha do alerta, respeitando
--    id_user e id_target_profile), para o alerta continuar fechado. Alerta cuja cozinha não tem
--    destinatário não gera linha e passa a contar como aberto.
-- 2) Índices que repetem outro: idx_user_email e idx_product_barcode duplicam o índice das
--    constraints UNIQUE de email e barcode; os outros cinco são prefixo exato de um índice
--    composto ou da PK e só pagam escrita (a leitura usa o índice maior).

-- ---------------------------------------------------
-- BACKFILL DA LEITURA ANTIGA
-- ---------------------------------------------------

DO
$$
BEGIN

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = 'tb_alert'
          AND column_name = 'is_read'
    ) THEN

        INSERT INTO tb_alert_read (id_alert, id_user, read_at)
        SELECT a.id_alert, u.id_user, CURRENT_TIMESTAMP
        FROM tb_alert a
        JOIN tb_user u ON u.id_kitchen = a.id_kitchen
        WHERE a.is_read
          AND (a.id_user IS NULL OR u.id_user = a.id_user)
          AND (a.id_target_profile IS NULL OR u.id_profile = a.id_target_profile)
        ON CONFLICT (id_alert, id_user) DO NOTHING;

    END IF;

END;
$$;

-- ---------------------------------------------------
-- ROTINAS E VIEWS SEM is_read
-- ---------------------------------------------------

CREATE OR REPLACE FUNCTION fn_stock_alert()
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

CREATE OR REPLACE FUNCTION fn_expiration_alert()
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

CREATE OR REPLACE PROCEDURE sp_expire_batches()
LANGUAGE plpgsql
AS
$$
BEGIN

    CREATE TEMP TABLE tmp_expired_batches ON COMMIT DROP AS
    SELECT id_batch, id_product, id_kitchen
    FROM tb_stock_batch
    WHERE status = 'ACTIVE'
      AND expiration_date < CURRENT_DATE;

    UPDATE tb_stock_batch sb
    SET status = 'EXPIRED'
    FROM tmp_expired_batches e
    WHERE sb.id_batch = e.id_batch;

    INSERT INTO tb_alert (type, severity, id_batch, id_product, id_kitchen, message)
    SELECT 'EXPIRATION', 'CRITICAL', e.id_batch, e.id_product, e.id_kitchen,
           'Lote vencido. Verifique a validade do produto.'
    FROM tmp_expired_batches e
    WHERE NOT EXISTS (
        SELECT 1 FROM tb_alert a
        WHERE a.id_batch = e.id_batch
          AND a.type = 'EXPIRATION'
          AND NOT EXISTS (
              SELECT 1 FROM tb_alert_read ar
              WHERE ar.id_alert = a.id_alert
          )
    );

    INSERT INTO tb_alert (type, severity, id_product, id_kitchen, message)
    SELECT DISTINCT 'STOCK', 'HIGH', p.id_product, p.id_kitchen, 'Produto abaixo do estoque mínimo.'
    FROM tmp_expired_batches e
    JOIN tb_product_kitchen_parameter p
      ON p.id_product = e.id_product AND p.id_kitchen = e.id_kitchen
    WHERE p.min_stock > (
        SELECT COALESCE(SUM(sb.current_quantity), 0)
        FROM tb_stock_batch sb
        WHERE sb.id_product = p.id_product
          AND sb.id_kitchen = p.id_kitchen
          AND sb.status = 'ACTIVE'
          AND (sb.expiration_date IS NULL OR sb.expiration_date >= CURRENT_DATE)
    )
      AND NOT EXISTS (
        SELECT 1 FROM tb_alert a
        WHERE a.id_product = p.id_product
          AND a.id_kitchen = p.id_kitchen
          AND a.type = 'STOCK'
          AND NOT EXISTS (
              SELECT 1 FROM tb_alert_read ar
              WHERE ar.id_alert = a.id_alert
          )
    );

    DROP TABLE tmp_expired_batches;

END;
$$;

CREATE OR REPLACE PROCEDURE sp_alert_expiring_batches(
    p_days INTEGER DEFAULT 3
)
LANGUAGE plpgsql
AS
$$
BEGIN

    IF p_days IS NULL OR p_days < 0 THEN
        RAISE EXCEPTION
            'A quantidade de dias para o aviso de validade não pode ser negativa.';
    END IF;

    INSERT INTO tb_alert (type, severity, id_batch, id_product, id_kitchen, message)
    SELECT
        'EXPIRING',
        CASE
            WHEN sb.expiration_date <= CURRENT_DATE + 1 THEN 'HIGH'
            ELSE 'MEDIUM'
        END,
        sb.id_batch,
        sb.id_product,
        sb.id_kitchen,
        'Lote ' || sb.batch_number ||
        CASE
            WHEN sb.expiration_date = CURRENT_DATE THEN ' vence hoje'
            WHEN sb.expiration_date = CURRENT_DATE + 1 THEN ' vence amanhã'
            ELSE ' vence em ' || (sb.expiration_date - CURRENT_DATE) || ' dias'
        END ||
        ' (' || TO_CHAR(sb.expiration_date, 'DD/MM') || ').'
    FROM tb_stock_batch sb
    WHERE sb.status = 'ACTIVE'
      AND sb.expiration_date BETWEEN CURRENT_DATE AND CURRENT_DATE + p_days
      AND NOT EXISTS (
        SELECT 1 FROM tb_alert a
        WHERE a.id_batch = sb.id_batch
          AND a.type = 'EXPIRING'
          AND NOT EXISTS (
              SELECT 1 FROM tb_alert_read ar
              WHERE ar.id_alert = a.id_alert
          )
    );

END;
$$;

CREATE OR REPLACE VIEW vw_active_alerts AS
SELECT
    a.id_alert,
    a.type,
    a.severity,
    CASE a.severity
        WHEN 'CRITICAL' THEN 1
        WHEN 'HIGH' THEN 2
        WHEN 'MEDIUM' THEN 3
        WHEN 'LOW' THEN 4
        ELSE 5
    END AS severity_rank,
    a.id_kitchen,
    k.name AS kitchen_name,
    a.id_product,
    p.name AS product_name,
    a.id_batch,
    sb.batch_number,
    sb.expiration_date,
    a.message,
    a.created_at,
    (CURRENT_TIMESTAMP - a.created_at) AS alert_age
FROM tb_alert a
JOIN tb_kitchen k ON k.id_kitchen = a.id_kitchen
LEFT JOIN tb_product p ON p.id_product = a.id_product
LEFT JOIN tb_stock_batch sb ON sb.id_batch = a.id_batch
WHERE NOT EXISTS (
    SELECT 1 FROM tb_alert_read ar
    WHERE ar.id_alert = a.id_alert
);

CREATE OR REPLACE VIEW vw_kitchen_dashboard_kpi AS
SELECT
    k.id_kitchen,
    k.name AS kitchen_name,
    COALESCE(stock.active_batch_count, 0) AS active_batch_count,
    COALESCE(stock.distinct_product_count, 0) AS distinct_product_count,
    COALESCE(stock.total_stock_value, 0) AS total_stock_value,
    COALESCE(stock.expired_batch_count, 0) AS expired_batch_count,
    COALESCE(stock.critical_batch_count, 0) AS critical_batch_count,
    COALESCE(alerts.active_alert_count, 0) AS active_alert_count,
    COALESCE(reqs.pending_requisition_count, 0) AS pending_requisition_count
FROM tb_kitchen k
LEFT JOIN (
    SELECT
        id_kitchen,
        COUNT(*) AS active_batch_count,
        COUNT(DISTINCT id_product) AS distinct_product_count,
        SUM(current_quantity * COALESCE(unit_price, 0)) AS total_stock_value,
        COUNT(*) FILTER (WHERE expiration_date < CURRENT_DATE) AS expired_batch_count,
        COUNT(*) FILTER (
            WHERE expiration_date >= CURRENT_DATE
              AND expiration_date <= CURRENT_DATE + 3
        ) AS critical_batch_count
    FROM tb_stock_batch
    WHERE status = 'ACTIVE'
    GROUP BY id_kitchen
) stock ON stock.id_kitchen = k.id_kitchen
LEFT JOIN (
    SELECT a.id_kitchen, COUNT(*) AS active_alert_count
    FROM tb_alert a
    WHERE NOT EXISTS (
        SELECT 1 FROM tb_alert_read ar
        WHERE ar.id_alert = a.id_alert
    )
    GROUP BY a.id_kitchen
) alerts ON alerts.id_kitchen = k.id_kitchen
LEFT JOIN (
    SELECT id_kitchen, COUNT(*) AS pending_requisition_count
    FROM tb_requisition
    WHERE status = 'UNDER_REVIEW'
    GROUP BY id_kitchen
) reqs ON reqs.id_kitchen = k.id_kitchen;

-- ---------------------------------------------------
-- REMOÇÃO DA COLUNA E DOS ÍNDICES
-- ---------------------------------------------------

DROP INDEX IF EXISTS idx_alert_is_read;

ALTER TABLE tb_alert
DROP COLUMN IF EXISTS is_read;

DROP INDEX IF EXISTS idx_user_email;

DROP INDEX IF EXISTS idx_product_barcode;

DROP INDEX IF EXISTS idx_productsupplier_product;

DROP INDEX IF EXISTS idx_parameter_product;

DROP INDEX IF EXISTS idx_batch_kitchen;

DROP INDEX IF EXISTS idx_requisition_status;

-- ---------------------------------------------------
-- DATA CATALOG
-- ---------------------------------------------------

DELETE FROM tb_catalog_column c
USING tb_catalog_table t
WHERE t.id_catalog_table = c.id_catalog_table
  AND t.table_name = 'tb_alert'
  AND c.column_name = 'is_read';

CALL sp_sync_data_catalog();
