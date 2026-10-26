# Neo4j

**Status: proposta implementável — cobertura inteligente de fornecedores.** O grafo é uma projeção de leitura do PostgreSQL para uma única decisão: dada uma requisição, quais fornecedores atendem mais produtos, o que cada um deixa descoberto, o custo de referência e o prazo máximo da parte coberta.

A especificação completa (resumo executivo, aplicação na jornada, modelo, schema, sincronização, Cypher, contrato REST, implementação Spring, massa de teste, testes, DevOps, comparação com SQL, riscos e critérios de aceite) está em **[`docs/COBERTURA_FORNECEDORES.md`](docs/COBERTURA_FORNECEDORES.md)**.

| | |
|---|---|
| **Modelo** | `(:Requisition)-[:REQUESTS]->(:Product)<-[:SUPPLIES]-(:Supplier)` |
| **Fonte da verdade** | PostgreSQL (`tb_requisition`, `tb_requisition_item`, `tb_product`, `tb_supplier`, `tb_product_supplier`). O grafo é reconstruível a qualquer momento |
| **Chaves** | IDs do PostgreSQL, com constraint de unicidade por rótulo |
| **Consulta** | [`queries/supplier_coverage.cypher`](queries/supplier_coverage.cypher): ranking por cobertura → prazo → rating → custo |
| **Endpoint previsto** | `GET /api/requisitions/{id}/supplier-coverage` na API Spring, atrás da flag `NEO4J_COVERAGE_ENABLED` |
| **CI** | [`neo4j.yml`](../.github/workflows/neo4j.yml): schema e traversal num `neo4j:5` descartável |

## Uso hoje

| Repositório | Situação |
|-------------|----------|
| [`inventra-development-spring-redis-neo4j-2`](https://github.com/InventraTech/inventra-development-spring-redis-neo4j-2) (API) | Ainda sem dependência (`spring-boot-starter-data-neo4j`), configuração (`spring.neo4j.*`) ou código. A seção 09 da especificação descreve o que entra lá |
| [`inventra-artificial-intelligence-2`](https://github.com/InventraTech/inventra-artificial-intelligence-2) (IAI) | Não usa Neo4j. A IA usa MongoDB (ver [`../mongo`](../mongo)) |

Levantamento de 14/10/2026. Este repositório versiona o lado do banco: o Cypher que a API vai executar, a massa de teste com resultado esperado e a reprojeção a partir do PostgreSQL, todos executados de verdade nos testes.

## Estrutura

```text
neo4j/
├── constraints/     # unicidade de Requisition.id, Product.id, Supplier.id + rollback/
├── indexes/         # Requisition.kitchenId e Supplier.active + rollback/
├── migrations/      # V001__supplier_coverage.cypher (idempotente) + rollback/drop_everything.cypher
├── projection/      # um .cypher por evento do outbox (upsert e remoção), executado pelo worker da API
├── queries/         # supplier_coverage.cypher (traversal) e uncovered_products.cypher (aviso global)
├── seeds/           # requisition_842.cypher (massa 4×3 da especificação) e seed.ipynb (reprojeção do PostgreSQL)
├── tests/           # check_migrations.sh e check_supplier_coverage.sh, num neo4j:5 descartável
└── docs/            # COBERTURA_FORNECEDORES.md + PDF original
```

## Eventos de projeção

| Evento do outbox | Arquivo | Parâmetros |
|------------------|---------|------------|
| `REQUISITION_UPSERTED` / `ITEM_UPSERTED` | [`requisition_upserted.cypher`](projection/requisition_upserted.cypher) | `$requisition {id, kitchenId, type, status}`, `$items` (lista completa) |
| `ITEM_DELETED` | [`item_deleted.cypher`](projection/item_deleted.cypher) | `$requisitionId`, `$itemId` |
| `PRODUCT_SUPPLIER_UPSERTED` | [`product_supplier_upserted.cypher`](projection/product_supplier_upserted.cypher) | `$supplierId`, `$legalName`, `$rating`, `$active`, `$productId`, `$supplierCode`, `$referencePrice`, `$leadTimeDays` |
| `PRODUCT_SUPPLIER_DELETED` | [`product_supplier_deleted.cypher`](projection/product_supplier_deleted.cypher) | `$supplierId`, `$productId` |
| `SUPPLIER_UPDATED` | [`supplier_updated.cypher`](projection/supplier_updated.cypher) | `$supplierId`, `$legalName`, `$rating`, `$active` |
| `PRODUCT_UPDATED` | [`product_updated.cypher`](projection/product_updated.cypher) | `$productId`, `$name`, `$active` |

Todos usam `MERGE` pelas chaves do PostgreSQL: reprocessar um evento não duplica nó nem aresta. CNPJ, e-mail e WhatsApp do fornecedor não entram no grafo.

## Resultado esperado da massa de teste

Requisição #842 (cozinha 12): Arroz 20, Óleo 10, Feijão 5 e Leite 12 unidades.

| Posição | Fornecedor | Cobertura | Cobertos | Descobertos | Custo coberto | Prazo máx. |
|---------|------------|-----------|----------|-------------|---------------|------------|
| 1 | Distribuidora Alfa | 75% | Arroz, Óleo, Feijão | Leite | R$ 486,50 | 3 dias |
| 2 | Gama | 75% | Arroz, Feijão, Leite | Óleo | R$ 465,40 | 7 dias |
| 3 | Beta | 50% | Óleo, Leite | Arroz, Feijão | R$ 138,00 | 5 dias |

## Desenvolvimento

1. Mudança de schema entra no dicionário (`constraints/`, `indexes/`) **e** numa nova `migrations/V00N__*.cypher` idempotente (`IF NOT EXISTS`), registrada em `:SchemaMigration`.
2. Valide num Neo4j descartável, com os mesmos scripts do CI:

   ```bash
   docker run -d --name inventra-neo4j-test -e NEO4J_AUTH=none -v "$PWD:/repo" neo4j:5
   docker exec inventra-neo4j-test bash /repo/neo4j/tests/check_migrations.sh
   docker exec inventra-neo4j-test bash /repo/neo4j/tests/check_supplier_coverage.sh
   ```

   | Script | O que garante |
   |--------|---------------|
   | `check_migrations.sh` | Aplica a V001 duas vezes (idempotência), compara com o dicionário, faz rollback e reaplica |
   | `check_supplier_coverage.sh` | Ranking da massa 4×3 (ordem, %, custo, prazo), isolamento por cozinha, idempotência dos eventos, lacuna, remoções, desativação e preço nulo |

   Os dois apagam a projeção: nunca rodar contra o banco real.
3. **Reprojeção a partir do PostgreSQL:** `pip install -r seeds/requirements.txt` e [`seeds/seed.ipynb`](seeds/seed.ipynb) com as variáveis `DB_*` e `NEO4J_*` do `.env`. Aplica a V001, limpa só a projeção, reprojeta fornecedores, produtos, vínculos e requisições pelos mesmos `projection/*.cypher`, compara as contagens com o PostgreSQL e mostra o ranking de uma requisição `UNDER_REVIEW`.
