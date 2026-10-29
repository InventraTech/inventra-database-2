# Otimização de Consultas — EXPLAIN ANALYZE

## Como essa evidência foi gerada

Medição feita direto no banco de dados real do grupo, já com a massa de dados
do MD-03 carregada (cada uma das tabelas abaixo tem mais de 5.000 linhas).
Script completo em `explain_analyze.sql`, nesta mesma pasta — cada bloco
derruba o índice (ou ainda não cria), mede o plano "antes", cria o índice e
mede o plano "depois" da mesma query.

Testamos também um candidato a mais que acabou **descartado** —
documentado no fim deste arquivo, porque mostra uma parte real do trabalho
de otimização: nem todo índice que parece razoável vale a pena criar.

---

## Consulta 1 — Histórico de movimentação de um lote específico

O que `vw_stock_movement_log` e a tela de "detalhe do lote" fazem: buscar as
linhas de auditoria de **um** lote específico.

```sql
SELECT id_log, operation, operation_date, previous_data, new_data
FROM tb_log_stock_batch
WHERE id_batch = 42000;
```

`tb_log_stock_batch` só tinha a `PRIMARY KEY (id_log)` como índice — nenhum
índice em `id_batch`, apesar de ser a coluna usada pra filtrar em praticamente
toda consulta feita nessa tabela.

### Antes (sem índice em id_batch)

```
Seq Scan on tb_log_stock_batch  (cost=414.30..740.93 rows=1 width=409) (actual time=6.736..8.419 rows=1 loops=1)
  Filter: (id_batch = (InitPlan 1).col1)
  Rows Removed by Filter: 5009
  Buffers: shared hit=531
  InitPlan 1
    ->  Limit  (cost=414.30..414.30 rows=1 width=12) (actual time=6.395..6.399 rows=1 loops=1)
          Buffers: shared hit=267
          ->  Sort  (cost=414.30..426.82 rows=5010 width=12) (actual time=6.393..6.395 rows=1 loops=1)
                Sort Key: (count(*)) DESC
                Sort Method: top-N heapsort  Memory: 25kB
                Buffers: shared hit=267
                ->  HashAggregate  (cost=339.15..389.25 rows=5010 width=12) (actual time=4.065..5.362 rows=5010 loops=1)
                      Group Key: tb_log_stock_batch_1.id_batch
                      Batches: 1  Memory Usage: 593kB
                      Buffers: shared hit=264
                      ->  Seq Scan on tb_log_stock_batch tb_log_stock_batch_1  (cost=0.00..314.10 rows=5010 width=4) (actual time=0.002..1.155 rows=5010 loops=1)
                            Buffers: shared hit=264
Planning Time: 0.267 ms
Execution Time: 8.579 ms
```

Varreu a tabela inteira pra achar 1 linha (`Rows Removed by Filter: 5009`).

### Índice criado

```sql
CREATE INDEX idx_log_stock_batch_id_batch
ON tb_log_stock_batch (id_batch);
```

### Depois (com índice em id_batch)

```
Index Scan using idx_log_stock_batch_id_batch on tb_log_stock_batch  (cost=191.92..193.94 rows=1 width=409) (actual time=2.821..2.823 rows=1 loops=1)
  Index Cond: (id_batch = (InitPlan 1).col1)
  Buffers: shared hit=4 read=15
  InitPlan 1
    ->  Limit  (cost=191.63..191.64 rows=1 width=12) (actual time=2.797..2.799 rows=1 loops=1)
          Buffers: shared hit=1 read=15
          ->  Sort  (cost=191.63..204.16 rows=5010 width=12) (actual time=2.795..2.796 rows=1 loops=1)
                Sort Key: (count(*)) DESC
                Sort Method: top-N heapsort  Memory: 25kB
                Buffers: shared hit=1 read=15
                ->  GroupAggregate  (cost=0.28..166.58 rows=5010 width=12) (actual time=0.048..2.093 rows=5010 loops=1)
                      Group Key: tb_log_stock_batch_1.id_batch
                      Buffers: shared hit=1 read=15
                      ->  Index Only Scan using idx_log_stock_batch_id_batch on tb_log_stock_batch tb_log_stock_batch_1  (cost=0.28..91.43 rows=5010 width=4)
                            Heap Fetches: 0
                            Buffers: shared hit=1 read=15
Planning Time: 0.300 ms
Execution Time: 2.863 ms
```

| Métrica | Antes | Depois |
|---|---|---|
| Plano | Seq Scan (tabela inteira) | Index Scan |
| Linhas descartadas pelo filtro | 5.009 | 0 |
| Tempo de execução | 8,579 ms | 2,863 ms |
| Ganho | — | **~3x mais rápido** |

---

## Consulta 2 — Requisições em análise, mais recentes primeiro

O que a tela de "Requisições" faz ao listar o que está pendente de revisão.

```sql
SELECT id_requisition, requisition_type, id_kitchen, reason, created_at
FROM tb_requisition
WHERE status = 'UNDER_REVIEW'
ORDER BY created_at DESC
LIMIT 20;
```

Já existiam dois índices de uma coluna só: `idx_requisition_status` e
`idx_requisition_created_at`. Como a consulta filtra por `status` **e**
ordena por `created_at` ao mesmo tempo, o índice de uma coluna só resolve
parte do trabalho.

### Antes (índices de uma coluna só)

```
Limit  (cost=0.28..2.82 rows=20 width=51) (actual time=0.040..0.190 rows=20 loops=1)
  Buffers: shared hit=58
  ->  Index Scan Backward using idx_requisition_created_at on tb_requisition  (cost=0.28..190.96 rows=1504 width=51) (actual time=0.039..0.186 rows=20 loops=1)
        Filter: ((status)::text = 'UNDER_REVIEW'::text)
        Rows Removed by Filter: 34
        Buffers: shared hit=58
Planning Time: 0.179 ms
Execution Time: 0.211 ms
```

O índice só resolveu a ordenação (`created_at`); o filtro de `status` virou
um `Filter` aplicado depois, descartando 34 linhas que não precisavam nem
ter sido lidas.

### Índice criado

```sql
CREATE INDEX idx_requisition_status_created_at
ON tb_requisition (status, created_at DESC);
```

### Depois (índice composto)

```
Limit  (cost=0.28..1.80 rows=20 width=51) (actual time=0.076..0.101 rows=20 loops=1)
  Buffers: shared hit=20 read=2
  ->  Index Scan using idx_requisition_status_created_at on tb_requisition  (cost=0.28..114.04 rows=1504 width=51) (actual time=0.074..0.098 rows=20 loops=1)
        Index Cond: ((status)::text = 'UNDER_REVIEW'::text)
        Buffers: shared hit=20 read=2
Planning Time: 0.284 ms
Execution Time: 0.125 ms
```

| Métrica | Antes | Depois |
|---|---|---|
| Plano | Index Scan Backward + Filter pós-leitura | Index Scan, sem Filter |
| Linhas descartadas depois de ler | 34 | 0 |
| Tempo de execução | 0,211 ms | 0,125 ms |
| Ganho | — | **~1,7x mais rápido** |

---

## Consulta 3 — Fornecedores de um produto, do mais barato pro mais caro

O que a tela de catálogo de fornecedores (`vw_product_supplier_catalog`) faz
ao comparar preço entre fornecedores de um mesmo produto.

```sql
SELECT id_supplier, reference_price
FROM tb_product_supplier
WHERE id_product = 15
ORDER BY reference_price ASC;
```

Já existia `idx_productsupplier_product` (só em `id_product`). Ele resolve o
filtro, mas a ordenação por preço ainda precisava de um passo de `Sort`
separado.

### Antes (índice não cobre a ordenação)

```
Sort  (cost=167.73..167.73 rows=2 width=10) (actual time=3.984..3.987 rows=6 loops=1)
  Sort Key: tb_product_supplier.reference_price
  Sort Method: quicksort  Memory: 25kB
  Buffers: shared hit=50
  ->  Index Scan using idx_productsupplier_product on tb_product_supplier  (cost=0.28..3.32 rows=2 width=10) (actual time=3.960..3.972 rows=6 loops=1)
        Index Cond: (id_product = (InitPlan 1).col1)
        Buffers: shared hit=50
Planning Time: 0.262 ms
Execution Time: 4.092 ms
```

### Índice criado

```sql
CREATE INDEX idx_productsupplier_product_price
ON tb_product_supplier (id_product, reference_price);
```

### Depois (índice já entrega os dados ordenados)

```
Index Scan using idx_productsupplier_product_price on tb_product_supplier  (cost=164.69..167.72 rows=2 width=10) (actual time=3.652..3.665 rows=6 loops=1)
  Index Cond: (id_product = (InitPlan 1).col1)
  Buffers: shared hit=48 read=2
Planning Time: 0.337 ms
Execution Time: 3.752 ms
```

| Métrica | Antes | Depois |
|---|---|---|
| Plano | Index Scan + Sort separado | Index Scan, sem Sort |
| Tempo de execução | 4,092 ms | 3,752 ms |
| Ganho | — | **~8% mais rápido** (ganho modesto — a maior parte do tempo total é de uma subconsulta auxiliar de teste, não da query em si) |

---

## Consulta 4 — Lotes precisando de atenção, por cozinha

O filtro que `vw_batches_needing_attention` e o painel de vencimentos do
Dashboard fazem: lotes de uma cozinha específica, com `status = 'ACTIVE'` e
validade vencendo no próximo mês.

```sql
SELECT id_batch, batch_number, current_quantity, expiration_date
FROM tb_stock_batch
WHERE id_kitchen = 7
  AND status = 'ACTIVE'
  AND expiration_date <= CURRENT_DATE + 30;
```

Já existiam três índices de uma coluna só (`idx_batch_kitchen`,
`idx_batch_status`, `idx_batch_expiration_date`). Pra uma consulta que
filtra as três colunas ao mesmo tempo, um índice de uma coluna só resolve
parte do filtro — o resto vira `Filter` aplicado depois de já ter buscado a
linha.

### Antes (só índices de uma coluna)

```
Index Scan using idx_batch_kitchen on tb_stock_batch  (cost=190.17..193.22 rows=1 width=27) (actual time=5.924..5.938 rows=6 loops=1)
  Index Cond: (id_kitchen = (InitPlan 1).col1)
  Filter: (((status)::text = 'ACTIVE'::text) AND (expiration_date <= (CURRENT_DATE + 30)))
  Buffers: shared hit=77
  InitPlan 1
    ->  Limit  (cost=189.89..189.89 rows=1 width=12) (actual time=5.875..5.878 rows=1 loops=1)
          Buffers: shared hit=69
          ->  Sort  (cost=189.89..196.64 rows=2702 width=12) (actual time=5.873..5.875 rows=1 loops=1)
                Sort Key: (count(*)) DESC
                Sort Method: top-N heapsort  Memory: 25kB
                Buffers: shared hit=69
                ->  HashAggregate  (cost=149.36..176.38 rows=2702 width=12) (actual time=4.366..4.789 rows=2519 loops=1)
                      Group Key: tb_stock_batch_1.id_kitchen
                      Batches: 1  Memory Usage: 369kB
                      Buffers: shared hit=69
                      ->  Seq Scan on tb_stock_batch tb_stock_batch_1  (cost=0.00..131.62 rows=3546 width=4) (actual time=0.025..3.319 rows=3546 loops=1)
                            Filter: ((status)::text = 'ACTIVE'::text)
                            Rows Removed by Filter: 1464
                            Buffers: shared hit=69
Planning Time: 0.289 ms
Execution Time: 7.664 ms
```

O índice só resolveu `id_kitchen`; `status` e `expiration_date` viraram um
`Filter` aplicado depois.

### Índice criado

```sql
CREATE INDEX idx_batch_kitchen_status_expiration
ON tb_stock_batch (id_kitchen, status, expiration_date);
```

### Depois (índice composto nas três colunas)

```
Index Scan using idx_batch_kitchen_status_expiration on tb_stock_batch  (cost=154.87..156.89 rows=1 width=27) (actual time=1.929..1.938 rows=6 loops=1)
  Index Cond: ((id_kitchen = (InitPlan 1).col1) AND ((status)::text = 'ACTIVE'::text) AND (expiration_date <= (CURRENT_DATE + 30)))
  Buffers: shared hit=9 read=22
  InitPlan 1
    ->  Limit  (cost=154.58..154.58 rows=1 width=12) (actual time=1.908..1.909 rows=1 loops=1)
          Buffers: shared hit=1 read=22
          ->  Sort  (cost=154.58..161.33 rows=2702 width=12) (actual time=1.906..1.907 rows=1 loops=1)
                Sort Key: (count(*)) DESC
                Sort Method: top-N heapsort  Memory: 25kB
                Buffers: shared hit=1 read=22
                ->  GroupAggregate  (cost=0.28..141.07 rows=2702 width=12) (actual time=0.038..1.615 rows=2519 loops=1)
                      Group Key: tb_stock_batch_1.id_kitchen
                      Buffers: shared hit=1 read=22
                      ->  Index Only Scan using idx_batch_kitchen_status_expiration on tb_stock_batch tb_stock_batch_1  (cost=0.28..96.32 rows=3546 width=4)
                            Index Cond: (status = 'ACTIVE'::text)
                            Heap Fetches: 0
                            Buffers: shared hit=1 read=22
Planning Time: 0.323 ms
Execution Time: 1.978 ms
```

As três condições viraram `Index Cond`, sem `Filter` pós-leitura.

| Métrica | Antes | Depois |
|---|---|---|
| Plano | Index Scan + Filter pós-leitura | Index Scan, sem Filter |
| Tempo de execução | 7,664 ms | 1,978 ms |
| Ganho | — | **~3,9x mais rápido** |

Essa consulta precisou de duas rodadas de teste: a primeira tentativa deu 0
linhas (a cozinha escolhida não tinha lote vencendo) e a segunda tentativa
comparou um "antes" já em cache com um "depois" ainda frio — os dois casos
foram descartados por não serem uma comparação justa. Os números acima são
da terceira rodada, com os dois lados aquecidos antes de medir (cada query
rodada 3x, só a última guardada).

---

## Candidato descartado — Itens de uma requisição

Candidato testado: abrir uma requisição e listar os itens dela.

```sql
SELECT id_requisition_item, id_product, quantity, estimated_price, note
FROM tb_requisition_item
WHERE id_requisition = 850;
```

A hipótese era a mesma da Consulta 1: `tb_requisition_item` não teria índice
em `id_requisition`, só na PK. **A hipótese estava errada** — o projeto já
tinha `idx_requisitionitem_requisition` nessa mesma coluna desde o dicionário
original (`ddl/indexes/create_indexes.sql`). O plano "antes" já usa esse
índice:

```
Index Scan using idx_requisitionitem_requisition on tb_requisition_item  (cost=168.38..171.41 rows=2 width=61) (actual time=2.517..2.533 rows=6 loops=1)
  Index Cond: (id_requisition = (InitPlan 1).col1)
  Buffers: shared hit=27
Planning Time: 0.388 ms
Execution Time: 2.586 ms
```

Criamos `idx_requisitionitem_id_requisition (id_requisition)` mesmo assim
pra comparar — e, como esperado, ele é um **índice duplicado** (mesma coluna
do que já existia):

```
Index Scan using idx_requisitionitem_id_requisition on tb_requisition_item  (cost=163.38..166.41 rows=2 width=61) (actual time=2.175..2.184 rows=6 loops=1)
  Index Cond: (id_requisition = (InitPlan 1).col1)
  Buffers: shared hit=8 read=14
Planning Time: 0.302 ms
Execution Time: 2.224 ms
```

A diferença de tempo (2,586 ms → 2,224 ms) é ruído de cache, não efeito do
índice — os dois planos são a mesma estratégia (`Index Scan` por
`id_requisition`). Manter dois índices na mesma coluna só gastaria espaço em
disco e deixaria escritas um pouco mais lentas à toa. **Ação:** o índice
`idx_requisitionitem_id_requisition` foi removido do banco
(`DROP INDEX idx_requisitionitem_id_requisition;`) e não faz parte do schema.

---

## Consulta 5 — Subárvore de uma categoria (CTE recursiva)

Consulta medida: todas as subcategorias de uma categoria raiz, o mesmo corpo de
`fn_category_descendants` (`V019`). Banco local PostgreSQL 16 com o seed
completo (5.026 categorias em 3 níveis), após `ANALYZE tb_category`.

```sql
WITH RECURSIVE subtree AS (
    SELECT c.id_category, 0 AS lvl FROM tb_category c WHERE c.id_category = 1
    UNION ALL
    SELECT c.id_category, s.lvl + 1
    FROM tb_category c
    JOIN subtree s ON c.id_parent_category = s.id_category
)
SELECT * FROM subtree;
```

O passo recursivo pergunta "quem são as filhas de X?" a cada nível, ou seja,
filtra por `id_parent_category`.

### Antes (sem índice em id_parent_category)

```
Recursive Union (actual time=0.007..1.487 rows=61 loops=1)
  ->  Index Only Scan using tb_category_pkey on tb_category c (actual time=0.007..0.007 rows=1 loops=1)
  ->  Hash Join (actual time=0.305..0.490 rows=20 loops=3)
        ->  Seq Scan on tb_category c_1 (actual time=0.001..0.202 rows=5026 loops=3)
Execution Time: 1.512 ms
```

Cada nível da recursão lê a tabela inteira (5.026 linhas × 3 níveis).

### Índice criado

```sql
CREATE INDEX idx_category_parent ON tb_category (id_parent_category);
```

### Depois (com índice em id_parent_category)

```
Recursive Union (actual time=0.006..0.134 rows=61 loops=1)
  ->  Index Only Scan using tb_category_pkey on tb_category c (actual time=0.005..0.005 rows=1 loops=1)
  ->  Nested Loop
        ->  WorkTable Scan on subtree s (actual time=0.000..0.001 rows=20 loops=3)
        ->  Index Scan using idx_category_parent on tb_category c_1 (actual time=0.002..0.002 rows=1 loops=61)
              Index Cond: (id_parent_category = s.id_category)
Execution Time: 0.170 ms
```

| | Antes | Depois |
|---|---|---|
| Acesso às filhas | `Seq Scan` (5.026 linhas, 3x) | `Index Scan` em `idx_category_parent` |
| Tempo de execução | 1,512 ms | 0,170 ms |
| Ganho | — | **~8,9x mais rápido** |

O ganho cresce com a profundidade e com o tamanho da tabela: sem o índice,
cada nível a mais é outra varredura completa. O mesmo índice atende a trava
anti-ciclo (`fn_check_category_cycle`, que sobe pela PK) só no sentido
inverso, então ela já usava `tb_category_pkey`.

---

## Onde os índices ficam no projeto

| Índice | Dicionário | Migration |
|---|---|---|
| `idx_log_stock_batch_id_batch` (`id_batch`) | `ddl/logs/create_log_indexes.sql` | `migrations/V003__audit_logs.sql` |
| `idx_requisition_status_created_at` (`status`, `created_at DESC`) | `ddl/indexes/create_indexes.sql` | `migrations/V001__init_database.sql` |
| `idx_productsupplier_product_price` (`id_product`, `reference_price`) | `ddl/indexes/create_indexes.sql` | `migrations/V001__init_database.sql` |
| `idx_batch_kitchen_status_expiration` (`id_kitchen`, `status`, `expiration_date`) | `ddl/indexes/create_indexes.sql` | `migrations/V001__init_database.sql` |
| `idx_category_parent` (`id_parent_category`) | `ddl/indexes/create_indexes.sql` | `migrations/V019__category_hierarchy.sql` |

Rollback isolado em `ddl/indexes/rollback/drop_indexes.sql` e
`ddl/logs/rollback/drop_log_indexes.sql`; todos os cinco também estão no
`migrations/rollback/drop_everything.sql`.

> [!NOTE]
> Os índices de uma coluna só citados nos "Antes" (`idx_requisition_status`, `idx_productsupplier_product` e `idx_batch_kitchen`) são prefixo exato dos compostos acima (ou da PK) e foram removidos na `V022`: a leitura usa o composto, e o de uma coluna só custava escrita sem ganho. As medições dos "Antes" continuam valendo como registro do que existia na época.
