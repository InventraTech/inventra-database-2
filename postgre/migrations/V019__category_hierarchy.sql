-- ---------------------------------------------------
-- CATEGORY: HIERARQUIA (id_parent_category)
-- ---------------------------------------------------
-- A categoria passa a ter categoria-mãe (autorrelacionamento 1:N), formando uma árvore:
-- ex.: Hortifrúti > Categoria Vegetal. Nula = categoria raiz. A árvore é percorrida com
-- CTE recursiva (WITH RECURSIVE) na trava anti-ciclo, em fn_category_descendants, em
-- vw_category_tree e, por ela, no Data Mart (dim_category, snowflake) e em vw_category_stock_rollup.
-- Produto pode apontar para qualquer nível; quem já lê tb_category sem a coluna nova não muda.

-- ---------------------------------------------------
-- COLUMN
-- ---------------------------------------------------

ALTER TABLE tb_category
ADD COLUMN IF NOT EXISTS id_parent_category INTEGER;

-- ---------------------------------------------------
-- CONSTRAINTS
-- ---------------------------------------------------

DO $$
BEGIN
	IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_category_parent') THEN
		ALTER TABLE tb_category
		ADD CONSTRAINT fk_category_parent
		FOREIGN KEY (id_parent_category) REFERENCES tb_category (id_category)
		ON UPDATE NO ACTION ON DELETE RESTRICT;
	END IF;

	IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_category_not_self_parent') THEN
		ALTER TABLE tb_category
		ADD CONSTRAINT ck_category_not_self_parent
		CHECK (id_parent_category <> id_category);
	END IF;
END;
$$;

-- ---------------------------------------------------
-- INDEX CREATION
-- ---------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_category_parent
ON tb_category (id_parent_category);

-- ---------------------------------------------------
-- FUNCTIONS
-- ---------------------------------------------------

-- Sobe pelos ancestrais da nova mãe: se a própria categoria aparece, a troca fecharia um ciclo.
-- UNION (e não UNION ALL) para a recursão terminar mesmo se houver um ciclo antigo no banco.
CREATE OR REPLACE FUNCTION fn_check_category_cycle()
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
CREATE OR REPLACE FUNCTION fn_category_descendants(p_id_category INTEGER)
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

-- ---------------------------------------------------
-- TRIGGERS
-- ---------------------------------------------------

DROP TRIGGER IF EXISTS trg_category_no_cycle
ON tb_category;

CREATE TRIGGER trg_category_no_cycle
BEFORE INSERT OR UPDATE OF id_parent_category
ON tb_category
FOR EACH ROW
EXECUTE FUNCTION fn_check_category_cycle();

-- ---------------------------------------------------
-- VIEWS
-- ---------------------------------------------------

-- Árvore de categorias a partir das raízes: nível, caminho legível e ids do caminho (path_ids).
-- path_ids também barra a recursão se um ciclo existir.
CREATE OR REPLACE VIEW vw_category_tree AS
WITH RECURSIVE tree AS (
    SELECT
        c.id_category,
        c.name,
        c.id_parent_category,
        c.id_category AS id_root_category,
        1 AS category_level,
        c.name::TEXT AS category_path,
        ARRAY[c.id_category] AS path_ids
    FROM tb_category c
    WHERE c.id_parent_category IS NULL

    UNION ALL

    SELECT
        c.id_category,
        c.name,
        c.id_parent_category,
        t.id_root_category,
        t.category_level + 1,
        t.category_path || ' > ' || c.name,
        t.path_ids || c.id_category
    FROM tb_category c
    JOIN tree t ON c.id_parent_category = t.id_category
    WHERE NOT c.id_category = ANY(t.path_ids)
)
SELECT
    t.id_category,
    t.name AS category_name,
    t.id_parent_category,
    parent.name AS parent_category_name,
    t.id_root_category,
    root.name AS root_category_name,
    t.category_level,
    t.category_path,
    t.path_ids,
    NOT EXISTS (
        SELECT 1 FROM tb_category child
        WHERE child.id_parent_category = t.id_category
    ) AS is_leaf
FROM tree t
JOIN tb_category root ON root.id_category = t.id_root_category
LEFT JOIN tb_category parent ON parent.id_category = t.id_parent_category;

-- Estoque ativo de cada categoria somado com o das subcategorias (subtree), com ranking
-- e participação dentro do mesmo nível da árvore.
CREATE OR REPLACE VIEW vw_category_stock_rollup AS
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

-- ---------------------------------------------------
-- DATA MART (SNOWFLAKE)
-- ---------------------------------------------------

-- Dimensão da categoria normalizada à parte (snowflake): dim_product.category_name -> dim_category.
-- A ligação é pelo nome (UNIQUE em tb_category) porque dim_product fica como está: a V004 a recria
-- com CREATE OR REPLACE e não aceitaria colunas a menos se a V019 a alargasse.
CREATE OR REPLACE VIEW dim_category AS
SELECT
    t.id_category,
    t.category_name,
    t.id_parent_category,
    t.parent_category_name,
    t.root_category_name,
    t.category_level,
    t.category_path,
    t.is_leaf
FROM vw_category_tree t;

-- ---------------------------------------------------
-- DATA CATALOG
-- ---------------------------------------------------

INSERT INTO tb_catalog_table (table_name, domain, description, business_rules, id_access_level, data_owner)
SELECT
	'tb_category', 'MASTER_DATA',
	'Categorias de produto em árvore (ex.: Hortifrúti > Categoria Vegetal).',
	'Nome único. Categoria-mãe opcional (nula = raiz); a hierarquia não pode ter ciclo (trg_category_no_cycle) e categoria com subcategorias não pode ser apagada. Percorrida com CTE recursiva em vw_category_tree.',
	al.id_access_level, 'Compras'
FROM tb_catalog_access_level al
WHERE al.code = 'PUBLIC'
ON CONFLICT (table_name) DO UPDATE
SET domain = EXCLUDED.domain,
    description = EXCLUDED.description,
    business_rules = EXCLUDED.business_rules,
    id_access_level = EXCLUDED.id_access_level,
    data_owner = EXCLUDED.data_owner,
    updated_at = CURRENT_TIMESTAMP;

INSERT INTO tb_catalog_column (id_catalog_table, column_name, description, business_rule, id_access_level, is_personal_data)
SELECT t.id_catalog_table, 'id_parent_category', 'Categoria-mãe na hierarquia.',
	'Opcional (FK fk_category_parent, ON DELETE RESTRICT). Nula = categoria raiz. Não pode ser a própria categoria (ck_category_not_self_parent) nem uma descendente dela (trg_category_no_cycle).',
	NULL, false
FROM tb_catalog_table t
WHERE t.table_name = 'tb_category'
ON CONFLICT (id_catalog_table, column_name) DO UPDATE
SET description = EXCLUDED.description,
    business_rule = EXCLUDED.business_rule,
    id_access_level = EXCLUDED.id_access_level,
    is_personal_data = EXCLUDED.is_personal_data,
    updated_at = CURRENT_TIMESTAMP;

CALL sp_sync_data_catalog();
