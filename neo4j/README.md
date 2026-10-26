# Neo4j

**Status: não usado.** Nenhum serviço do Inventra conecta ao Neo4j hoje. O que existe aqui é uma **proposta** de projeção em grafo para a cobertura de fornecedores por requisição, descrita em [`docs/COBERTURA_FORNECEDORES.md`](docs/COBERTURA_FORNECEDORES.md) (PDF original em [`docs/`](docs/Inventra_Neo4j_Cobertura_Fornecedores.pdf)). Constraints, índices, seed e a consulta `cobertura_fornecedores_validada.cypher` foram executados num Neo4j 5 descartável (Docker); isso não roda no CI e nenhum serviço usa o grafo.

Levantamento feito em 14/10/2026, em todas as branches de:

| Repositório | Resultado |
|-------------|-----------|
| [`inventra-development-spring-redis-neo4j-2`](https://github.com/InventraTech/inventra-development-spring-redis-neo4j-2) (API) | O nome cita Neo4j, mas não há dependência (`pom.xml` sem `spring-boot-starter-data-neo4j`), configuração (`spring.neo4j.*`), variável de ambiente nem código. A única menção é o link do repositório em `docs/inv2-25-review.md` |
| [`inventra-artificial-intelligence-2`](https://github.com/InventraTech/inventra-artificial-intelligence-2) (IAI) | Nenhuma menção. A IA usa MongoDB (ver [`../mongo`](../mongo)) e consulta o estoque pela API |

Quando o Neo4j entrar, a pasta segue o mesmo desenho das outras:

```text
neo4j/
├── constraints/     # CREATE CONSTRAINT ... IF NOT EXISTS (unicidade e existência) + rollback/
├── indexes/         # CREATE INDEX ... IF NOT EXISTS + rollback/
├── migrations/      # V001__*.cypher idempotentes + rollback/drop_everything.cypher
├── seeds/           # seed.ipynb (driver neo4j + dotenv), com IDs vindos do PostgreSQL
├── tests/           # aplica 2x, rollback e reaplica num neo4j:5 descartável
└── docs/            # modelo de nós e relacionamentos e consultas atendidas
```

Os nós devem carregar o ID do PostgreSQL (`id_product`, `id_supplier`, `id_kitchen`...) como chave com constraint de unicidade, já que o PostgreSQL continua sendo a fonte da verdade do cadastro.

## Proposta: cobertura de fornecedores

Grafo mínimo (`Requisition`, `Product`, `Supplier`; relacionamentos `REQUESTS` e `SUPPLIES`) que responde a uma pergunta: quais fornecedores atendem os produtos de uma requisição, com quais lacunas, custo de referência e prazo máximo. O PostgreSQL segue como fonte da verdade; o Neo4j seria uma projeção de leitura reconstruível.

| Pasta | Arquivo | Conteúdo |
|-------|---------|----------|
| `constraints/` | `constraints.cypher` | Unicidade de `Requisition`, `Product` e `Supplier` por `id` |
| `indexes/` | `indexes.cypher` | `Requisition.kitchenId` e `Supplier.active` |
| `queries/` | `upsert_requisicao.cypher`, `upsert_catalogo_fornecimento.cypher` | `MERGE` idempotente da projeção |
| `queries/` | `cobertura_fornecedores_validada.cypher` | Traversal e ranking, validado: devolve Alfa 75%, Gama 75%, Beta 50% |
| `queries/` | `cobertura_fornecedores.cypher` | Transcrição literal do PDF; **não executa** (padrão `->(d.product)` inválido). Só para conferência |
| `seeds/` | `seed_cobertura.cypher` | Requisição #842, 4 produtos, 3 fornecedores e os vínculos `SUPPLIES` (idempotente) |
| `docs/` | `COBERTURA_FORNECEDORES.md` | Especificação completa |
