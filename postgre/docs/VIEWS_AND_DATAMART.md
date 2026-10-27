# Views, Data Mart e Analytics

Camada de consulta do banco, criada em `migrations/V004__views.sql` e `migrations/V005__etl_analytics.sql`. As migrations `V008` e `V009` ajustam o filtro de algumas views, sem mudar as colunas.

## Views operacionais (`vw_*`)

Arquivo: `views/create_views.sql`. Dão suporte às telas do app e a consultas prontas para a IA, sem cruzar tabela por tabela.

| View | Para que serve |
|------|----------------|
| `vw_stock_batch_detail` | Lote a lote, com dias até vencer e status (EXPIRED/CRITICAL/WARNING/OK) |
| `vw_product_stock_position` | Quantidade total por produto/cozinha vs. mínimo/máximo |
| `vw_daily_expiration_summary` | Vencimentos agrupados por dia (Dashboard) |
| `vw_active_alerts` | Alertas que ninguém leu ainda, ordenados por severidade |
| `vw_stock_value_by_category` | Estoque somado por categoria (Dashboard) |
| `vw_requisition_summary` / `vw_requisition_pending` | Requisições com totais (sem rascunhos), e as pendentes |
| `vw_stock_movement_log` | Entradas/saídas reconstruídas do log de auditoria |
| `vw_inventory_count_divergence` | Diferença entre contagem registrada e física |
| `vw_kitchen_daily_stock_movement` | Movimentação diária com total acumulado (gráfico de linha) |
| `vw_product_requisition_ranking` | Produtos mais requisitados, por cozinha (sem rascunhos) |
| `vw_product_supplier_catalog` | Fornecedores por produto, ordenados por preço |
| `vw_kitchen_dashboard_kpi` | KPIs resumidos por cozinha, numa linha só |
| `vw_products_below_minimum` / `vw_batches_needing_attention` | Filtros prontos de "abaixo do mínimo" e "precisa de atenção" |
| `vw_supplier_profile` | Resumo por fornecedor (nº de produtos, preço médio, prazo médio) |
| `vw_monthly_waste_proxy_kpi` | Estimativa de desperdício. **Proxy/hipótese, não é fórmula aprovada:** o banco ainda não registra o motivo de uma baixa de estoque (consumo normal vs. descarte) |

## Data Mart / Star Schema (`dim_*` / `fact_*`)

Arquivo: `views/datamart/create_datamart_views.sql`. Atende o requisito de Modelagem Dimensional para BI. É um **star schema virtual**: dimensões e fatos são views sobre as tabelas normalizadas, não tabelas físicas duplicadas.

```mermaid
flowchart LR
    dp[dim_product] --- fsm
    dk[dim_kitchen] --- fsm
    dd[dim_date] --- fsm
    fsm[("fact_stock_movement")]
    dp --- fri[("fact_requisition_item")]
    dk --- fri
    dd --- fri
    dp --- fic[("fact_inventory_count")]
    dk --- fic
    dd --- fic
    ds[dim_supplier] --- fsm
    ds --- fri
    dc[dim_category] -.-|category_name| dp
```

Na categoria o modelo vira **snowflake**: `dim_product` aponta para `dim_category` (linha pontilhada), que traz a hierarquia da `V019` (mãe, raiz, nível e caminho, calculados por CTE recursiva em `vw_category_tree`). A ligação é por `category_name`, único em `tb_category`. `dim_product` não ganhou `id_category` porque a `V004` a recria com `CREATE OR REPLACE VIEW`, que não aceita coluna a menos ([convenção](ARCHITECTURE.md#convenções)). Produto sem categoria aparece como `UNCATEGORIZED` e não casa com nenhuma linha de `dim_category`.

| Tipo | View | Grão |
|------|------|------|
| Dimensão | `dim_product` | uma linha por produto |
| Dimensão (snowflake) | `dim_category` | uma linha por categoria, com mãe, raiz, `category_level`, `category_path` e `is_leaf` |
| Dimensão | `dim_kitchen` | uma linha por cozinha |
| Dimensão | `dim_supplier` | uma linha por fornecedor |
| Dimensão | `dim_date` | uma linha por dia (2023–2030) |
| Fato | `fact_stock_movement` | uma linha por movimentação de estoque |
| Fato | `fact_requisition_item` | uma linha por item de requisição |
| Fato | `fact_inventory_count` | uma linha por contagem de inventário |

Uma ferramenta de BI (Power BI, Metabase etc.) conectada nessas 8 views monta o relacionamento fato↔dimensão sozinha, pelas colunas de chave (`id_product`, `id_kitchen`, `date_key`); `dim_product`↔`dim_category` liga por `category_name`.

## Views analíticas (CTEs + Window Functions)

Arquivo: `views/analytics/create_etl_views.sql`. CTEs organizam os cálculos e Window Functions entram por cima.

| View | Para que serve |
|------|----------------|
| `vw_category_stock_balance` | Estoque atual vs. mínimo por categoria (2 CTEs), com ranking de risco (`RANK()`) da categoria mais apertada para a mais tranquila |
| `vw_category_monthly_requisition_trend` | Demanda requisitada por categoria, mês a mês, com total acumulado (`SUM() OVER`) |
| `vw_product_expiration_urgency` | Lotes ativos por produto/cozinha ordenados por validade, com acumulado de quantidade em risco (`SUM() OVER`) e ranking de urgência por cozinha (`RANK()`) |
| `vw_category_stock_rollup` | Estoque ativo (quantidade e valor) de cada categoria **somado com o das subcategorias**: 2 CTEs sobre `vw_category_tree` (CTE recursiva), ranking de valor por nível da árvore (`RANK() OVER (PARTITION BY category_level)`) e participação no nível (`SUM() OVER`) |

`vw_category_tree` (em `views/create_views.sql`) é a árvore de categorias montada com `WITH RECURSIVE`, base de `vw_category_stock_rollup` e `dim_category`. Veja [`ARCHITECTURE.md`](ARCHITECTURE.md#cte-recursiva-na-hierarquia-de-categorias).

As views de DAU (`vw_dau`, `vw_dau_by_kitchen`), também com CTEs e Window Functions (`LAG`, `LEAD`, média móvel, soma acumulada e `RANK()`), estão em `views/monitoring/` e documentadas em [`MONITORING.md`](MONITORING.md).

Rollbacks isolados em `views/rollback/`, `views/datamart/rollback/`, `views/analytics/rollback/` e `views/monitoring/rollback/`, além do `drop_everything.sql`.
