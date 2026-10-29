-- =====================================================
-- VERIFICAÇÃO DAS REDUNDÂNCIAS CONTROLADAS
-- =====================================================
-- O modelo está em 3FN, com 5 redundâncias controladas (NORMALIZATION.md, seção 5).
-- Cada consulta abaixo procura linhas em que a redundância perdeu a consistência.
-- R1 e R4 são garantidas por trigger desde a V012; as consultas continuam como prova.
-- Resultado esperado: 0 em todas as linhas de "inconsistentes".
-- Só leitura: pode rodar direto no banco do Aiven (psql ou pgAdmin).

-- ---------------------------------------------------
-- R1. tb_inventory_count.divergence = physical_quantity - registered_quantity
-- ---------------------------------------------------

SELECT
    'R1 divergence calculada' AS check_name,
    COUNT(*) AS total,
    COUNT(*) FILTER (
        WHERE divergence IS DISTINCT FROM physical_quantity - registered_quantity
    ) AS inconsistentes
FROM tb_inventory_count

UNION ALL

-- ---------------------------------------------------
-- R2. tb_stock_batch.current_quantity = saldo da última movimentação do lote
--     (só lotes com movimentação; lote sem nenhuma ainda está com o saldo da entrada)
-- ---------------------------------------------------

SELECT
    'R2 saldo do lote x última movimentação',
    COUNT(*),
    COUNT(*) FILTER (WHERE sb.current_quantity <> last_mov.balance_after)
FROM tb_stock_batch sb
JOIN (
    SELECT DISTINCT ON (id_batch) id_batch, balance_after
    FROM tb_stock_movement
    ORDER BY id_batch, created_at DESC, id_movement DESC
) last_mov ON last_mov.id_batch = sb.id_batch

UNION ALL

-- ---------------------------------------------------
-- R3. tb_stock_movement.balance_after encadeado: saldo anterior + quantidade
--     (ENTRY soma, WRITE_OFF subtrai, ADJUSTMENT soma com sinal)
-- ---------------------------------------------------

SELECT
    'R3 balance_after encadeado',
    COUNT(*),
    COUNT(*) FILTER (
        WHERE previous_balance IS NOT NULL
          AND balance_after <> previous_balance
              + CASE type WHEN 'WRITE_OFF' THEN -quantity ELSE quantity END
    )
FROM (
    SELECT
        type,
        quantity,
        balance_after,
        LAG(balance_after) OVER (
            PARTITION BY id_batch
            ORDER BY created_at, id_movement
        ) AS previous_balance
    FROM tb_stock_movement
) chain

UNION ALL

-- ---------------------------------------------------
-- R4. tb_alert com lote: produto e cozinha do alerta = produto e cozinha do lote
-- ---------------------------------------------------

SELECT
    'R4 alerta x lote (produto e cozinha)',
    COUNT(*),
    COUNT(*) FILTER (
        WHERE a.id_product IS DISTINCT FROM sb.id_product
           OR a.id_kitchen <> sb.id_kitchen
    )
FROM tb_alert a
JOIN tb_stock_batch sb ON sb.id_batch = a.id_batch

UNION ALL

-- ---------------------------------------------------
-- R5. Leitura de alerta em dois modelos: is_read (antigo) e tb_alert_read (por pessoa).
--     Não é erro ter os dois; a consulta mostra quantos alertas usam só o modelo antigo.
-- ---------------------------------------------------

SELECT
    'R5 alertas lidos só pelo is_read (informativo)',
    COUNT(*),
    COUNT(*) FILTER (
        WHERE a.is_read
          AND NOT EXISTS (SELECT 1 FROM tb_alert_read ar WHERE ar.id_alert = a.id_alert)
    )
FROM tb_alert a

UNION ALL

-- ---------------------------------------------------
-- Status derivado: lote ativo nunca fica com saldo zero (fn_update_batch_status)
-- ---------------------------------------------------

SELECT
    'status: lote ACTIVE com saldo zero',
    COUNT(*),
    COUNT(*) FILTER (WHERE status = 'ACTIVE' AND current_quantity = 0)
FROM tb_stock_batch;

-- =====================================================
-- DEPENDÊNCIAS QUE NÃO EXISTEM (prova empírica)
-- =====================================================
-- Uma dependência funcional X -> Y só existe se cada X tiver um único Y. As consultas
-- abaixo mostram, nos dados reais, casos em que X se repete com Y diferente: se houver
-- linhas, a dependência não existe e não há o que extrair para outra tabela.

-- cidade -> UF? (cidades homônimas em UFs diferentes)
SELECT city, COUNT(DISTINCT state) AS ufs
FROM tb_kitchen
WHERE city IS NOT NULL
GROUP BY city
HAVING COUNT(DISTINCT state) > 1;

-- marca -> categoria? (a mesma marca em categorias diferentes)
SELECT brand, COUNT(DISTINCT id_category) AS categorias
FROM tb_product
WHERE brand IS NOT NULL
GROUP BY brand
HAVING COUNT(DISTINCT id_category) > 1
ORDER BY categorias DESC
LIMIT 10;
