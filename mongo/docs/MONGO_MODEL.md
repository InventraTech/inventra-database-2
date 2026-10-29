# Modelo MongoDB (`dbIAI`)

Banco de documentos da IA do Inventra ([`inventra-artificial-intelligence-2`](https://github.com/InventraTech/inventra-artificial-intelligence-2)). Guarda as conversas do chat, as métricas de cada requisição e as propostas de ação que esperam a aprovação do usuário. Não guarda o estoque: a IA consulta e altera o PostgreSQL pela API Spring.

| | |
|---|---|
| **Banco** | `dbIAI` (variável `MONGO_CONNECTION` na IAI) |
| **Coleções** | `sessions`, `metrics`, `approvals`, `notifications` (+ `schema_migrations`, controle desta esteira) |
| **Quem escreve** | `iai/app/core/assistant/memory.py` (sessions), `iai/app/core/infra/metrics.py` (metrics), `iai/app/core/inventra/approvals.py` (approvals) |
| **Contrato** | `$jsonSchema` em `schemas/*.schema.json`, aplicado por `migrations/V001__init_dbiai.js` e atualizado por `migrations/V002__approvals_kitchen_jev.js` |

## Por que documento e não tabela

Uma conversa é lida e escrita sempre inteira: o app abre a sessão, empilha mensagens e no fim gera um resumo. As mensagens não são consultadas fora da sessão e o formato delas muda com o grafo de agentes. Guardar a sessão como um documento com o array `messages` embutido evita join e migração a cada mudança do grafo. As métricas seguem o mesmo raciocínio: cada requisição gera um documento com listas de nós, de chamadas de LLM e de julgamentos do JEV, de tamanho variável. A proposta de ação é um documento só porque nasce imutável, carrega o retrato do estoque e a própria trilha de auditoria, e é lida e decidida inteira.

## `sessions`

Uma conversa de um usuário em uma cozinha. Fica **ativa** (`active = true`) até `POST /chat/encerrar`, que gera o resumo via LLM e fecha a sessão. Um `session_id` pode se repetir: cada encerramento separa uma sessão da próxima, e o índice único parcial garante no máximo uma sessão ativa por usuário + cozinha + `session_id`.

| Campo | Tipo | Regra |
|-------|------|-------|
| `_id` | string | UUID v4 gerado pela IAI; é o `doc_id` devolvido em `/chat/historico` |
| `session_id` | string | Identificador da conversa enviado pelo app |
| `user_id` | string | Dono da conversa. Deve ser o `tb_user.id_user` (UUID) do PostgreSQL |
| `kitchen_id` | int ≥ 1 | Cozinha da conversa; o histórico nunca atravessa cozinhas |
| `active` | bool | `true` = aberta; `/chat/encerrar` muda para `false` |
| `started_at` / `updated_at` | date | UTC |
| `summary` | string | Vazio enquanto a sessão está ativa |
| `messages[]` | array | `{role, content, confianca?}` |
| `messages[].role` | enum | `human` (usuário), `iai` (resposta final), `judge` (reprovação do juiz, só auditoria) |
| `messages[].content` | string | Texto **já anonimizado** pelo guardrail (e-mail, CPF, RG e telefone viram tokens) |
| `messages[].confianca` | number 0–1 | Só em `role = judge` |

```json
{
  "_id": "6f1c0a4e-6a51-4a3e-9d0c-1b7e2f9a8c11",
  "session_id": "app-3f9a1c2b7d4e",
  "user_id": "0b9c7f8e-2d1a-4c3b-9e8f-7a6b5c4d3e2f",
  "kitchen_id": 3,
  "active": false,
  "started_at": { "$date": "2026-10-10T13:02:11Z" },
  "updated_at": { "$date": "2026-10-10T13:05:40Z" },
  "summary": "Usuário consultou o estoque de tomate e os lotes que vencem na semana.",
  "messages": [
    { "role": "human", "content": "quantos kg de tomate temos?" },
    { "role": "iai", "content": "Há 12,5 kg de tomate em 2 lotes." }
  ]
}
```

## `metrics`

Um documento por requisição de `/chat`, gravado pelo `ColetorMetricas`. O texto do prompt e os argumentos das ferramentas **não** são guardados. `GET /metrics` agrega a janela de 7 ou 30 dias da cozinha do usuário.

| Campo | Tipo | Regra |
|-------|------|-------|
| `timestamp` | date | Momento da requisição (UTC) |
| `session_id`, `user_id` | string | Mesmos valores da sessão |
| `kitchen_id` | int ≥ 1 | Cozinha da requisição |
| `latencia_total_ms` | number ≥ 0 | Já inclui o tempo do JEV, que roda dentro do nó do especialista |
| `status` | enum | `ok`, `bloqueado` (guardrail de entrada recusou, não é erro), `erro` (exceção ou JEV indisponível numa escrita) |
| `nos[]` | array | `{no, ms, erro}` por nó do grafo |
| `chamadas[]` | array | `{modelo, tokens_entrada, tokens_saida, custo_usd, latencia_ms}` por chamada de LLM (Gemini e Groq) |
| `jev[]` | array | Um item por julgamento do JEV no turno (cada proposta `propor_*` e a resposta final): `agent`, `tool` (`resposta_final` quando julga o texto), `attempt`, `decision`, `checks`, `failed_checks`, `duration_ms`, `model`, `usage`, `custo_usd`, `error_type` |
| `jev_events[]` | array | Linha do tempo técnica dos julgamentos (`jev_revisao_aprovada`, `jev_revisao_reprovada`, `validacao_local_*`), sem argumentos nem conversa |
| `tokens_entrada`, `tokens_saida` | int ≥ 0 | Soma de `chamadas[]` mais os tokens informados pelo JEV |
| `custo_usd` | number ≥ 0 | LLMs (`chamadas[]`) mais o JEV (`jev[].custo_usd`) |
| `erros_componentes[]` | string[] | `llm:*`, `tool:*`, `chain:*`, `jev:*`, inclusive os recuperados por fallback |
| `resolvida` | bool | Execução autorizada concluída ou FAQ respondida; bloqueio e erro nunca contam |
| `agentes_chamados[]` | string[] | Ex.: `guardrail_insulto`, `estoquista`, `jev`, `faq` (o motivo depois dos dois pontos é descartado) |
| `llm_mode`, `error_type` | string | Modo da IAI e tipo da exceção quando `status = erro` |

O preço do JEV usado em `jev[].custo_usd` vem de `PRECO_JEV_USD_POR_MILHAO` na IAI (US$ 0,042 por milhão de tokens de entrada, saída não cobrada) e deve ser conferido com a TypeSafe.

## `approvals`

Proposta de ação sobre o estoque (human-in-the-loop). Toda escrita da IA nasce aqui como `AGUARDANDO_APROVACAO`; **nada muda no estoque até o próprio solicitante aprovar**, em outra requisição. O documento é imutável (`proposal_hash` cobre `action`, `requester`, `before` e `justification`) e a trilha de auditoria fica embutida em `audit[]`, que só cresce.

| Campo | Tipo | Regra |
|-------|------|-------|
| `_id` | string | SHA-256 de `[user_id, kitchen_id, idempotency_key]`; repetir a mesma proposta devolve o mesmo documento |
| `requester_id`, `kitchen_id` | string, int | Quem pediu (e o único que aprova) e a cozinha |
| `idempotency_key` | string | `sha256(turn_id:impressão da ação)`; um novo turno gera outra chave |
| `action` | object | `{operation, parameters}`, já validados; números viram texto decimal |
| `requester` | object | Identidade no momento da proposta: `user_id`, `kitchen_id`, `role`, `name`, `mocked` |
| `before[]` | array | `{parameter, record}`: retrato dos registros da API Spring; a execução revalida e recusa se algo mudou |
| `justification` | string | Motivo informado pelo especialista |
| `proposal_hash` | string | SHA-256 hexadecimal; a decisão precisa repeti-lo |
| `status` | enum | `AGUARDANDO_APROVACAO`, `APROVADA_PENDENTE_INTEGRACAO`, `EM_EXECUCAO`, `CONCLUIDA`, `RECUSADA`, `FALHOU`, `EXPIRADA`, `RESULTADO_INCERTO` |
| `created_at` / `expires_at` | date | A proposta expira 7 dias depois |
| `decided_by`, `decision`, `decision_reason`, `decided_at` | | `null` enquanto aguarda; `decision` é `approve` ou `reject` |
| `judge_cancelled` | bool | `true` = o JEV reprovou a proposta antes de ela chegar ao usuário. Fica `RECUSADA` com `decided_by = juiz` só para auditoria e some das listas |
| `execution_started_at`, `executed_at`, `result`, `execution_error`, `exception_type` | | Preenchidos na execução. `RESULTADO_INCERTO` nunca é repetido automaticamente |
| `technical_executor`, `business_mode`, `confirmation_policy`, `notification` | | `iai`, `spring` ou `mock`, `requester` e o canal de aviso |
| `audit[]` | array | `{event, at, actor}`: `PROPOSTA_CRIADA`, `APROVADA_PENDENTE_INTEGRACAO`, `RECUSADA`, `CANCELADA_PELO_JUIZ`, `EM_EXECUCAO`, `CONCLUIDA`, `FALHOU`, `EXPIRADA`, `RESULTADO_INCERTO` |

```json
{
  "_id": "9a3f...e1",
  "requester_id": "0b9c7f8e-2d1a-4c3b-9e8f-7a6b5c4d3e2f",
  "kitchen_id": 3,
  "idempotency_key": "4c1d...b7",
  "action": { "operation": "desativar_produto", "parameters": { "productId": 7 } },
  "requester": { "user_id": "0b9c7f8e-2d1a-4c3b-9e8f-7a6b5c4d3e2f", "kitchen_id": 3, "role": "SUPERVISOR", "name": "Davi", "mocked": false },
  "before": [{ "parameter": "productId", "record": { "id": 7, "active": true } }],
  "justification": "Produto descontinuado pelo fornecedor.",
  "proposal_hash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "status": "AGUARDANDO_APROVACAO",
  "created_at": { "$date": "2026-10-29T06:20:00Z" },
  "expires_at": { "$date": "2026-11-05T06:20:00Z" },
  "decided_by": null, "decision": null, "decided_at": null,
  "audit": [{ "event": "PROPOSTA_CRIADA", "at": { "$date": "2026-10-29T06:20:00Z" }, "actor": "0b9c7f8e-2d1a-4c3b-9e8f-7a6b5c4d3e2f" }]
}
```

## `notifications`

Caixa de entrada por cozinha. A IAI cria o índice no startup, mas **ainda não grava nesta coleção** (hoje o aviso de proposta é o campo `notification` de `approvals`). Existe sem validador até o formato dos documentos ser definido.

## Coleções só do modo demonstração

Com `IAI_BUSINESS_MODE=mock`, a IAI também usa `business_mock`, `execution_mock` e `mock_counters` para simular o estoque. São dados de exemplo, sem contrato aqui, e não existem em produção.

## Índices

| Coleção | Índice | Consulta atendida |
|---------|--------|-------------------|
| `sessions` | `user_id_1_kitchen_id_1_session_id_1_active_1` (único, parcial `active = true`) | Sessão ativa de um usuário na cozinha (`doc_id_da_sessao`); impede duas ativas iguais em criação concorrente |
| `sessions` | `user_id_1_kitchen_id_1_started_at_-1` | Histórico do usuário na cozinha, mais recente primeiro (`recuperar_historico`, tool `buscar_historico`) |
| `approvals` | `requester_id_1_kitchen_id_1_idempotency_key_1` (único) | Idempotência: a mesma proposta no mesmo turno não duplica |
| `approvals` | `status_1_expires_at_1` | Expiração das propostas pendentes (`expire_pending`) |
| `notifications` | `kitchen_id_1_created_at_-1` | Caixa de entrada da cozinha |
| `metrics` | `kitchen_id_1_timestamp_-1` | Janela de `GET /metrics` por cozinha |

Os nomes seguem o padrão do driver porque a IAI também chama `create_index` no startup. Se o nome (ou as opções) fosse outro para a mesma chave, o MongoDB recusaria o índice da aplicação. A V002 troca os índices da V001 (`session_id_1`, `user_id_1_started_at_-1`, `timestamp_-1`), porque toda consulta da IAI passou a filtrar por cozinha.

## Validação

As coleções `sessions`, `metrics` e `approvals` têm validador `$jsonSchema` com `validationLevel: moderate` e `validationAction: warn`:

- campo a mais é sempre aceito (o schema não usa `additionalProperties: false`);
- documento fora do contrato é **gravado** e o `mongod` registra um aviso no log. A IAI grava o chat no meio da resposta, e um campo renomeado não pode derrubar a conversa antes de o contrato ser atualizado aqui;
- para auditar, a mesma consulta que o seed usa no final lista o que está fora do contrato:

```js
const v = db.getCollectionInfos({ name: 'metrics' })[0].options.validator;
db.metrics.find({ $nor: [v] });
```

Documentos anteriores à V002 (sem `kitchen_id` ou `active`) continuam gravados, mas a IAI só enxerga documentos da cozinha do usuário. Fazer backfill deles é decisão de produto e fica fora da migration.

Quando o formato estabilizar, a troca para `validationAction: error` é uma migration nova com `collMod`.

## Retenção e privacidade

- Nenhuma coleção tem TTL. As sessões são o histórico de longo prazo da IA (a tool `buscar_historico` lê os resumos), e as propostas continuam disponíveis para auditoria, inclusive as expiradas e as canceladas pelo juiz.
- `metrics` cresce um documento por mensagem e `GET /metrics` só lê 30 dias. Uma retenção (ex.: 90 dias) exige um índice TTL em `timestamp` sozinho; o índice atual é composto com `kitchen_id` e não serve para TTL. Fica como decisão do time, em migration própria.
- `content` já chega anonimizado. `approvals.requester.name` e `user_id` são os identificadores pessoais. A exclusão de um usuário no PostgreSQL deve ser acompanhada de `deleteMany({ user_id })` em `sessions` e `metrics` e `deleteMany({ requester_id })` em `approvals`.
- `approvals.before[].record` guarda um retrato de registros da API (produtos, lotes, fornecedores) da cozinha; não contém conversa.

## Esteira

| Pasta | Papel |
|-------|-------|
| `schemas/` | Contrato de cada coleção em JSON Schema (dicionário). `rollback/remove_validators.js` tira os validadores sem apagar dados |
| `indexes/` | `create_indexes.js` (dicionário, um `createIndex` por linha porque `scripts/workspace/build.py` lê por linha) + `rollback/drop_indexes.js` |
| `migrations/` | `V001__init_dbiai.js` (sessions e metrics) e `V002__approvals_kitchen_jev.js` (cozinha, JEV, approvals, notifications), idempotentes (`createCollection` ou `collMod`; `createIndex` não duplica). `rollback/drop_everything.js` apaga as coleções |
| `seeds/` | `seed.ipynb`: conversas, métricas e propostas fictícias, com `user_id` lidos de `tb_user` quando o PostgreSQL está no `.env` |
| `tests/` | `check_migrations.sh`: aplica 2×, valida contrato e índices (inclusive unicidade), compara dicionário × migrations, rollback e reaplica |

Cada migration aplicada é registrada em `schema_migrations` (`_id = 'V001'`, `'V002'`, com `applied_at`).

```bash
cd mongo
for f in migrations/V*.js; do mongosh "$MONGO_CONNECTION" --file "$f"; done
```

`MONGO_DB` muda o banco alvo (padrão `dbIAI`). Os testes usam `dbIAI_ci` e apagam as coleções: nunca rodar contra o banco real.
