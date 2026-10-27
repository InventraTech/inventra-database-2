-- ---------------------------------------------------
-- ETL / ANALYTICS VIEW CREATION
-- ---------------------------------------------------

CREATE VIEW vw_category_stock_balance AS
WITH estoque_atual AS (
    SELECT p.id_category, SUM(sb.current_quantity) AS total_atual
    FROM tb_stock_batch sb
    JOIN tb_product p ON p.id_product = sb.id_product
    WHERE sb.status = 'ACTIVE'
    GROUP BY p.id_category
),
estoque_minimo AS (
    SELECT p.id_category, SUM(pkp.min_stock) AS total_minimo
    FROM tb_product_kitchen_parameter pkp
    JOIN tb_product p ON p.id_product = pkp.id_product
    GROUP BY p.id_category
)
SELECT
    c.id_category,
    c.name AS category_name,
    COALESCE(ea.total_atual, 0) AS total_atual,
    COALESCE(em.total_minimo, 0) AS total_minimo,
    COALESCE(ea.total_atual, 0) - COALESCE(em.total_minimo, 0) AS folga,
    RANK() OVER (
        ORDER BY (COALESCE(ea.total_atual, 0) - COALESCE(em.total_minimo, 0)) ASC
    ) AS risk_rank
FROM tb_category c
LEFT JOIN estoque_atual ea ON ea.id_category = c.id_category
LEFT JOIN estoque_minimo em ON em.id_category = c.id_category;

CREATE VIEW vw_category_monthly_requisition_trend AS
WITH monthly_demand AS (
    SELECT
        p.id_category,
        DATE_TRUNC('month', r.created_at)::DATE AS reference_month,
        SUM(ri.quantity) AS quantity_requested
    FROM tb_requisition r
    JOIN tb_requisition_item ri ON ri.id_requisition = r.id_requisition
    JOIN tb_product p ON p.id_product = ri.id_product
    WHERE r.status IN ('UNDER_REVIEW', 'APPROVED')
    GROUP BY p.id_category, DATE_TRUNC('month', r.created_at)::DATE
)
SELECT
    md.id_category,
    c.name AS category_name,
    md.reference_month,
    md.quantity_requested,
    SUM(md.quantity_requested) OVER (
        PARTITION BY md.id_category
        ORDER BY md.reference_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_quantity_requested
FROM monthly_demand md
JOIN tb_category c ON c.id_category = md.id_category
ORDER BY md.id_category, md.reference_month;

CREATE VIEW vw_product_expiration_urgency AS
WITH batch_risk AS (
    SELECT
        sb.id_batch,
        sb.id_product,
        p.name AS product_name,
        sb.id_kitchen,
        sb.current_quantity,
        sb.expiration_date,
        (sb.expiration_date - CURRENT_DATE) AS days_to_expire
    FROM tb_stock_batch sb
    JOIN tb_product p ON p.id_product = sb.id_product
    WHERE sb.status = 'ACTIVE'
      AND sb.expiration_date IS NOT NULL
),
product_next_expiration AS (
    SELECT id_product, id_kitchen, MIN(expiration_date) AS next_expiration
    FROM batch_risk
    GROUP BY id_product, id_kitchen
)
SELECT
    br.id_kitchen,
    br.id_product,
    br.product_name,
    br.id_batch,
    br.current_quantity,
    br.expiration_date,
    br.days_to_expire,
    SUM(br.current_quantity) OVER (
        PARTITION BY br.id_product, br.id_kitchen
        ORDER BY br.expiration_date, br.id_batch
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_quantity_at_risk,
    RANK() OVER (
        PARTITION BY br.id_kitchen
        ORDER BY pne.next_expiration ASC
    ) AS urgency_rank
FROM batch_risk br
JOIN product_next_expiration pne
    ON pne.id_product = br.id_product AND pne.id_kitchen = br.id_kitchen
ORDER BY br.id_kitchen, urgency_rank, br.expiration_date;

-- Estoque ativo de cada categoria somado com o das subcategorias (subtree), com ranking
-- e participação dentro do mesmo nível da árvore.
CREATE VIEW vw_category_stock_rollup AS
WITH direct_stock AS (
    SELECT
        p.id_category,
        SUM(sb.current_quantity) AS quantity,
        SUM(sb.current_quantity * COALESCE(sb.unit_price, 0)) AS stock_value
    FROM tb_stock_batch sb
    JOIN tb_product p ON p.id_product = sb.id_product
    WHERE sb.status = 'ACTIVE'
      AND p.id_category IS NOT NULL
    GROUP BY p.id_category
),
subtree_stock AS (
    SELECT
        a.id_category,
        COUNT(*) - 1 AS subcategory_count,
        COALESCE(SUM(ds.quantity), 0) AS subtree_quantity,
        COALESCE(SUM(ds.stock_value), 0) AS subtree_value
    FROM vw_category_tree a
    JOIN vw_category_tree d ON a.id_category = ANY(d.path_ids)
    LEFT JOIN direct_stock ds ON ds.id_category = d.id_category
    GROUP BY a.id_category
)
SELECT
    t.id_category,
    t.category_name,
    t.id_parent_category,
    t.category_level,
    t.category_path,
    t.is_leaf,
    ss.subcategory_count,
    COALESCE(ds.quantity, 0) AS direct_quantity,
    COALESCE(ds.stock_value, 0) AS direct_value,
    ss.subtree_quantity,
    ss.subtree_value,
    RANK() OVER (
        PARTITION BY t.category_level
        ORDER BY ss.subtree_value DESC
    ) AS value_rank_in_level,
    ROUND(
        100 * ss.subtree_value
        / NULLIF(SUM(ss.subtree_value) OVER (PARTITION BY t.category_level), 0),
        2
    ) AS share_of_level_pct
FROM vw_category_tree t
JOIN subtree_stock ss ON ss.id_category = t.id_category
LEFT JOIN direct_stock ds ON ds.id_category = t.id_category;
