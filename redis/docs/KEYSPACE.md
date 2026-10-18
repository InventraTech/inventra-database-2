# Keyspace Redis

Catálogo das chaves que a API Spring ([`inventra-development-spring-redis-neo4j-2`](https://github.com/InventraTech/inventra-development-spring-redis-neo4j-2)) grava no Redis. O Redis não tem schema: este documento é o contrato de cada chave (estrutura, campos, TTL e quem lê ou escreve), no mesmo papel do catálogo de dados do PostgreSQL.

| | |
|---|---|
| **Serviço** | Aiven for Valkey/Redis, standalone, TLS (`REDIS_SSL=true`) |
| **Variáveis** | `REDIS_HOST`, `REDIS_PORT`, `REDIS_USERNAME`, `REDIS_PASSWORD`, `REDIS_DATABASE` (padrão `0`), `REDIS_SSL` |
| **Cliente** | `StringRedisTemplate` (valores sempre string; JSON serializado pela API) |
| **Timeouts** | conexão e comando: 10 s |
| **Usos** | refresh tokens, pedidos de acesso à cozinha, fila de cadastro por código de barras e ranking de validade por cozinha |

## Visão geral

| Padrão da chave | Tipo | TTL | Dono (classe da API) |
|-----------------|------|-----|----------------------|
| `rt:{hashDoToken}` | Hash | refresh (30 dias) | `RedisRefreshTokenStore` |
| `rt:fam:{familyId}` | Set | refresh (30 dias), renovado a cada token | `RedisRefreshTokenStore` |
| `kar:{id}` | Hash | 7 dias enquanto `PENDING`; sem TTL depois de decidido | `RedisKitchenAccessRequestStore` |
| `kar:user:{userId}` | String | sem TTL | `RedisKitchenAccessRequestStore` |
| `kar:user:{userId}:kitchens` | Hash | sem TTL | `RedisKitchenAccessRequestStore` |
| `kar:kitchen:{kitchenId}` | Sorted Set | sem TTL | `RedisKitchenAccessRequestStore` |
| `inventra:product-registration:ready` | List | sem TTL | `RedisProductRegistrationQueue` |
| `inventra:product-registration:ready:{token}` | List | 30 s, renovado com a concessão | `RedisProductRegistrationQueue` |
| `inventra:product-registration:job:{eventId}` | String (JSON) | sem TTL enquanto pendente; 7 dias depois do resultado | `RedisProductRegistrationQueue` |
| `inventra:product-registration:pending` | Sorted Set | sem TTL | `RedisProductRegistrationQueue` |
| `inventra:product-registration:sequence` | String (contador) | sem TTL | `RedisProductRegistrationQueue` |
| `inventra:product-registration:consumer-lock` | String | 30 s, renovado a cada 5 s | `ProductRegistrationConsumer` |
| `inventra:product-registration:errors` | List (DLQ) | 7 dias sem novas falhas (lista inteira) | `RedisProductRegistrationQueue` |
| `inventra:ranking:expiration:{kitchenId}` | Sorted Set | 60 s, renovado a cada reconstrução | `RedisExpirationRanking` |
| `inventra:ranking:expiration:{kitchenId}:build:{uuid}` | Sorted Set temporário | 60 s; renomeado atomicamente ao publicar | `RedisExpirationRanking` |

`userId` e `decidedBy` são o `tb_user.id_user` (UUID) e `kitchenId` é o `tb_kitchen.id_kitchen` do PostgreSQL. O Redis não tem chave estrangeira: um usuário ou cozinha removido no PostgreSQL deixa chaves órfãs até o TTL ou a limpeza na leitura.

## Refresh tokens (`rt:*`)

Rotação de refresh token com detecção de reuso. A chave é o **hash** do token; o token em si nunca é gravado.

| Chave | Campo | Conteúdo |
|-------|-------|----------|
| `rt:{hash}` | `userId` | UUID do usuário |
| | `familyId` | Família de rotação (todos os tokens descendentes do mesmo login) |
| | `pwd` | Impressão da senha no momento da emissão; trocar a senha invalida o token |
| | `usedAt` | Epoch ms em que o token foi trocado por outro (só existe depois da rotação) |
| `rt:fam:{familyId}` | membros | Hashes dos tokens da família, para revogar todos de uma vez |

- TTL: `jwt.refresh-expiration-ms` (padrão 2.592.000.000 ms = 30 dias, variável `JWT_REFRESH_EXPIRATION_MS`).
- Reuso de um token com `usedAt` depois de 10 s de tolerância revoga a família inteira (`revokeFamily`).

## Pedidos de acesso à cozinha (`kar:*`)

Um usuário pede para entrar numa cozinha; o supervisor aprova ou recusa. O pedido pendente expira sozinho; o decidido vira histórico permanente.

| Chave | Conteúdo |
|-------|----------|
| `kar:{id}` | Hash: `userId`, `userName`, `userEmail`, `kitchenId`, `kitchenName`, `status` (`PENDING`, `APPROVED`, `REJECTED`), `createdAt`, `decidedAt`, `decidedBy`, `reason` (datas em epoch ms) |
| `kar:user:{userId}` | ID do pedido mais recente do usuário |
| `kar:user:{userId}:kitchens` | Hash `kitchenId → id` do pedido mais recente do usuário em cada cozinha |
| `kar:kitchen:{kitchenId}` | Sorted Set de IDs, score = `createdAt`; listagem do supervisor |

- TTL do pendente: `app.kitchen-access-request.ttl` (padrão 7 dias).
- A decisão é atômica na API: só decide se ainda estiver `PENDING` e remove o TTL (`PERSIST`) na mesma operação ([`commands/kitchen-access/decide.redis`](../commands/kitchen-access/decide.redis)).
- Quando um pendente expira, o ID continua em `kar:kitchen:*` e `kar:user:*:kitchens`; a API remove o ID órfão na próxima leitura.
- `userName` e `userEmail` são **cópias** do PostgreSQL no momento do pedido (dado pessoal no Redis). Os pedidos decididos não expiram; a exclusão de um usuário deve apagar `kar:user:{userId}*` e os `kar:{id}` dele.

## Fila de cadastro por código de barras (`inventra:product-registration:*`)

Fila FIFO confiável da INV2-25 (Redis List com `LPUSH`/`BRPOP`). O fluxo completo e as garantias estão em [`PRODUCT_QUEUE.md`](PRODUCT_QUEUE.md). O prefixo vem de `REDIS_PRODUCT_QUEUE_KEY_PREFIX`: ambientes que compartilham o mesmo Redis precisam de prefixos diferentes, e os testes usam `inventra:test:...`.

| Sufixo | Conteúdo |
|--------|----------|
| `ready` | IDs aguardando quando não há consumer com concessão |
| `ready:{token}` | Lista própria da concessão atual; um consumer antigo nunca retira itens da sucessora |
| `job:{eventId}` | JSON do `ProductRegistrationJob`: `eventId`, `userId`, `request` (`name`, `brand`, `categoryId`, `unitId`, `barcode`), `status` (`QUEUED`, `PROCESSING`, `COMPLETED`, `FAILED`), `productId`, `errorCode`, `submittedAt`, `startedAt`, `finishedAt`, `attempts`, `nextAttemptAt` |
| `pending` | Índice durável dos pedidos não confirmados (score = `sequence`); a concessão reconstrói sua lista a partir dele |
| `sequence` | Contador monotônico do índice |
| `consumer-lock` | Token da concessão exclusiva de consumo |
| `errors` | DLQ: JSON do job falho ou `{eventId, status, errorCode, originalPayload}` (até 4 KiB) da quarentena; máx. 1.000 itens |

O vínculo com o PostgreSQL é a coluna `tb_product.registration_event_id` (UUID único), gravada na mesma transação do produto: é ela que permite reprocessar o mesmo `eventId` sem duplicar o produto. Essa coluna está hoje só na migration da API (`V010__product_registration_event.sql`), ainda não no `postgre/` deste repositório.

## Ranking de validade (`inventra:ranking:expiration:*`)

Ranking da INV2-26 com um Sorted Set por cozinha. Entram lotes `ACTIVE`, com saldo positivo e data de validade preenchida. O membro é o ID do lote com padding de 10 posições, e o score é a data de validade em epoch day; por isso os lotes que vencem primeiro aparecem nas primeiras posições. Empates são resolvidos pelo ID numérico crescente.

| Chave | Conteúdo |
|-------|----------|
| `inventra:ranking:expiration:{kitchenId}` | Snapshot publicado do ranking da cozinha; contém também o marcador interno `~empty` com score `+inf` quando a cozinha não possui lotes elegíveis |
| `inventra:ranking:expiration:{kitchenId}:build:{uuid}` | Snapshot temporário criado pelo script Lua; recebe os membros e é publicado com `RENAME`, sem expor ranking parcial |

- TTL padrão: 60 segundos, configurável por `REDIS_RANKING_TTL_SECONDS`; o prefixo é configurável por `REDIS_RANKING_KEY_PREFIX`.
- Entrada, baixa, reposição, ajuste e consumo FEFO publicam a alteração após o commit PostgreSQL. A reconstrução assíncrona substitui o snapshot inteiro de forma atômica.
- Cache ausente ou expirado é reconstruído a partir do PostgreSQL na próxima consulta. Uma falha do Redis não desfaz uma movimentação já confirmada no banco relacional.
- Endpoint: `GET /ranking?kitchenId={id}&limit={1..100}`. A autenticação e a autorização por cozinha permanecem iguais às da API.
- Contrato completo e critérios: [`RANKING.md`](RANKING.md).

## Comandos por operação

Cada operação da API está em [`commands/`](../commands), como a sequência de comandos Redis que ela executa, com placeholders (`<eventId>`, `<token>`...) e comentários. Os arquivos são de leitura: não rodam com `redis-cli` sem substituir os placeholders.

| Arquivo | Operações |
|---------|-----------|
| `auth/refresh-token.redis` | Emitir, validar, marcar como usado e revogar a família |
| `kitchen-access/request.redis` | Criar pedido pendente, ler, listar por usuário e por cozinha, limpar IDs expirados |
| `kitchen-access/decide.redis` | Aprovar ou recusar |
| `product-queue/enqueue.redis` | Enfileirar cadastro |
| `product-queue/lease.redis` | Adquirir, renovar e liberar a concessão do consumer |
| `product-queue/recover.redis` | Reconstruir a lista do consumer a partir de `pending` |
| `product-queue/consume.redis` | Retirar o próximo ID (`BRPOP`), consultar pedido e DLQ |
| `product-queue/update.redis` | `PROCESSING`, `COMPLETED` ou `FAILED` (com DLQ) |
| `product-queue/quarantine.redis` | Payload inválido direto para a DLQ |
| `ranking/expiration.redis` | Publicar atomicamente e consultar o ranking de validade por cozinha |

**Atomicidade.** Nos arquivos que começam com "se ... para aqui" (`enqueue`, `recover`, `update`, `quarantine`, renovar/liberar em `lease` e `decide`), a API não manda os comandos um a um. Ela executa a sequência inteira de uma vez. Os scripts versionados estão em [`scripts/product-queue/`](../scripts/product-queue/) e [`scripts/ranking/`](../scripts/ranking/); a decisão de acesso continua no `DECIDE_SCRIPT` da API. É o que impede um consumer que perdeu a concessão de confirmar um item, dois supervisores de decidirem o mesmo pedido ou leitores de observarem um ranking parcial. Rodados manualmente, um por um, esses comandos **não** têm essa garantia; para corrigir dado em produção, prefira a API.

## O que não está no Redis

`LoginAttemptService`, `KitchenCodeLookupLimiter` e `KitchenDiscoveryLimiter` (limites de tentativa de login e de busca de cozinha) guardam contadores **em memória** da instância. Funciona com uma instância só (Render); com mais de uma, cada instância conta separado e o limite multiplica. Mover para o Redis seria um contador com `INCR` + `EXPIRE` por janela (`login:{chave}` 15 min, `kitchen-lookup:{ip}` 1 h, `kitchen-discovery:{ip}` 1 min).

## Operação

- **Eviction:** `maxmemory-policy noeviction`. Pedidos pendentes, histórico de acesso e DLQ não têm TTL; uma política `allkeys-*` apagaria dados. Com memória cheia o Redis recusa a escrita e a API responde 503.
- **Persistência:** AOF (`appendonly yes`, `appendfsync everysec`) + RDB. Na Aiven, conferir no console; localmente, [`config/redis.conf`](../config/redis.conf).
- **Backup:** o Redis guarda estado operacional, não o cadastro. A fonte da verdade continua no PostgreSQL; a perda do Redis derruba sessões (todos fazem login de novo), pedidos de acesso pendentes e jobs da fila ainda não processados.
- **Inspeção:** usar `SCAN` com padrão (`redis-cli --scan --pattern 'kar:kitchen:*'`), nunca `KEYS` em produção.
- **Mudanças:** chave nova, campo novo ou TTL diferente na API entra neste documento e no arquivo de `commands/` correspondente, no mesmo PR da API.
