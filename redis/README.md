# Redis da Inventra

Este diretório reúne somente os artefatos de banco necessários às entregas INV2-24, INV2-25 e INV2-26. A implementação Java que consome estes contratos permanece no repositório da API.

## Entregas

- **INV2-24 — integração:** configuração persistente do Redis, convenções de chaves e comandos de validação.
- **INV2-25 — fila de produtos:** contrato FIFO, scripts Lua atômicos, recuperação, quarentena e dead-letter queue.
- **INV2-26 — ranking:** contrato do Sorted Set, atualização atômica e expiração do ranking.

## Estrutura

- `config/redis.conf`: persistência e configuração do servidor.
- `commands/`: exemplos executáveis por funcionalidade.
- `scripts/product-queue/`: operações atômicas da fila.
- `scripts/ranking/`: publicação atômica do ranking.
- `docs/`: contratos, chaves, decisões e operação.
- `tests/`: verificações executadas pelo CI.

## Validação local

Com Docker e Bash disponíveis, execute a partir da raiz do repositório:

```bash
bash redis/tests/check_keyspace_sync.sh
bash redis/tests/check_config.sh
bash redis/tests/check_scripts.sh
```

Os testes usam uma instância descartável do Redis 7. Nenhuma credencial é necessária.
