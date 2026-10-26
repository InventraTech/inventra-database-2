# Neo4j no Inventra: cobertura inteligente de fornecedores

Especificação técnica de uma projeção de grafo aplicada a uma única decisão operacional: descobrir quais fornecedores conseguem atender os produtos de uma requisição, com quais lacunas, custo de referência e prazo máximo.

| | |
|---|---|
| **Arquitetura de dados** | BD2-06 + Traversal |
| **Recorte funcional** | Requisições → itens → produtos → fornecedores |
| **Status do documento** | Proposta implementável. O Cypher, a massa de teste e a reprojeção estão versionados em [`neo4j/`](../README.md) e validados num Neo4j 5 descartável ([`tests/`](../tests)); o endpoint na API Spring ainda não foi implementado. |
| **Card** | [INV2-27](https://inventraoficial.atlassian.net/browse/INV2-27) — modelar entidades como grafo no Neo4j (ver [aderência ao card](#aderência-ao-card-inv2-27)) |
| **Origem** | Documento de arquitetura proposto em 14 de outubro de 2026, baseado no código atual do Inventra e na identidade visual fornecida: [`Inventra_Neo4j_Cobertura_Fornecedores.pdf`](Inventra_Neo4j_Cobertura_Fornecedores.pdf) (16 páginas). Este arquivo traz o conteúdo completo do PDF; os ajustes feitos ao versionar e executar estão em [Notas de implementação](#notas-de-implementação-neste-repositório). |

*Gestão • Estoque • Controle • Organização • Inovação • Tecnologia*

---

## 01 Resumo executivo

> [!IMPORTANT]
> **Decisão proposta.** Adicionar ao módulo de requisições uma análise de cobertura de fornecedores. Dada uma requisição, o serviço percorre os produtos pedidos e todos os fornecedores vinculados a eles, ranqueando quem cobre mais itens e expondo o que cada fornecedor não atende.

**Por que é um diferencial real.** Em vez de obrigar o usuário a escolher um fornecedor antes de receber inteligência, o Inventra apresenta as opções possíveis para o conjunto inteiro da requisição — inclusive quando nenhum fornecedor cobre tudo.

**Por que o recorte é pequeno.** O grafo contém somente `Requisition`, `Product` e `Supplier`, com dois relacionamentos. Não substitui estoque, autenticação, aprovações, compras ou o banco relacional.

### Pergunta de negócio

> “Para esta requisição, quais fornecedores conseguem atender o maior número de produtos, quais itens cada um deixa descobertos e qual é a estimativa de custo e prazo da parte coberta?”

| Aspecto | Decisão |
|---|---|
| Fonte de verdade | PostgreSQL continua responsável pelas entidades e transações. |
| Papel do Neo4j | Projeção de leitura reconstruível para traversal e agregação por conectividade. |
| Entrada | `requisitionId` obtido pela rota REST e `kitchenId` validado pelo usuário autenticado. |
| Saída | Ranking, cobertura %, itens cobertos, lacunas, custo coberto, maior lead time e rating. |
| Consistência | Eventual; reconciliação periódica corrige eventos atrasados ou duplicados. |
| Falha aceitável | Endpoint responde indisponibilidade específica; fluxo transacional segue no PostgreSQL. |

### Leitura rápida do fluxo

1. Usuário abre uma requisição em análise.
2. API valida a cozinha.
3. Neo4j percorre `REQUESTS` e `SUPPLIES`.
4. Serviço calcula e ordena a cobertura.
5. Interface mostra fornecedores e lacunas.
6. Usuário ainda decide qual fornecedor sugerir; nenhuma compra é criada automaticamente.

---

## 02 Onde isso entra no Inventra real

A proposta nasce de um ponto específico já presente no código. Ela não pressupõe um novo módulo amplo; amplia a decisão dentro de `Requisition` e reutiliza vínculos já mantidos em `ProductSupplier`.

| Evidência encontrada | Comportamento atual | Oportunidade do grafo |
|---|---|---|
| `RequisitionItem` | Liga requisição a produto; aceita `suggestedSupplier`, `quantity`, `estimatedPrice` e `note`. | O nó `Requisition` e `REQUESTS` preservam a demanda a analisar. |
| `ProductSupplier` | Liga produto a fornecedor com `supplierCode`, `referencePrice` e `leadTimeDays`. | `SUPPLIES` transforma cada vínculo em uma aresta rica para comparação. |
| `RequisitionService.addItem` | Fornecedor sugerido é opcional, mas a referência de preço só é buscada quando o ID já foi enviado. | A análise antecede a escolha e descobre todos os candidatos conectados. |
| `KitchenAccessGuard` | Usuário só acessa a cozinha do próprio cadastro. | A requisição é validada no PostgreSQL antes de consultar o grafo. |
| Redis | Já existe como infraestrutura para fila/concorrência de registro de produto. | Não é substituído: Redis coordena fluxo; Neo4j responde conectividade. |

| Antes | Depois |
|---|---|
| O solicitante informa um fornecedor ou deixa o campo vazio. A API não apresenta uma visão conjunta da requisição, nem identifica automaticamente produtos sem alternativa de fornecimento. | Um botão “Analisar fornecedores” retorna um ranking explicável. O usuário enxerga cobertura total/parcial, prazo e custo de referência antes de selecionar ou dividir a compra. |

> [!WARNING]
> **Limite funcional deliberado.** O endpoint não altera `suggestedSupplierId`, `estimatedPrice`, status da requisição ou estoque. Ele é somente leitura e serve à decisão humana. A gravação continua nas rotas existentes, preservando regras, auditoria e procedures do PostgreSQL.

> [!TIP]
> **Hipótese de valor a validar.** Reduzir o tempo de comparação manual e revelar requisições inviáveis mais cedo. Métricas sugeridas: tempo entre inclusão do último item e escolha do fornecedor; percentual de requisições com cobertura total; quantidade média de fornecedores avaliados; incidência de itens sem fornecedor cadastrado.

---

## 03 Aplicação na jornada da requisição

O ponto ideal é a tela de detalhes de uma requisição com status `UNDER_REVIEW`, imediatamente após os itens serem adicionados e antes da aprovação.

| Etapa | Ação do usuário | Resposta do Inventra |
|---|---|---|
| 1. Montagem | Inclui arroz, óleo, feijão e leite na requisição. | PostgreSQL salva `RequisitionItem`; projeção recebe ou reconcilia `REQUESTS`. |
| 2. Análise | Seleciona “Analisar fornecedores”. | API verifica JWT, carrega a requisição e executa `KitchenAccessGuard`. |
| 3. Traversal | Nenhuma escolha prévia de fornecedor é exigida. | Neo4j navega requisição → produtos ← fornecedores e agrega por fornecedor. |
| 4. Decisão | Compara “Alfa: 75% / 3 itens” e “Beta: 50% / 2 itens”. | Interface lista itens cobertos, lacunas, custo estimado e maior prazo. |
| 5. Ação | Escolhe um fornecedor por item ou decide fracionar. | Rotas atuais persistem `suggestedSupplierId` e `estimatedPrice`. |

### Estados de interface recomendados

| Estado | Comportamento |
|---|---|
| **Cobertura total** | Selo verde “Atende 4 de 4”. Mostrar prazo máximo e custo total de referência; oferecer ação para aplicar a sugestão item a item, sujeita a confirmação. |
| **Cobertura parcial** | Selo amarelo “Atende 3 de 4”. Destacar produto sem cobertura e manter visíveis fornecedores complementares. |
| **Sem vínculo cadastrado** | Mensagem objetiva: “Nenhum fornecedor está associado ao produto Leite integral”. Direcionar ao cadastro Product ↔ Supplier já existente. A lista vem de [`queries/uncovered_products.cypher`](../queries/uncovered_products.cypher). |
| **Projeção indisponível** | Não bloquear criação, submissão ou aprovação. Exibir “Análise temporariamente indisponível” e permitir repetir. |

> [!NOTE]
> **Regra de explicabilidade.** Cada posição do ranking deve ser auditável: cobertura é itens distintos cobertos ÷ itens distintos solicitados; prazo é o maior `leadTimeDays` entre os itens cobertos; custo usa `referencePrice × quantity` apenas onde há preço; rating vem de `Supplier`. Nenhum “score mágico” deve ocultar esses componentes.

---

## 04 Modelo de grafo mínimo

Traversal de cobertura: requisição → produtos ← fornecedores.

```mermaid
flowchart LR
  R["Requisition<br/>#842"] -- REQUESTS --> A["Product<br/>Arroz"]
  R -- REQUESTS --> O["Product<br/>Óleo"]
  SA["Supplier<br/>Alfa"] -- SUPPLIES --> A
  SA -- SUPPLIES --> O
  SB["Supplier<br/>Beta"] -- SUPPLIES --> O
```

O percurso possui dois níveis de relacionamento e cruza uma aresta de demanda com uma aresta de capacidade de fornecimento. A direção desenhada expressa semântica; o Cypher pode atravessar `SUPPLIES` no sentido inverso.

| Elemento | Chave | Propriedades projetadas | Origem relacional |
|---|---|---|---|
| `:Requisition` | `id` | `kitchenId`, `type`, `status`, `createdAt`, `updatedAt` | `tb_requisition` |
| `:Product` | `id` | `name`, `active` | `tb_product` |
| `:Supplier` | `id` | `legalName`, `rating`, `active` | `tb_supplier` |
| `:REQUESTS` | `itemId` | `quantity`, `estimatedPrice`, `note`, `updatedAt` | `tb_requisition_item` |
| `:SUPPLIES` | `productId` + `supplierId` | `supplierCode`, `referencePrice`, `leadTimeDays`, `updatedAt` | `tb_product_supplier` |

Mapeamento coluna a coluna feito pela reprojeção ([`seeds/seed.ipynb`](../seeds/seed.ipynb)):

| Grafo | PostgreSQL |
|---|---|
| `Requisition.id` / `kitchenId` / `type` / `status` | `tb_requisition.id_requisition` / `id_kitchen` / `requisition_type` / `status` |
| `Product.id` / `name` / `active` | `tb_product.id_product` / `name` / `active` |
| `Supplier.id` / `legalName` / `rating` / `active` | `tb_supplier.id_supplier` / `legal_name` / `rating` / `active` |
| `REQUESTS.itemId` / `quantity` / `estimatedPrice` / `note` | `tb_requisition_item.id_requisition_item` / `quantity` / `estimated_price` / `note` |
| `SUPPLIES.supplierCode` / `referencePrice` / `leadTimeDays` | `tb_product_supplier.supplier_code` / `reference_price` / `lead_time_days` |

### Decisões de modelagem

- **`RequisitionItem` vira relacionamento:** sua razão de existir é qualificar o vínculo entre uma requisição e um produto; `itemId` permanece como identificador da aresta.
- **`ProductSupplier` vira relacionamento:** preço e prazo pertencem à capacidade de um fornecedor atender um produto, não aos nós isoladamente.
- **`Kitchen` não vira nó nesta primeira versão:** `kitchenId` na requisição basta para filtro defensivo; incluir `Kitchen` ampliaria o escopo sem melhorar o traversal principal.
- **Categoria e estoque ficam fora:** não são necessários para responder a pergunta escolhida. Essa exclusão mantém a projeção pequena e coerente.
- **IDs do PostgreSQL são preservados:** permitem `MERGE` idempotente e rastreabilidade cruzada.

---

## 05 Schema, restrições e projeção

As constraints evitam duplicidade de nós; índices apoiam a entrada por requisição/cozinha. A unicidade dos relacionamentos é garantida pelo padrão de `MERGE` com as chaves relacionais.

Versionado em [`migrations/V001__supplier_coverage.cypher`](../migrations/V001__supplier_coverage.cypher), com o dicionário em [`constraints/`](../constraints/create_constraints.cypher) e [`indexes/`](../indexes/create_indexes.cypher):

```cypher
CREATE CONSTRAINT requisition_id IF NOT EXISTS
FOR (r:Requisition) REQUIRE r.id IS UNIQUE;

CREATE CONSTRAINT product_id IF NOT EXISTS
FOR (p:Product) REQUIRE p.id IS UNIQUE;

CREATE CONSTRAINT supplier_id IF NOT EXISTS
FOR (s:Supplier) REQUIRE s.id IS UNIQUE;

CREATE INDEX requisition_kitchen IF NOT EXISTS
FOR (r:Requisition) ON (r.kitchenId);

CREATE INDEX supplier_active IF NOT EXISTS
FOR (s:Supplier) ON (s.active);
```

### Upsert de uma requisição e seus itens

Evento `REQUISITION_UPSERTED` / `ITEM_UPSERTED`, em [`projection/requisition_upserted.cypher`](../projection/requisition_upserted.cypher). A versão versionada também apaga a aresta de um item que não está mais na lista (ver notas):

```cypher
MERGE (r:Requisition {id: $requisition.id})
SET r.kitchenId = $requisition.kitchenId,
    r.type = $requisition.type,
    r.status = $requisition.status,
    r.updatedAt = datetime();

UNWIND $items AS item
MERGE (p:Product {id: item.productId})
SET p.name = item.productName, p.active = item.productActive
MERGE (r)-[rel:REQUESTS {itemId: item.itemId}]->(p)
SET rel.quantity = item.quantity,
    rel.estimatedPrice = item.estimatedPrice,
    rel.note = item.note,
    rel.updatedAt = datetime();
```

### Upsert do catálogo de fornecimento

Evento `PRODUCT_SUPPLIER_UPSERTED`, em [`projection/product_supplier_upserted.cypher`](../projection/product_supplier_upserted.cypher):

```cypher
MERGE (s:Supplier {id: $supplierId})
SET s.legalName = $legalName, s.rating = $rating, s.active = $active
MERGE (p:Product {id: $productId})
MERGE (s)-[rel:SUPPLIES]->(p)
SET rel.supplierCode = $supplierCode,
    rel.referencePrice = $referencePrice,
    rel.leadTimeDays = $leadTimeDays,
    rel.updatedAt = datetime();
```

> [!NOTE]
> **Remoções também são eventos.** Ao excluir `RequisitionItem` ou desvincular `ProductSupplier`, a projeção deve apagar a aresta correspondente. Desativar produto/fornecedor atualiza `active`; exclusão física do nó só ocorre quando a política relacional realmente o remover.

| Evento | Arquivo | Efeito no grafo |
|---|---|---|
| `REQUISITION_UPSERTED` / `ITEM_UPSERTED` | [`projection/requisition_upserted.cypher`](../projection/requisition_upserted.cypher) | `MERGE` da requisição e das arestas `REQUESTS` |
| `ITEM_DELETED` | [`projection/item_deleted.cypher`](../projection/item_deleted.cypher) | apaga a aresta `REQUESTS {itemId}` |
| `PRODUCT_SUPPLIER_UPSERTED` | [`projection/product_supplier_upserted.cypher`](../projection/product_supplier_upserted.cypher) | `MERGE` da aresta `SUPPLIES` com preço e prazo |
| `PRODUCT_SUPPLIER_DELETED` | [`projection/product_supplier_deleted.cypher`](../projection/product_supplier_deleted.cypher) | apaga a aresta `SUPPLIES` (também usado pela reconciliação) |
| `SUPPLIER_UPDATED` | [`projection/supplier_updated.cypher`](../projection/supplier_updated.cypher) | atualiza `legalName`, `rating` e `active` |
| `PRODUCT_UPDATED` | [`projection/product_updated.cypher`](../projection/product_updated.cypher) | atualiza `name` e `active` |

---

## 06 Arquitetura e sincronização

```mermaid
flowchart LR
  C["Cliente<br/>Inventra"] --> API["REST API<br/>Spring Boot"]
  API --> PG[("PostgreSQL<br/>fonte oficial")]
  PG -- evento --> OUT["Outbox /<br/>reconciliação"]
  OUT --> PS["Projection<br/>Service"]
  PS -- MERGE --> N[("Neo4j<br/>projeção")]
  API -. leitura do ranking .-> N
```

Falha no Neo4j não desfaz a transação de negócio; a projeção é reprocessável.

A integração recomendada é assíncrona. A transação de negócio confirma primeiro no PostgreSQL; depois um evento projeta a mudança no Neo4j. Isso evita que uma indisponibilidade do grafo impeça a operação principal.

| Mecanismo | Responsabilidade | Detalhe operacional |
|---|---|---|
| Outbox no PostgreSQL | Registrar evento na mesma transação da alteração. | Tipos: `REQUISITION_UPSERTED`, `ITEM_UPSERTED`/`DELETED`, `PRODUCT_SUPPLIER_UPSERTED`/`DELETED`, `SUPPLIER_UPDATED`. |
| Projection worker | Ler eventos, montar parâmetros e executar `MERGE`/`DELETE` no Neo4j. | Idempotente por `aggregateId` + `eventId`; retry com backoff; dead letter após limite. |
| Reconciliação | Comparar contagens e `updatedAt`; recompor entidades divergentes. | Job noturno e endpoint administrativo protegido para uma requisição. A reconstrução completa e a comparação de contagens estão em [`seeds/seed.ipynb`](../seeds/seed.ipynb). |
| Watermark | Expor idade da projeção na resposta. | `projectionUpdatedAt` e `stale=true` quando exceder, por exemplo, 5 minutos. |
| Redis existente | Pode acordar/serializar o worker, se o padrão do projeto for reaproveitado. | Não armazena o grafo e não se torna fonte de verdade. |

### Consistência e atomicidade

- O endpoint consulta o PostgreSQL primeiro para validar existência, cozinha e autorização; depois usa `id` + `kitchenId` no Cypher.
- Se a projeção estiver atrasada, a resposta inclui `stale` e timestamp — não retorna um ranking silenciosamente desatualizado.
- Eventos duplicados são seguros porque os comandos usam `MERGE` e `SET`; eventos fora de ordem usam `version`/`updatedAt` para impedir regressão.
- Uma reconstrução completa apaga apenas o banco/projeção Neo4j controlado e reprojeta tabelas relacionais; nunca apaga o PostgreSQL.

---

## 07 Traversal principal em Cypher

A consulta entra pela requisição autorizada, materializa sua demanda, encontra fornecedores conectados a pelo menos um produto e calcula cobertura e lacunas por fornecedor.

Versão executável em [`queries/supplier_coverage.cypher`](../queries/supplier_coverage.cypher), validada pelo [`tests/check_supplier_coverage.sh`](../tests/check_supplier_coverage.sh):

```cypher
MATCH (r:Requisition {id: $requisitionId, kitchenId: $kitchenId})
MATCH (r)-[req:REQUESTS]->(p:Product)
// o mesmo produto em dois itens conta uma vez, com a quantidade somada
WITH r, p, sum(req.quantity) AS quantity
WITH r,
     collect({product: p, quantity: quantity}) AS demand,
     count(p) AS totalProducts

UNWIND demand AS d
WITH demand, totalProducts, d, d.product AS product
MATCH (s:Supplier)-[sp:SUPPLIES]->(product)
WHERE s.active = true AND product.active = true

WITH demand, totalProducts, s,
     collect(DISTINCT {
       id: product.id,
       name: product.name,
       quantity: d.quantity,
       referencePrice: sp.referencePrice,
       leadTimeDays: sp.leadTimeDays
     }) AS covered,
     max(sp.leadTimeDays) AS maxLeadTimeDays

WITH totalProducts, s, covered, maxLeadTimeDays,
     [d IN demand
      WHERE NOT d.product.id IN [c IN covered | c.id]
      | {id: d.product.id, name: d.product.name}] AS uncovered,
     reduce(cost = 0.0, c IN covered |
       cost + coalesce(c.referencePrice, 0) * c.quantity
     ) AS coveredCost

RETURN s.id AS supplierId,
       s.legalName AS supplierName,
       s.rating AS rating,
       size(covered) AS coveredCount,
       totalProducts,
       round(100.0 * size(covered) / totalProducts, 1) AS coveragePercent,
       covered, uncovered,
       round(coveredCost, 2) AS estimatedCoveredCost,
       size([c IN covered WHERE c.referencePrice IS NULL]) AS priceMissingCount,
       maxLeadTimeDays

ORDER BY coveragePercent DESC,
         maxLeadTimeDays ASC,
         rating DESC,
         estimatedCoveredCost ASC,
         supplierName ASC;
```

> [!NOTE]
> **Traversal real:** o resultado não é obtido por busca de um nó isolado. A consulta atravessa `REQUESTS` para descobrir o conjunto dinâmico de produtos e, para cada produto, atravessa `SUPPLIES` no sentido inverso para descobrir e agrupar candidatos.

Ordem do ranking: maior cobertura → menor prazo máximo → maior rating → menor custo coberto → nome. A consulta complementar [`queries/uncovered_products.cypher`](../queries/uncovered_products.cypher) devolve os produtos que nenhum fornecedor ativo atende (aviso global do estado “Sem vínculo cadastrado”).

---

## 08 Contrato REST

> [!IMPORTANT]
> **`GET /api/requisitions/{id}/supplier-coverage`**
>
> Endpoint autenticado e somente leitura. O `kitchenId` não vem do cliente: é obtido da requisição carregada no PostgreSQL e validado com `KitchenAccessGuard`.

### Resposta 200 — exemplo não trivial

```json
{
  "requisitionId": 842,
  "kitchenId": 12,
  "totalProducts": 4,
  "projectionUpdatedAt": "2026-10-14T11:40:12-03:00",
  "stale": false,
  "suppliers": [
    {
      "supplierId": 31,
      "supplierName": "Distribuidora Alfa",
      "rating": 5,
      "coveredCount": 3,
      "coveragePercent": 75.0,
      "estimatedCoveredCost": 486.50,
      "maxLeadTimeDays": 3,
      "coveredProducts": [
        {"productId": 10, "name": "Arroz", "quantity": 20,
         "referencePrice": 18.50, "leadTimeDays": 2},
        {"productId": 11, "name": "Óleo", "quantity": 10,
         "referencePrice": 7.65, "leadTimeDays": 3},
        {"productId": 12, "name": "Feijão", "quantity": 5,
         "referencePrice": 8.00, "leadTimeDays": 2}
      ],
      "uncoveredProducts": [{"productId": 13, "name": "Leite"}]
    }
  ]
}
```

### Respostas de erro

| HTTP | Quando | Formato esperado |
|---|---|---|
| 401 | JWT ausente/inválido | Problem Details já adotado pelo projeto. |
| 403 | Usuário não pertence à cozinha da requisição | `title=Forbidden`; detail da `KitchenAccessGuard`. |
| 404 | Requisição não existe | `ResourceNotFoundException` → Problem Details. |
| 409 | Projeção ainda não contém a requisição e política decide não degradar | `type=/problems/graph-projection-not-ready`. |
| 503 | Driver Neo4j indisponível/timeout | `type=/problems/supplier-coverage-unavailable`; `retryable=true`. |

---

## 09 Implementação Java/Spring proposta

Estrutura mínima, sem converter todo o domínio JPA para Spring Data Neo4j. O código vive no [repositório da API](https://github.com/InventraTech/inventra-development-spring-redis-neo4j-2); este repositório versiona o Cypher que ele executa.

```text
core/service/requisition/coverage/
  SupplierCoverageUseCase.java
  SupplierCoverageService.java
  SupplierCoverageGraphRepository.java
  model/SupplierCoverageResponse.java

infrastructure/graph/
  Neo4jSupplierCoverageRepository.java
  Neo4jProjectionWriter.java
  GraphProjectionHealthIndicator.java

infrastructure/controller/
  RequisitionController.java   // novo GET /{id}/supplier-coverage
```

### Dependência e configuração

```xml
<dependency>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-data-neo4j</artifactId>
</dependency>
```

```properties
spring.neo4j.uri=${NEO4J_URI:bolt://localhost:7687}
spring.neo4j.authentication.username=${NEO4J_USERNAME:neo4j}
spring.neo4j.authentication.password=${NEO4J_PASSWORD}
app.neo4j.supplier-coverage.enabled=${NEO4J_COVERAGE_ENABLED:false}
app.neo4j.supplier-coverage.timeout=${NEO4J_COVERAGE_TIMEOUT:2s}
```

### Controller e serviço

```java
@GetMapping("/{id}/supplier-coverage")
public ResponseEntity<SupplierCoverageResponse> supplierCoverage(
        @PathVariable Integer id) {
    return ResponseEntity.ok(coverageUseCase.analyze(id));
}

@Service
@RequiredArgsConstructor
class SupplierCoverageService implements SupplierCoverageUseCase {

    private final RequisitionRepository requisitions;
    private final KitchenAccessGuard accessGuard;
    private final SupplierCoverageGraphRepository graph;

    public SupplierCoverageResponse analyze(Integer id) {
        Requisition req = requisitions.findById(id)
            .orElseThrow(() -> new ResourceNotFoundException(
                "Requisição não encontrada."));
        Integer kitchenId = req.getKitchen().getId();
        accessGuard.assertAccess(kitchenId);
        return graph.findCoverage(id, kitchenId);
    }
}
```

> [!TIP]
> **Preferência:** usar `Neo4jClient` com parâmetros, pois o retorno é uma projeção agregada e não uma árvore de entidades. `@Query` em repository também é válido, mas tende a acoplar o DTO à infraestrutura.

---

## 10 Repositório de traversal e DTO

```java
public interface SupplierCoverageGraphRepository {
    SupplierCoverageResponse findCoverage(Integer requisitionId, Integer kitchenId);
}

@Repository
@RequiredArgsConstructor
class Neo4jSupplierCoverageRepository
        implements SupplierCoverageGraphRepository {

    // conteúdo de neo4j/queries/supplier_coverage.cypher
    private static final String CYPHER = ...;

    private final Neo4jClient neo4j;
    private final GraphProjectionClock projectionClock;

    public SupplierCoverageResponse findCoverage(Integer requisitionId,
                                                 Integer kitchenId) {
        List<Map<String, Object>> rows = neo4j.query(CYPHER)
            .bind(requisitionId).to("requisitionId")
            .bind(kitchenId).to("kitchenId")
            .fetch().all().stream().toList();

        List<SupplierCoverage> suppliers = rows.stream().map(this::mapSupplier).toList();
        // totalProducts vem em todas as linhas; sem fornecedor candidato, o serviço usa os itens do PostgreSQL
        Integer totalProducts = rows.isEmpty() ? null : ((Number) rows.getFirst().get("totalProducts")).intValue();

        return new SupplierCoverageResponse(
            requisitionId, kitchenId, totalProducts,
            projectionClock.lastUpdatedAt(), projectionClock.isStale(),
            suppliers);
    }
}

public record SupplierCoverageResponse(
    Integer requisitionId,
    Integer kitchenId,
    Integer totalProducts,
    Instant projectionUpdatedAt,
    boolean stale,
    List<SupplierCoverage> suppliers
) {}

public record SupplierCoverage(
    Integer supplierId,
    String supplierName,
    Integer rating,
    Integer coveredCount,
    BigDecimal coveragePercent,
    BigDecimal estimatedCoveredCost,
    Integer priceMissingCount,
    Integer maxLeadTimeDays,
    List<CoveredProduct> coveredProducts,
    List<UncoveredProduct> uncoveredProducts
) {}

public record CoveredProduct(Integer productId, String name, BigDecimal quantity,
                             BigDecimal referencePrice, Integer leadTimeDays) {}

public record UncoveredProduct(Integer productId, String name) {}
```

### Cuidados de mapeamento

- Converter números do driver explicitamente (`Value.asInt`/`asDouble`) e construir `BigDecimal` de maneira controlada.
- Não retornar CNPJ, e-mail ou WhatsApp: a decisão não necessita desses dados e a superfície de exposição fica menor.
- Quando `referencePrice` estiver nulo, marcar `costCompleteness=false` ou `priceMissingCount`; zero não pode parecer preço real. O Cypher versionado já devolve `priceMissingCount`.
- Tratar lista vazia de itens antes do Cypher para produzir resposta coerente ou erro de regra de negócio.
- Aplicar timeout dedicado menor que o timeout global e instrumentar duração/erro da consulta.

> [!WARNING]
> **Feature flag.** O endpoint só é registrado/ativado quando `NEO4J_COVERAGE_ENABLED=true`. Em ambientes sem Neo4j — inclusive o atual — a aplicação inicia normalmente e a documentação continua verificável por testes de unidade e contrato.

---

## 11 Massa de teste e resultado esperado

Conjunto mínimo recomendado: 1 requisição, 4 produtos e 3 fornecedores. Ele gera cobertura total, parcial e lacuna, evitando um teste trivial. Versionado completo (com todos os `SUPPLIES` da matriz) em [`seeds/requisition_842.cypher`](../seeds/requisition_842.cypher).

| Fornecedor | Arroz | Óleo | Feijão | Leite | Cobertura |
|---|---|---|---|---|---|
| Alfa (rating 5) | R$ 18,50 / 2d | R$ 7,65 / 3d | R$ 8,00 / 2d | — | 3/4 = 75% |
| Beta (rating 4) | — | R$ 7,20 / 5d | — | R$ 5,50 / 4d | 2/4 = 50% |
| Gama (rating 3) | R$ 17,90 / 7d | — | R$ 7,80 / 6d | R$ 5,70 / 7d | 3/4 = 75% |

**Demanda da requisição #842:** Arroz 20 un.; Óleo 10 un.; Feijão 5 un.; Leite 12 un. Pela ordenação definida, Alfa aparece antes de Gama: ambos cobrem 75%, mas Alfa tem prazo máximo de 3 dias contra 7. Beta aparece depois com 50%.

| Posição | Fornecedor | Cobertos | Descobertos | Custo coberto | Prazo máx. |
|---|---|---|---|---|---|
| 1 | Alfa | Arroz, Óleo, Feijão | Leite | R$ 486,50 | 3 dias |
| 2 | Gama | Arroz, Feijão, Leite | Óleo | R$ 465,40 | 7 dias |
| 3 | Beta | Óleo, Leite | Arroz, Feijão | R$ 138,00 | 5 dias |

Conta do custo coberto: Alfa = 20 × 18,50 + 10 × 7,65 + 5 × 8,00 = 370,00 + 76,50 + 40,00 = **486,50**; Gama = 20 × 17,90 + 5 × 7,80 + 12 × 5,70 = 358,00 + 39,00 + 68,40 = **465,40**; Beta = 10 × 7,20 + 12 × 5,50 = 72,00 + 66,00 = **138,00**.

### Cypher de seed demonstrativo

```cypher
MERGE (r:Requisition {id: 842})
SET r.kitchenId = 12, r.type = 'PURCHASE', r.status = 'UNDER_REVIEW'

MERGE (a:Product {id: 10}) SET a.name = 'Arroz', a.active = true
MERGE (o:Product {id: 11}) SET o.name = 'Óleo', o.active = true
MERGE (f:Product {id: 12}) SET f.name = 'Feijão', f.active = true
MERGE (l:Product {id: 13}) SET l.name = 'Leite', l.active = true

MERGE (r)-[q1:REQUESTS {itemId: 1}]->(a) SET q1.quantity = 20
MERGE (r)-[q2:REQUESTS {itemId: 2}]->(o) SET q2.quantity = 10
MERGE (r)-[q3:REQUESTS {itemId: 3}]->(f) SET q3.quantity = 5
MERGE (r)-[q4:REQUESTS {itemId: 4}]->(l) SET q4.quantity = 12

MERGE (alfa:Supplier {id: 31}) SET alfa.legalName = 'Distribuidora Alfa', alfa.rating = 5, alfa.active = true
MERGE (beta:Supplier {id: 32}) SET beta.legalName = 'Beta', beta.rating = 4, beta.active = true
MERGE (gama:Supplier {id: 33}) SET gama.legalName = 'Gama', gama.rating = 3, gama.active = true

MERGE (alfa)-[s1:SUPPLIES]->(a) SET s1.supplierCode = 'ALF-010', s1.referencePrice = 18.50, s1.leadTimeDays = 2
MERGE (alfa)-[s2:SUPPLIES]->(o) SET s2.supplierCode = 'ALF-011', s2.referencePrice = 7.65, s2.leadTimeDays = 3
MERGE (alfa)-[s3:SUPPLIES]->(f) SET s3.supplierCode = 'ALF-012', s3.referencePrice = 8.00, s3.leadTimeDays = 2
MERGE (beta)-[s4:SUPPLIES]->(o) SET s4.supplierCode = 'BET-011', s4.referencePrice = 7.20, s4.leadTimeDays = 5
MERGE (beta)-[s5:SUPPLIES]->(l) SET s5.supplierCode = 'BET-013', s5.referencePrice = 5.50, s5.leadTimeDays = 4
MERGE (gama)-[s6:SUPPLIES]->(a) SET s6.supplierCode = 'GAM-010', s6.referencePrice = 17.90, s6.leadTimeDays = 7
MERGE (gama)-[s7:SUPPLIES]->(f) SET s7.supplierCode = 'GAM-012', s7.referencePrice = 7.80, s7.leadTimeDays = 6
MERGE (gama)-[s8:SUPPLIES]->(l) SET s8.supplierCode = 'GAM-013', s8.referencePrice = 5.70, s8.leadTimeDays = 7;
```

---

## 12 Estratégia de testes

| Camada | Cenário | Asserção principal | Onde |
|---|---|---|---|
| Unitário — serviço | Requisição existente e usuário da mesma cozinha. | Guard chamado antes do graph repository; IDs corretos encaminhados. | API |
| Unitário — segurança | Usuário de cozinha diferente. | 403; graph repository nunca é chamado. | API |
| Unitário — erro | `Neo4jClient` lança timeout. | Exceção traduzida em 503 Problem Details; sem alteração no PostgreSQL. | API |
| Contrato web | GET autenticado para `/supplier-coverage`. | JSON contém percentuais, listas cobertas/descobertas, `stale` e timestamp. | API |
| Integração — Neo4j | Seed com 4×3 da seção anterior. | Ordem Alfa, Gama, Beta; percentuais 75, 75, 50. | [`check_supplier_coverage.sh`](../tests/check_supplier_coverage.sh) passo 2 |
| Integração — lacuna | Produto sem qualquer `SUPPLIES`. | Produto aparece como descoberto para todos os candidatos; aviso global calculado. | [`check_supplier_coverage.sh`](../tests/check_supplier_coverage.sh) passo 5 |
| Projeção | Mesmo evento processado duas vezes. | Contagens de nós/arestas não mudam; propriedades permanecem iguais. | [`check_supplier_coverage.sh`](../tests/check_supplier_coverage.sh) passo 4 |
| Reconciliação | Aresta removida no PostgreSQL, presente no Neo4j. | Job detecta e exclui `SUPPLIES` órfão. | [`check_supplier_coverage.sh`](../tests/check_supplier_coverage.sh) passos 6 e 7 |

Além da tabela, o [`check_supplier_coverage.sh`](../tests/check_supplier_coverage.sh) cobre o isolamento por cozinha (passo 3), fornecedor e produto desativados (passo 7) e preço nulo sinalizado em `priceMissingCount` (passo 8); o [`check_migrations.sh`](../tests/check_migrations.sh) cobre idempotência, dicionário × migration e rollback do schema.

### Exemplo de teste de integração

```java
@Test
void ranksByCoverageThenLeadTime() {
    seedRequisition842();

    var result = repository.findCoverage(842, 12);

    assertThat(result.suppliers())
        .extracting(SupplierCoverage::supplierName)
        .containsExactly("Distribuidora Alfa", "Gama", "Beta");

    assertThat(result.suppliers().getFirst().coveragePercent())
        .isEqualByComparingTo("75.0");

    assertThat(result.suppliers().getFirst().uncoveredProducts())
        .extracting(UncoveredProduct::name)
        .containsExactly("Leite");
}
```

### Como testar sem acesso atual ao Neo4j

- Testes unitários mockam `SupplierCoverageGraphRepository` e cobrem autorização, transformação e falhas.
- O Cypher e o seed ficam versionados; na CI com Docker/Testcontainers, o mesmo contrato executa contra Neo4j efêmero (aqui: `.github/workflows/neo4j.yml` num `neo4j:5`).
- Enquanto a infraestrutura não existir na API, marcar apenas os testes de integração com tag `neo4j` — nunca declarar que o traversal foi executado onde ele não foi.
- Validar manualmente exemplos aritméticos do documento para garantir que custo e ordenação são determinísticos (conta na seção 11).

---

## 13 DevOps, implantação e observabilidade

A entrega segue o padrão observado na documentação do projeto: branch por tipo/objetivo, commits convencionais e PR identificado pelo item do backlog.

| Item | Especificação |
|---|---|
| Branch | `feat/neo4j-cobertura-fornecedores` |
| Commits | `feat(neo4j): adiciona projeção de fornecedores`<br>`feat(requisition): expõe análise de cobertura`<br>`test(neo4j): cobre traversal e isolamento por cozinha`<br>`docs(neo4j): documenta operação e recuperação` |
| PR | `INV2-XX: Análise de cobertura de fornecedores com Neo4j` |
| Segredos | `NEO4J_URI`, `NEO4J_USERNAME` e `NEO4J_PASSWORD` no cofre do ambiente; nunca em `application.properties` versionado. |
| Ambientes | Feature flag desligada por padrão. Habilitar primeiro em desenvolvimento, depois homologação e produção. |

### Pipeline proposto

- Build e testes unitários sempre; testes Neo4j em job com serviço efêmero quando a infraestrutura for disponibilizada.
- Análise de dependências e imagem já presentes no fluxo DevOps permanecem; o driver Neo4j entra na mesma verificação de vulnerabilidades.
- Smoke test pós-deploy: health do driver, constraint check, projeção de uma requisição sintética e chamada do endpoint.
- Rollback: desligar `NEO4J_COVERAGE_ENABLED` e reimplantar; nenhuma migração relacional destrutiva é necessária para desativar a leitura.

### Métricas e alertas

| Métrica | Objetivo inicial | Alerta |
|---|---|---|
| `supplier_coverage_query_seconds` p95 | < 300 ms | p95 > 800 ms por 10 min |
| `graph_projection_lag_seconds` | < 60 s | p95 > 300 s |
| `graph_projection_dead_letter_total` | 0 | qualquer incremento |
| `supplier_coverage_errors_total` / requests | < 1% | ≥ 5% por 5 min |
| `coverage_full_ratio` | Produto/negócio | queda abrupta pode indicar projeção incompleta |

> [!CAUTION]
> **Privacidade e acesso.** O grafo não precisa de dados pessoais do requisitante nem contatos do fornecedor. Registrar em log IDs, duração, contagens e `correlationId` — não payload integral ou credenciais.

---

## 14 Por que Neo4j e não somente SQL

SQL consegue responder à pergunta. O diferencial do Neo4j não é impossibilidade relacional, e sim tornar a conectividade o modelo primário de leitura e permitir evolução do percurso sem multiplicar joins e subconsultas.

| Critério | PostgreSQL | Neo4j neste recorte |
|---|---|---|
| Transações e integridade | Melhor escolha; já é a fonte de verdade. | Não deve assumir aprovações, estoque ou persistência principal. |
| Consulta atual | JOIN `requisition_item` → `product` → `product_supplier` → `supplier`, GROUP BY, agregações e anti-join para lacunas. | O padrão `r→p←s` expressa diretamente demanda e cobertura. |
| Evolução | Adicionar substitutos, regiões, bloqueios e múltiplos saltos aumenta joins/CTEs. | Novas relações podem estender o traversal mantendo legibilidade. |
| Custo operacional | Já pago e dominado pela equipe. | Novo banco, driver, backup lógico da projeção, monitoramento e conhecimento. |
| Justificativa honesta | Uma única consulta não obriga Neo4j. | Vale se a análise de rede virar capacidade do produto e for usada com frequência. |

### Complexidade SQL equivalente

Para cada fornecedor candidato seria necessário: juntar os itens da requisição; juntar vínculos de fornecimento; agrupar por fornecedor; contar produtos distintos; calcular custo; determinar maior prazo; e executar um anti-join/`NOT EXISTS` para produzir os produtos não cobertos. O resultado é viável, mas a noção de “cobertura” fica distribuída entre joins, GROUP BY e subconsultas.

Para comparação, a mesma resposta no PostgreSQL atual:

```sql
WITH demand AS (
    SELECT i.id_product, p.name, sum(i.quantity) AS quantity
    FROM tb_requisition_item i
    JOIN tb_requisition r ON r.id_requisition = i.id_requisition
    JOIN tb_product p ON p.id_product = i.id_product
    WHERE r.id_requisition = :requisition_id AND r.id_kitchen = :kitchen_id
    GROUP BY i.id_product, p.name
), covered AS (
    SELECT s.id_supplier, s.legal_name, s.rating, d.id_product, d.quantity, ps.reference_price, ps.lead_time_days
    FROM demand d
    JOIN tb_product p ON p.id_product = d.id_product AND p.active
    JOIN tb_product_supplier ps ON ps.id_product = d.id_product
    JOIN tb_supplier s ON s.id_supplier = ps.id_supplier AND s.active
)
SELECT c.id_supplier, c.legal_name, c.rating,
       count(*) AS covered_count,
       round(100.0 * count(*) / (SELECT count(*) FROM demand), 1) AS coverage_percent,
       round(sum(coalesce(c.reference_price, 0) * c.quantity), 2) AS estimated_covered_cost,
       max(c.lead_time_days) AS max_lead_time_days,
       (SELECT string_agg(d.name, ', ' ORDER BY d.name) FROM demand d
         WHERE NOT EXISTS (SELECT 1 FROM covered x WHERE x.id_supplier = c.id_supplier AND x.id_product = d.id_product)) AS uncovered
FROM covered c
GROUP BY c.id_supplier, c.legal_name, c.rating
ORDER BY coverage_percent DESC, max_lead_time_days, c.rating DESC, estimated_covered_cost, c.legal_name;
```

| Quando manter só SQL | Quando o grafo compensa |
|---|---|
| Poucas requisições, consulta rara, relações estáveis e equipe sem capacidade operacional para outro banco. Nesse cenário, uma view/materialized view pode ser mais econômica. | Cobertura vira função central; relações crescem para substituição de produtos, fornecedores alternativos, restrições e caminhos logísticos; explicabilidade do percurso é requisito. |

> [!IMPORTANT]
> **Decisão recomendada.** Implementar como experimento isolado e medido. Se o endpoint não reduzir esforço ou não evoluir para relações adicionais, desligar a feature e manter a solução SQL. O desenho evita lock-in porque todos os dados continuam no PostgreSQL.

---

## 15 Riscos, critérios de aceite e entrega

### Riscos e respostas

| Risco | Impacto | Mitigação |
|---|---|---|
| Projeção atrasada | Ranking usa vínculo antigo. | `stale`/timestamp, outbox, retry, reconciliação e observabilidade. |
| Preço nulo interpretado como zero | Decisão financeira incorreta. | `priceMissingCount`/`costCompleteness`; não somar silenciosamente como valor válido. |
| Vazamento entre cozinhas | Acesso indevido. | Carga relacional + `KitchenAccessGuard` antes do grafo + `kitchenId` no `MATCH`. |
| Custo operacional maior que o valor | Complexidade desnecessária. | Feature flag, métricas de adoção e critério explícito de descontinuação. |
| Consulta cresce sem limite | Latência/memória. | Limitar itens por requisição, timeout, índices e `PROFILE` em homologação. |

### Critérios de aceite rastreáveis

| Critério | Evidência definida nesta especificação |
|---|---|
| Pergunta de negócio clara | [Seção 01](#01-resumo-executivo): ranking de cobertura, lacunas, custo e prazo para uma requisição. |
| Traversal ≥ 2 relações | [Seção 07](#07-traversal-principal-em-cypher): `Requisition-[:REQUESTS]→Product←[:SUPPLIES]-Supplier`. |
| Endpoint REST | [Seção 08](#08-contrato-rest): `GET /api/requisitions/{id}/supplier-coverage` e contrato JSON. |
| Justificativa grafo × SQL | [Seção 14](#14-por-que-neo4j-e-não-somente-sql): comparação, limites e condição econômica de adoção. |
| Resultado não trivial | [Seção 11](#11-massa-de-teste-e-resultado-esperado): 4 produtos, 3 fornecedores e coberturas 75/75/50%. |
| Aderência ao projeto | Seções [02](#02-onde-isso-entra-no-inventra-real), [06](#06-arquitetura-e-sincronização) e [09](#09-implementação-javaspring-proposta): entidades reais, `KitchenAccessGuard`, Redis e Spring Boot. |

### Definition of Done

- [x] Cypher versionado, parametrizado e validado em ambiente Neo4j controlado (`neo4j:5` descartável, [`tests/`](../tests)).
- [ ] Endpoint protegido, documentado no OpenAPI e coberto por testes de autorização e contrato.
- [ ] Projeção idempotente, reconciliação documentada e dashboards/alertas ativos (Cypher idempotente e reconciliação por contagem prontos; worker e alertas na API).
- [ ] Feature flag e rollback exercitados; indisponibilidade do grafo não bloqueia fluxo principal.
- [ ] Resultado demonstrado com massa não trivial e evidência anexada ao PR (massa e resultado verificados em [`check_supplier_coverage.sh`](../tests/check_supplier_coverage.sh)).

> [!NOTE]
> **Conclusão.** O diferencial não é “usar um banco de grafo”. É transformar uma relação já existente — produtos e seus fornecedores — em uma decisão contextual para a requisição. O recorte é pequeno, explicável, reversível e pode crescer somente se provar valor.

---

## Notas de implementação neste repositório

Ao versionar a especificação e executar o Cypher num Neo4j 5.26 real, estes pontos do documento original foram corrigidos ou completados:

| Ponto | No documento original | Como ficou |
|---|---|---|
| Traversal (seção 07) | `MATCH (s:Supplier)-[sp:SUPPLIES]->(d.product)` | Não executa: o Neo4j rejeita acesso a propriedade dentro do padrão (`Invalid input '.'`). O produto é extraído com `WITH d.product AS product` antes do `MATCH`. |
| Produto repetido em dois itens | Contaria duas vezes em `covered` | A demanda é agregada por produto (`sum(req.quantity)`), mantendo a regra “itens distintos”. |
| Preço nulo | Somado como zero | `priceMissingCount` no retorno, como pedem os cuidados de mapeamento e a tabela de riscos. |
| Custo | Ponto flutuante cru | `round(coveredCost, 2)`. |
| Seed (seção 11) | Só os `REQUESTS`; “Repetir MERGE de Supplier/SUPPLIES conforme a matriz” | Matriz completa com os 8 `SUPPLIES` em [`seeds/requisition_842.cypher`](../seeds/requisition_842.cypher); `MERGE` pela chave `itemId` e `SET` da quantidade (o original fazia `MERGE` pela quantidade, o que duplicaria a aresta ao mudar o valor). |
| Remoções | Descritas, sem comando | [`item_deleted.cypher`](../projection/item_deleted.cypher), [`product_supplier_deleted.cypher`](../projection/product_supplier_deleted.cypher) e remoção de itens ausentes no upsert completo da requisição. |
| Desativar produto | Descrito, sem evento | [`product_updated.cypher`](../projection/product_updated.cypher). |
| Reconstrução completa | Descrita | [`seeds/seed.ipynb`](../seeds/seed.ipynb): reprojeta do PostgreSQL e compara contagens. |
| Repositório Java (seção 10) | Construtor com argumentos fora da ordem do record, sem `totalProducts`; `projectionClock`, `mapSupplier` e a interface não declarados | Assinaturas alinhadas, `priceMissingCount` no DTO e records `CoveredProduct`/`UncoveredProduct` declarados. Continua sendo código ilustrativo: **não foi compilado**. |
| IDs e nomes dos fornecedores | Só o id do Alfa (31) é fixado; a tabela da seção 11 diz “Alfa”, o JSON da seção 08 e o teste da seção 12 dizem “Distribuidora Alfa” | Beta = 32 e Gama = 33; o seed usa “Distribuidora Alfa”, “Beta” e “Gama”, que é o que o teste da seção 12 espera. |
| Figuras | Os dois diagramas (seções 04 e 06) são ilustrações no PDF | Redesenhados em Mermaid. |

### Trechos literais do PDF que foram corrigidos

Para que nenhum conteúdo do documento se perca, estes são os trechos como aparecem no PDF.

Traversal da seção 07 (o Neo4j 5 rejeita a linha `->(d.product)`):

```cypher
MATCH (r:Requisition {id: $requisitionId, kitchenId: $kitchenId})
MATCH (r)-[req:REQUESTS]->(p:Product)
WITH r,
     collect({product: p, request: req}) AS demand,
     count(DISTINCT p) AS totalProducts

UNWIND demand AS d
MATCH (s:Supplier)-[sp:SUPPLIES]->(d.product)
WHERE s.active = true AND d.product.active = true

WITH r, demand, totalProducts, s,
     collect(DISTINCT {
       id: d.product.id,
       name: d.product.name,
       quantity: d.request.quantity,
       referencePrice: sp.referencePrice,
       leadTimeDays: sp.leadTimeDays
     }) AS covered,
     max(sp.leadTimeDays) AS maxLeadTimeDays

WITH r, totalProducts, s, covered, maxLeadTimeDays,
     [d IN demand
      WHERE NOT d.product.id IN [c IN covered | c.id]
      | {id: d.product.id, name: d.product.name}] AS uncovered,
     reduce(cost = 0.0, c IN covered |
       cost + coalesce(c.referencePrice, 0) * c.quantity
     ) AS estimatedCoveredCost

RETURN s.id AS supplierId,
       s.legalName AS supplierName,
       s.rating AS rating,
       size(covered) AS coveredCount,
       totalProducts,
       round(100.0 * size(covered) / totalProducts, 1) AS coveragePercent,
       covered, uncovered, estimatedCoveredCost, maxLeadTimeDays

ORDER BY coveragePercent DESC,
         maxLeadTimeDays ASC,
         rating DESC,
         estimatedCoveredCost ASC,
         supplierName ASC;
```

Seed demonstrativo da seção 11:

```cypher
MERGE (r:Requisition {id:842}) SET r.kitchenId=12, r.status='UNDER_REVIEW'
MERGE (a:Product {id:10}) SET a.name='Arroz', a.active=true
MERGE (o:Product {id:11}) SET o.name='Óleo', o.active=true
MERGE (f:Product {id:12}) SET f.name='Feijão', f.active=true
MERGE (l:Product {id:13}) SET l.name='Leite', l.active=true
MERGE (r)-[:REQUESTS {itemId:1, quantity:20}]->(a)
MERGE (r)-[:REQUESTS {itemId:2, quantity:10}]->(o)
MERGE (r)-[:REQUESTS {itemId:3, quantity:5}]->(f)
MERGE (r)-[:REQUESTS {itemId:4, quantity:12}]->(l);
// Repetir MERGE de Supplier/SUPPLIES conforme a matriz acima.
```

Repositório e DTO da seção 10:

```java
@Repository
@RequiredArgsConstructor
class Neo4jSupplierCoverageRepository
        implements SupplierCoverageGraphRepository {
    private final Neo4jClient neo4j;

    public SupplierCoverageResponse findCoverage(Integer requisitionId,
                                                 Integer kitchenId) {
        List<SupplierCoverage> suppliers = neo4j.query(CYPHER)
            .bind(requisitionId).to("requisitionId")
            .bind(kitchenId).to("kitchenId")
            .fetchAs(SupplierCoverage.class)
            .mappedBy((type, row) -> mapSupplier(row))
            .all().stream().toList();

        return new SupplierCoverageResponse(
            requisitionId, kitchenId, suppliers,
            projectionClock.lastUpdatedAt(), projectionClock.isStale());
    }
}

public record SupplierCoverageResponse(
    Integer requisitionId,
    Integer kitchenId,
    Integer totalProducts,
    Instant projectionUpdatedAt,
    boolean stale,
    List<SupplierCoverage> suppliers
) {}

public record SupplierCoverage(
    Integer supplierId,
    String supplierName,
    Integer rating,
    Integer coveredCount,
    BigDecimal coveragePercent,
    BigDecimal estimatedCoveredCost,
    Integer maxLeadTimeDays,
    List<CoveredProduct> coveredProducts,
    List<UncoveredProduct> uncoveredProducts
) {}
```

Estrutura de pastas da seção 09, como no PDF (sem a interface `SupplierCoverageGraphRepository`):

```text
core/service/requisition/coverage/
  SupplierCoverageUseCase.java
  SupplierCoverageService.java
  model/SupplierCoverageResponse.java

infrastructure/graph/
  Neo4jSupplierCoverageRepository.java
  Neo4jProjectionWriter.java
  GraphProjectionHealthIndicator.java

infrastructure/controller/
  RequisitionController.java // novo GET /{id}/supplier-coverage
```

No PDF, os critérios de aceite da seção 15 apontam para páginas: “Página 2” (resumo), “Página 8” (traversal), “Página 9” (REST), “Página 15” (grafo × SQL), “Página 12” (massa de teste) e “Páginas 3, 7 e 10” (aderência). Aqui eles viraram links para as seções correspondentes.

---

## Aderência ao card INV2-27

Critérios de aceite do [INV2-27](https://inventraoficial.atlassian.net/browse/INV2-27) (“[EXTRA] Modelar entidades como grafo no Neo4j”) conferidos contra este material. Esta seção **não faz parte do PDF**.

| Critério do card | Situação | Evidência |
|---|---|---|
| Neo4j rodando e acessível pela aplicação | **Parcial** | O Neo4j 5 sobe num container e recebe o schema, a massa e as consultas no CI ([`neo4j.yml`](../../.github/workflows/neo4j.yml)); a reprojeção ([`seeds/seed.ipynb`](../seeds/seed.ipynb)) conecta pelo driver Python. Nenhuma aplicação Spring está conectada: o `spring-boot-starter-data-neo4j` e o `Neo4jClient` das seções 09 e 10 continuam proposta. |
| Pelo menos 3 tipos de nós e 2 tipos de relacionamentos | Atende | Nós `Requisition`, `Product` e `Supplier`; relacionamentos `REQUESTS` e `SUPPLIES` (seção 04), com constraints de unicidade na [`V001`](../migrations/V001__supplier_coverage.cypher). |
| Dados de exemplo carregados e visíveis no Neo4j Browser | **Parcial** | A massa da seção 11 ([`requisition_842.cypher`](../seeds/requisition_842.cypher)) carrega 8 nós e 12 relacionamentos, e o [`check_supplier_coverage.sh`](../tests/check_supplier_coverage.sh) confere o resultado. A visualização no Neo4j Browser (`http://localhost:7474`) não foi conferida. |
| Modelagem justificada: por que grafo e não relacional | Atende | Seção 04 (decisões de modelagem) e seção 14 (comparação com SQL, com a consulta equivalente e quando manter só SQL). |

Diferenças entre o card e o PDF:

- O card sugere nós `Produto`, `Categoria` e `Fornecedor` e relacionamentos `PERTENCE_A` e `FORNECIDO_POR`, em português e com `@Node`/`@Relationship`. O PDF usa rótulos em inglês, **não tem `Categoria`** (excluída de propósito, seção 04) e usa `REQUESTS` e `SUPPLIES`.
- O card pede o mapeamento com `@Node`/`@Relationship` (Spring Data Neo4j). O PDF propõe `Neo4jClient` com projeção por Cypher, “sem converter todo o domínio JPA” (seção 09).
- O traversal (pergunta de negócio, endpoint REST) é do [INV2-28](https://inventraoficial.atlassian.net/browse/INV2-28), hoje **Cancelado**. A seção 07 existe como proposta e a consulta está versionada e testada em [`queries/`](../queries), mas o endpoint não foi implementado.
