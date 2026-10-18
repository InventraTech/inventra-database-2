# INV2-26 — ranking de validade de lotes

O ranking em tempo real prioriza lotes pela proximidade da data de validade. O Redis usa um Sorted Set, permitindo consulta ordenada e atualização concorrente sem leitura-modificação-escrita na aplicação.

## Modelo

- **Membro:** identificador do lote, serializado de forma estável.
- **Pontuação:** instante de validade normalizado pela API.
- **Ordem:** menor pontuação primeiro, isto é, lotes que vencem antes aparecem primeiro.
- **Desempate:** ordem lexicográfica do membro, comportamento nativo do Redis para pontuações iguais.

As chaves oficiais e seus placeholders estão em [KEYSPACE.md](KEYSPACE.md).

## Atualização atômica

A API monta o novo ranking em uma chave temporária com o mesmo hash tag da chave publicada. O script [`../scripts/ranking/replace.lua`](../scripts/ranking/replace.lua) valida todos os pares membro/pontuação, aplica o TTL e troca a chave temporária pela chave oficial com `RENAME`.

Isso garante que leitores vejam integralmente a versão anterior ou a nova, nunca um ranking parcialmente reconstruído. Se algum dado for inválido, o script falha antes da publicação e preserva o ranking vigente.

## Expiração

O ranking possui TTL renovado a cada publicação bem-sucedida. O valor é configurado pela aplicação e deve ser maior que zero. A chave temporária também recebe expiração defensiva para não deixar resíduos em caso de interrupção.

O exemplo em [`../commands/ranking/expiration.redis`](../commands/ranking/expiration.redis) demonstra criação, consulta e expiração.

## Consistência concorrente

Cada reconstrução usa uma chave temporária exclusiva. A publicação por Lua é atômica, e as chaves compartilham o mesmo hash tag para compatibilidade com Redis Cluster. Atualizações incrementais, quando usadas pela API, devem empregar `ZINCRBY`, que também é atômico.

## Validação

[`../tests/check_scripts.sh`](../tests/check_scripts.sh) executa o script em Redis 7 real e verifica ordenação, desempate, TTL, substituição integral e preservação do ranking diante de entrada inválida. Os testes de endpoint, autorização e integração PostgreSQL/Redis permanecem no repositório da API.
