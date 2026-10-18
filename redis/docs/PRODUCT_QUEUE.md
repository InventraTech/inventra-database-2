# INV2-25 — fila de cadastro de produtos

Este documento define o contrato Redis da fila FIFO usada pela API para processar cadastros por código de barras. A implementação da aplicação permanece no repositório da API; aqui ficam as estruturas e operações atômicas pertencentes ao banco.

## Contrato

O produtor adiciona o identificador do evento com `LPUSH` e o consumidor retira com `BRPOP`, preservando a ordem FIFO. O payload e o estado do processamento ficam separados da lista para permitir reprocessamento e auditoria.

As chaves oficiais estão descritas em [KEYSPACE.md](KEYSPACE.md). Os scripts Lua ficam em [`../scripts/product-queue/`](../scripts/product-queue/).

## Regras de confiabilidade

- O mesmo evento pode ser reenviado de forma idempotente, mas um novo evento com código de barras já ativo deve ser rejeitado antes do enfileiramento.
- O consumidor registra início, conclusão e falha do processamento; erros inesperados incluem a stack trace.
- Falhas transitórias de banco usam no máximo cinco tentativas, com backoff, antes do envio para a DLQ.
- Payload inválido ou corrompido é colocado em quarentena, sem bloquear os itens seguintes.
- A DLQ mantém no máximo 1.000 entradas e expira após sete dias.
- O lock usa token de fencing: somente o proprietário atual pode recuperar, atualizar ou liberar a fila.
- A confirmação é idempotente. Uma repetição após perda de resposta não recria nem processa novamente um trabalho já concluído.
- A autorização continua sendo responsabilidade da API; apenas usuários com acesso à cozinha podem produzir ou consultar tarefas.
- A migration de suporte da API usa a versão `V010`, evitando colisão com migrations existentes.

## Operações atômicas

| Script | Responsabilidade |
|---|---|
| `enqueue.lua` | Registra o evento e o coloca simultaneamente na lista e no conjunto de pendências. |
| `lease.lua` | Renova ou libera o lock somente quando o token informado é o proprietário. |
| `recover.lua` | Reconstrói a lista ativa a partir das pendências após reinício ou troca de consumidor. |
| `update.lua` | Atualiza o estado, remove a pendência e, quando necessário, envia para a DLQ com limite e TTL. |
| `quarantine.lua` | Isola payloads inválidos e remove a pendência de forma atômica. |

## Persistência e recuperação

O arquivo [`../config/redis.conf`](../config/redis.conf) mantém AOF habilitado. Ao assumir o lock, o consumidor executa a recuperação antes de voltar a consumir. Assim, eventos que estavam pendentes continuam disponíveis depois de uma reinicialização.

## Validação

[`../tests/check_scripts.sh`](../tests/check_scripts.sh) executa os scripts em Redis 7 real e cobre FIFO, recuperação, idempotência por token, quarentena, DLQ e TTL. Os testes de integração da API — incluindo concorrência, autorização e falhas de banco — permanecem no repositório da aplicação.
