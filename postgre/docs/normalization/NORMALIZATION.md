# Normalização do Modelo

Demonstração de que o banco do Inventra está normalizado até a **3ª Forma Normal (3FN)**. Também atende à Forma Normal de Boyce-Codd (FNBC) e não precisa de decomposição para a 4FN nem para a 5FN. Cobre o schema de `V001` a `V014`.

## 1. Resumo

| Forma normal | Situação | Onde está a prova |
|--------------|----------|-------------------|
| 1FN | ✅ Atende (exceto as tabelas de log, que guardam o retrato da linha em JSON de propósito) | [Seção 4.1](#41-primeira-forma-normal-1fn) |
| 2FN | ✅ Atende: as 4 tabelas de chave composta não têm dependência parcial | [Seção 4.2](#42-segunda-forma-normal-2fn) |
| 3FN | ✅ Atende, com 5 **redundâncias controladas** documentadas, protegidas pelo próprio banco e verificáveis | [Seções 4.3](#43-terceira-forma-normal-3fn) e [5](#5-redundâncias-controladas) |
| FNBC | ✅ Atende: todo determinante é chave candidata | [Seção 4.4](#44-forma-normal-de-boyce-codd-fnbc) |
| 4FN e 5FN | ✅ Atende: não há fatos multivalorados independentes nem associação ternária decomponível | [Seção 4.5](#45-quarta-e-quinta-formas-normais-4fn-e-5fn) |

Ficam **fora** da análise, por decisão de projeto:
- **Data Mart** (`dim_*`, `fact_*`): é desnormalizado de propósito (star schema para BI), mas são views sobre as tabelas normalizadas e não guardam dado próprio;
- **Tabelas de log** (`tb_log_*`): veja a [seção 6](#6-fora-do-escopo-da-normalização).

## 2. Método

Para cada tabela, listamos as **chaves candidatas** e as **dependências funcionais (DF)** `X → Y`: um valor de `X` determina um único valor de `Y`. A partir delas, cada forma normal é verificada assim:

| Forma | Regra verificada |
|-------|------------------|
| 1FN | Todo atributo é atômico; não há grupo repetido nem lista dentro de uma coluna |
| 2FN | 1FN, e nenhum atributo não-chave depende de **parte** de uma chave composta |
| 3FN | 2FN, e nenhum atributo não-chave depende de **outro atributo não-chave** (dependência transitiva) |
| FNBC | Em toda DF `X → Y` não trivial, `X` é chave candidata |
| 4FN | FNBC, e não há duas dependências multivaloradas independentes na mesma tabela |
| 5FN | 4FN, e a tabela não pode ser decomposta em tabelas menores e reconstruída por junção sem perda |

**Notação:** `PK` é a chave primária; `CC` são outras chaves candidatas (colunas `UNIQUE NOT NULL`, ou `UNIQUE` que identificam a linha quando preenchidas).

## 3. Dependências funcionais por tabela

Em todas as tabelas abaixo, a única DF é **chave → demais colunas**, exceto onde indicado. Isso é o que torna o modelo 3FN e FNBC.

### Cadastros

| Tabela | PK | CC | Dependências funcionais | Observação |
|--------|----|----|-------------------------|------------|
| `tb_profile` | `id_profile` | `access_type` | `id_profile → access_type, description` | |
| `tb_kitchen` | `id_kitchen` | `code` | `id_kitchen → name, code, address, city, state, latitude, longitude, accepting_requests, active, created_at` | `city ↛ state` (há cidades homônimas em UFs diferentes), por isso a UF fica na própria cozinha |
| `tb_category` | `id_category` | `name` | `id_category → name, description` | |
| `tb_measurement_unit` | `id_unit` | `symbol` | `id_unit → symbol, description` | |
| `tb_product` | `id_product` | `barcode` (quando informado) | `id_product → name, brand, id_category, id_unit, barcode, photo_url, active, created_at` | `brand ↛ id_category`: uma marca pode ter produtos em categorias diferentes, então a marca não vira tabela com categoria própria |
| `tb_supplier` | `id_supplier` | `cnpj` | `id_supplier → legal_name, cnpj, email, whatsapp, rating, active, created_at` | |
| `tb_user` | `id_user` | `email`, `firebase_uid` (quando informado) | `id_user → name, email, password_hash, firebase_uid, photo_url, id_kitchen, id_profile, active, last_login, created_at` | O nome do perfil e o da cozinha **não** são repetidos aqui: ficam em `tb_profile` e `tb_kitchen` |

### Associativas (N:N)

| Tabela | PK | Dependências funcionais |
|--------|----|-------------------------|
| `tb_product_supplier` | `(id_product, id_supplier)` | `(id_product, id_supplier) → supplier_code, reference_price, lead_time_days` |
| `tb_product_kitchen_parameter` | `(id_product, id_kitchen)` | `(id_product, id_kitchen) → min_stock, max_stock, average_daily_consumption` |
| `tb_alert_read` | `(id_alert, id_user)` | `(id_alert, id_user) → read_at` |

### Movimentação e eventos

| Tabela | PK | Dependências funcionais | Observação |
|--------|----|-------------------------|------------|
| `tb_stock_batch` | `id_batch` | `id_batch → id_product, id_kitchen, id_supplier, batch_number, invoice_number, initial_quantity, current_quantity, entry_date, expiration_date, unit_price, status` | `current_quantity`: [R2](#r2-saldo-do-lote-current_quantity) |
| `tb_requisition` | `id_requisition` | `id_requisition → requisition_type, origin, status, reason, id_kitchen, id_requester_user, id_approver_user, created_at, approved_at` | |
| `tb_requisition_item` | `id_requisition_item` | `id_requisition_item → id_requisition, id_product, id_suggested_supplier, quantity, estimated_price, note` | `estimated_price` é retrato do momento: veja a [seção 5.1](#51-retratos-históricos-não-são-redundância) |
| `tb_pre_list` | `id_pre_list` | `id_pre_list → list_date` | |
| `tb_pre_list_item` | `id_pre_list_item` | `id_pre_list_item → id_pre_list, id_supplier, id_product, quantity` | O fornecedor fica no item (não em `tb_product`) porque a mesma lista pode comprar o mesmo produto de fornecedores diferentes |
| `tb_inventory` | `id_inventory` | `id_inventory → id_kitchen, id_responsible_user, started_at, closed_at, status, note` | |
| `tb_inventory_count` | `id_count` | `id_count → id_inventory, id_batch, registered_quantity, physical_quantity, divergence` e `(physical_quantity, registered_quantity) → divergence` | `divergence`: [R1](#r1-divergência-do-inventário-divergence) |
| `tb_stock_movement` | `id_movement` | `id_movement → id_batch, id_user, id_requisition, type, reason, quantity, balance_after, created_at` | `balance_after`: [R3](#r3-saldo-após-a-movimentação-balance_after) |
| `tb_alert` | `id_alert` | `id_alert → type, severity, id_batch, id_product, id_kitchen, id_user, id_target_profile, ref_key, message, is_read, created_at` e, quando há lote, `id_batch → id_product, id_kitchen` | [R4](#r4-produto-e-cozinha-no-alerta-com-lote) e [R5](#r5-dois-modelos-de-leitura-de-alerta) |
| `tb_user_daily_access` | `(id_user, access_date)` | `(id_user, access_date) → first_access_time, last_access_time, access_count` | Guarda só a **hora** do primeiro e do último acesso: com `TIMESTAMP`, valeria `first_access_at → access_date`, um determinante que não é chave (fora da FNBC) |
| `tb_ui_click_counter` | `id_counter` (sempre 1) | `id_counter →` cada contador | **Exceção consciente à 1FN**: as colunas contadoras são um grupo repetido (uma por coisa clicável). É de propósito: o produto precisa só do total de cliques de cada botão, com `UPDATE coluna = coluna + 1`, sem histórico. Como a tabela tem uma linha só, não há redundância nem anomalia de atualização. Custo: elemento novo = `ADD COLUMN` |

### Governança

| Tabela | PK | CC | Dependências funcionais |
|--------|----|----|-------------------------|
| `tb_catalog_access_level` | `id_access_level` | `code`, `level_rank` | `id_access_level → code, level_rank, description, audience` |
| `tb_catalog_table` | `id_catalog_table` | `table_name` | `id_catalog_table → table_name, domain, description, business_rules, id_access_level, data_owner, created_at, updated_at` |
| `tb_catalog_column` | `id_catalog_column` | `(id_catalog_table, column_name)` | `id_catalog_column → id_catalog_table, column_name, description, business_rule, id_access_level, is_personal_data, updated_at` |
| `tb_backup_history` | `id_backup` | | `id_backup → operation, status, database_name, file_name, file_size_bytes, checksum_sha256, started_at, finished_at, executed_by, error_message` |

No catálogo, foram evitadas duas redundâncias que seriam tentadoras:
- **tipo, nulidade, PK e FK das colunas:** já estão no `pg_catalog` do PostgreSQL, e as views lêem de lá;
- **"a tabela contém dado pessoal":** é calculado a partir das colunas em `vw_data_catalog_table`.

## 4. Verificação por forma normal

### 4.1 Primeira forma normal (1FN)

- **Valores atômicos:** nenhuma coluna guarda lista, conjunto ou valores separados por vírgula. O que seria multivalorado virou tabela própria:
  - os fornecedores de um produto estão em `tb_product_supplier`;
  - os itens de uma requisição, em `tb_requisition_item`;
  - quem leu um alerta, em `tb_alert_read`;
  - as contagens de um inventário, em `tb_inventory_count`.
- **Sem grupos repetidos:** não há colunas como `fornecedor_1`, `fornecedor_2`. A quantidade de qualquer coisa "por produto" ou "por requisição" é ilimitada.
- **Toda tabela tem chave primária**, e nenhuma linha se repete.
- **Endereço** (`tb_kitchen.address`) fica numa coluna só porque o sistema o usa inteiro, apenas para exibir. Cidade, UF e coordenadas, que são usadas em filtros e na busca por proximidade, já são colunas separadas.

**Exceção consciente:** `tb_log_base.previous_data` e `new_data` são `JSONB`. Veja a [seção 6](#6-fora-do-escopo-da-normalização).

### 4.2 Segunda forma normal (2FN)

A 2FN só pode ser violada em tabela com **chave composta**. São quatro, e em nenhuma um atributo depende só de parte da chave:

| Tabela | Atributo | Depende de | Por que não de parte da chave |
|--------|----------|------------|--------------------------------|
| `tb_product_supplier` | `supplier_code`, `reference_price`, `lead_time_days` | `(id_product, id_supplier)` | O preço e o prazo são da **combinação**: o mesmo produto tem preço diferente em cada fornecedor, e o mesmo fornecedor, em cada produto. O nome do produto e a razão social do fornecedor, que dependeriam de só uma parte, ficam em `tb_product` e `tb_supplier` |
| `tb_product_kitchen_parameter` | `min_stock`, `max_stock`, `average_daily_consumption` | `(id_product, id_kitchen)` | O estoque mínimo de arroz numa cozinha é diferente do de outra cozinha |
| `tb_alert_read` | `read_at` | `(id_alert, id_user)` | É o momento em que **aquela pessoa** leu **aquele alerta** |
| `tb_user_daily_access` | `first_access_time`, `last_access_time`, `access_count` | `(id_user, access_date)` | São os acessos **daquela pessoa** **naquele dia**; o nome e a cozinha do usuário ficam em `tb_user` |

As demais tabelas têm chave simples (`id_*`), então estão automaticamente em 2FN.

### 4.3 Terceira forma normal (3FN)

Nenhum atributo não-chave depende de outro atributo não-chave. A forma de garantir isso foi **guardar só a FK e buscar o dado da outra tabela por junção**:

| Em vez de guardar... | ...o modelo guarda | E busca em |
|----------------------|--------------------|------------|
| nome da categoria e símbolo da unidade no produto | `id_category`, `id_unit` | `tb_category`, `tb_measurement_unit` |
| nome do perfil e da cozinha no usuário | `id_profile`, `id_kitchen` | `tb_profile`, `tb_kitchen` |
| nome do produto, da cozinha e do fornecedor no lote | `id_product`, `id_kitchen`, `id_supplier` | tabelas de cadastro |
| nome de quem pediu e de quem aprovou na requisição | `id_requester_user`, `id_approver_user` | `tb_user` |
| cozinha do inventário em cada contagem | `id_inventory` | `tb_inventory` |
| nível de acesso por extenso no catálogo | `id_access_level` | `tb_catalog_access_level` |

As views (`vw_*`, `dim_*`) fazem essas junções para quem consulta, sem repetir o dado nas tabelas.

Os casos em que uma coluna **poderia** ser calculada a partir de outras estão listados na [seção 5](#5-redundâncias-controladas). São redundâncias assumidas, mantidas pelo próprio banco e verificáveis.

### 4.4 Forma normal de Boyce-Codd (FNBC)

A FNBC exige que todo determinante seja chave candidata. Os determinantes do modelo são:

- as PKs (`id_*` e as chaves compostas das associativas);
- as chaves candidatas naturais, protegidas por `UNIQUE`: `email` e `firebase_uid` (usuário), `code` (cozinha), `cnpj` (fornecedor), `barcode` (produto), `name` (categoria), `symbol` (unidade), `access_type` (perfil), `table_name` (catálogo).

Como as chaves naturais também são chaves candidatas, ter `cnpj → legal_name` ao lado de `id_supplier → legal_name` não viola a FNBC. As únicas exceções são as DFs das redundâncias R1 e R4 da seção 5.

### 4.5 Quarta e quinta formas normais (4FN e 5FN)

A 4FN e a 5FN tratam de tabelas que juntam **três ou mais entidades** numa chave só. O caso típico no domínio seria uma tabela `(produto, fornecedor, cozinha)`, para dizer "quem fornece o quê para onde". Nela, os fornecedores de um produto e as cozinhas que o usam seriam fatos independentes. Cada fornecedor novo exigiria uma linha para **cada** cozinha (dependência multivalorada, que viola a 4FN).

O modelo evita isso separando as duas relações:
- `tb_product_supplier` diz **quem fornece** cada produto;
- `tb_product_kitchen_parameter` diz **onde** cada produto é controlado.

As duas são **binárias**: não há tabela associativa com três chaves estrangeiras na chave primária. Por isso:
- **4FN:** não existem duas dependências multivaloradas independentes na mesma tabela;
- **5FN:** nenhuma tabela pode ser quebrada em projeções menores e reconstruída por junção, porque as associativas já são as projeções mínimas.

`tb_stock_batch` liga produto, cozinha e fornecedor, mas não é uma associação: cada lote é um **fato próprio**, com quantidade, validade e nota fiscal, e tem chave própria (`id_batch`).

## 5. Redundâncias controladas

São colunas que poderiam ser calculadas a partir de outras e foram guardadas por desempenho ou histórico. Todas são mantidas pelo **próprio banco** (trigger ou procedure). Nenhuma é preenchida à mão, e todas podem ser conferidas com [`normalization_checks.sql`](normalization_checks.sql).

### R1. Divergência do inventário (`divergence`)

- **Redundância:** `tb_inventory_count.divergence = physical_quantity - registered_quantity` é uma DF entre atributos não-chave (dependência transitiva).
- **Por que existe:** os relatórios de inventário filtram e ordenam por divergência, e a coluna evita recalcular em toda consulta.
- **Quem mantém:** `trg_calculate_divergence` recalcula em **todo** `INSERT` e `UPDATE` da linha. Um valor escrito à mão em `divergence` é sobrescrito pelo cálculo.
- **Histórico:** até a `V011`, a trigger só disparava quando `registered_quantity` ou `physical_quantity` mudavam, e um `UPDATE` só de `divergence` passava sem recálculo. A `V012` passou a disparar em qualquer `UPDATE` e recalculou as linhas existentes.
- **Alternativa avaliada:** coluna gerada (`GENERATED ALWAYS AS (physical_quantity - registered_quantity) STORED`). Não foi adotada porque a API (`InventoryService.registerCount`) envia `divergence` no `INSERT`, e a coluna gerada recusaria esse valor; seria preciso mudar a entidade JPA junto. A trigger dá a mesma garantia sem mexer na API.

### R2. Saldo do lote (`current_quantity`)

- **Redundância:** desde a `V007`, o saldo pode ser reconstruído a partir de `initial_quantity` e das linhas de `tb_stock_movement`.
- **Por que existe:** é o dado mais consultado do sistema (estoque atual, alertas, baixas). Somar o histórico a cada leitura seria caro, e as regras de saldo não negativo e de status dependem dele.
- **Quem mantém:** `sp_register_stock_entry`, `sp_write_off_stock` e `sp_cancel_requisition` atualizam o saldo **e** gravam a movimentação na mesma transação. O ajuste de saldo da API (inclusive no fechamento de inventário) grava a movimentação `ADJUSTMENT` correspondente. `trg_validate_stock` impede saldo negativo.

### R3. Saldo após a movimentação (`balance_after`)

- **Redundância:** `tb_stock_movement.balance_after` é igual ao saldo anterior do lote mais (ou menos) a quantidade movimentada.
- **Por que existe:** é um **retrato** para auditoria. Ele mostra qual era o saldo naquele instante, mesmo que movimentações posteriores sejam estornadas.
- **Quem mantém:** as mesmas procedures da R2, na mesma transação.

### R4. Produto e cozinha no alerta com lote

- **Redundância:** quando `tb_alert.id_batch` está preenchido, `id_batch → id_product, id_kitchen` (dependência transitiva).
- **Por que existe:** o alerta `STOCK` (estoque mínimo) não tem lote; só tem produto e cozinha. Manter as duas colunas em todos os alertas permite que a API e as views filtrem alertas por cozinha e produto do mesmo jeito, sem tratar os tipos separadamente.
- **Quem mantém:** `trg_alert_batch_consistency` (desde a `V012`), em todo `INSERT` e em `UPDATE` de `id_batch`, `id_product` ou `id_kitchen`. Quando há lote:
  - produto ou cozinha **vazios** são preenchidos com os do lote;
  - produto ou cozinha **diferentes** dos do lote são recusados com erro.

  As functions e procedures de alerta já copiavam do lote. A API recusa lote de outra cozinha ou de outro produto, mas aceitava um alerta com lote e **sem** produto, que agora é completado pela trigger.
- **Histórico:** antes da `V012`, nenhuma constraint garantia a regra. A `V012` corrigiu os alertas existentes a partir do lote; as correções ficam registradas em `tb_log_alert`.

### R5. Dois modelos de leitura de alerta

- **Redundância:** `tb_alert.is_read` (alerta lido por alguém) convive com `tb_alert_read` (leitura por pessoa, desde a `V008`).
- **Por que existe:** compatibilidade. O app antigo marca o alerta inteiro como lido, e o novo registra a leitura de cada pessoa. A regra "alerta aberto = `is_read = false` **e** nenhuma linha em `tb_alert_read`" considera os dois.
- **Melhoria possível:** quando o app antigo for desligado, migrar os `is_read = true` para `tb_alert_read` e remover a coluna.

### 5.1 Retratos históricos não são redundância

Estas colunas **parecem** repetir dado de outra tabela, mas guardam o valor **daquele momento**. Recalcular daria um resultado errado:

| Coluna | Parece repetir | Por que é outro fato |
|--------|----------------|----------------------|
| `tb_stock_batch.unit_price` | `tb_product_supplier.reference_price` | Preço efetivamente pago naquela nota; o de referência muda com o tempo |
| `tb_requisition_item.estimated_price` | `tb_product_supplier.reference_price` | Estimativa no dia do pedido |
| `tb_inventory_count.registered_quantity` | `tb_stock_batch.current_quantity` | Saldo do sistema **no momento da contagem**; o saldo do lote continua mudando depois |
| `tb_stock_batch.status` | `current_quantity` e `expiration_date` | Só em parte: `CANCELLED` é decisão de negócio, e `EXPIRED` só é aplicado pelo job diário |

## 6. Fora do escopo da normalização

**Tabelas de auditoria** (`tb_log_base` e as 7 `tb_log_*`): `previous_data` e `new_data` guardam a linha inteira em `JSONB`, o que não é atômico (1FN). É proposital:
- o log é um **registro histórico imutável**, só de inserção, e não participa das transações de negócio;
- um retrato em JSON continua válido mesmo depois que a tabela auditada ganha ou perde colunas;
- é isso que permite `sp_restore_from_audit` reconstruir a linha como ela era.

As colunas comuns ficam uma vez só em `tb_log_base`, e as filhas herdam (`INHERITS`), em vez de repetir a estrutura 7 vezes.

**Data Mart** (`dim_product`, `dim_kitchen`, `dim_supplier`, `dim_date`, `fact_*`): o star schema repete atributos de propósito, para o BI fazer menos junções. Como são **views**, a fonte continua única e normalizada. Veja [`VIEWS_AND_DATAMART.md`](../VIEWS_AND_DATAMART.md).

## 7. Relacionamentos e cardinalidades

Todos os relacionamentos usam `FOREIGN KEY` declarada no banco. "Obrigatório" significa FK `NOT NULL`, e "opcional", FK que aceita nulo.

| Lado 1 | Lado N | Cardinalidade | FK | Participação |
|--------|--------|---------------|----|--------------|
| `tb_profile` | `tb_user` | 1:N | `tb_user.id_profile` | Obrigatória |
| `tb_kitchen` | `tb_user` | 1:N | `tb_user.id_kitchen` | Opcional (usuário ainda sem cozinha) |
| `tb_category` | `tb_product` | 1:N | `tb_product.id_category` | Opcional |
| `tb_measurement_unit` | `tb_product` | 1:N | `tb_product.id_unit` | Obrigatória |
| `tb_product` ↔ `tb_supplier` | via `tb_product_supplier` | **N:N** | `id_product`, `id_supplier` | Obrigatória nas duas pontas |
| `tb_product` ↔ `tb_kitchen` | via `tb_product_kitchen_parameter` | **N:N** | `id_product`, `id_kitchen` | Obrigatória nas duas pontas |
| `tb_product` | `tb_stock_batch` | 1:N | `tb_stock_batch.id_product` | Obrigatória |
| `tb_kitchen` | `tb_stock_batch` | 1:N | `tb_stock_batch.id_kitchen` | Obrigatória |
| `tb_supplier` | `tb_stock_batch` | 1:N | `tb_stock_batch.id_supplier` | Opcional |
| `tb_kitchen` | `tb_requisition` | 1:N | `tb_requisition.id_kitchen` | Obrigatória |
| `tb_user` | `tb_requisition` (solicitante) | 1:N | `tb_requisition.id_requester_user` | Obrigatória |
| `tb_user` | `tb_requisition` (aprovador) | 1:N | `tb_requisition.id_approver_user` | Opcional (preenchida na decisão) |
| `tb_requisition` | `tb_requisition_item` | 1:N | `tb_requisition_item.id_requisition` | Obrigatória |
| `tb_product` | `tb_requisition_item` | 1:N | `tb_requisition_item.id_product` | Obrigatória |
| `tb_supplier` | `tb_requisition_item` | 1:N | `tb_requisition_item.id_suggested_supplier` | Opcional |
| `tb_pre_list` | `tb_pre_list_item` | 1:N | `tb_pre_list_item.id_pre_list` | Obrigatória |
| `tb_product` | `tb_pre_list_item` | 1:N | `tb_pre_list_item.id_product` | Obrigatória |
| `tb_supplier` | `tb_pre_list_item` | 1:N | `tb_pre_list_item.id_supplier` | Obrigatória |
| `tb_kitchen` | `tb_inventory` | 1:N | `tb_inventory.id_kitchen` | Obrigatória |
| `tb_user` | `tb_inventory` | 1:N | `tb_inventory.id_responsible_user` | Obrigatória |
| `tb_inventory` | `tb_inventory_count` | 1:N | `tb_inventory_count.id_inventory` | Obrigatória |
| `tb_stock_batch` | `tb_inventory_count` | 1:N | `tb_inventory_count.id_batch` | Obrigatória |
| `tb_stock_batch` | `tb_stock_movement` | 1:N | `tb_stock_movement.id_batch` | Obrigatória |
| `tb_user` | `tb_stock_movement` | 1:N | `tb_stock_movement.id_user` | Opcional (movimentação do sistema) |
| `tb_requisition` | `tb_stock_movement` | 1:N | `tb_stock_movement.id_requisition` | Opcional |
| `tb_kitchen` | `tb_alert` | 1:N | `tb_alert.id_kitchen` | Obrigatória |
| `tb_product` | `tb_alert` | 1:N | `tb_alert.id_product` | Opcional |
| `tb_stock_batch` | `tb_alert` | 1:N | `tb_alert.id_batch` | Opcional (alerta de estoque mínimo não tem lote) |
| `tb_user` | `tb_alert` (destinatário) | 1:N | `tb_alert.id_user` | Opcional (nulo = cozinha inteira) |
| `tb_profile` | `tb_alert` (perfil destinatário) | 1:N | `tb_alert.id_target_profile` | Opcional |
| `tb_alert` ↔ `tb_user` | via `tb_alert_read` | **N:N** | `id_alert`, `id_user` | Obrigatória; apagar o alerta apaga as leituras (`ON DELETE CASCADE`) |
| `tb_user` | `tb_user_daily_access` | 1:N | `tb_user_daily_access.id_user` | Obrigatória; apagar o usuário apaga o histórico (`ON DELETE CASCADE`) |
| `tb_catalog_access_level` | `tb_catalog_table` | 1:N | `tb_catalog_table.id_access_level` | Obrigatória |
| `tb_catalog_table` | `tb_catalog_column` | 1:N | `tb_catalog_column.id_catalog_table` | Obrigatória (`ON DELETE CASCADE`) |
| `tb_catalog_access_level` | `tb_catalog_column` | 1:N | `tb_catalog_column.id_access_level` | Opcional (nulo = herda o da tabela) |
| `tb_log_base` | 7 tabelas `tb_log_*` | Herança (é-um) | `INHERITS` | Cada filha é um tipo de log |

**Relacionamento 1:1:** não há no modelo. Cada candidato natural (perfil do usuário, cozinha do usuário, lote do alerta) é N:1, porque o lado "1" se repete em várias linhas do outro lado.

**Tabelas sem FK para as tabelas auditadas:** as `tb_log_*` guardam o id da linha auditada sem `FOREIGN KEY`, de propósito: o log de um `DELETE` precisa continuar existindo depois que a linha some.

## 8. Como verificar

```bash
psql -f postgre/docs/normalization/normalization_checks.sql
```

| Consulta | Esperado |
|----------|----------|
| R1 a R4 e status | `inconsistentes = 0` (desde a `V012`, R1 e R4 são garantidas por trigger) |
| R5 | Informativo: alertas lidos só pelo modelo antigo |
| cidade → UF, marca → categoria | Linhas retornadas **provam** que a dependência não existe, então não há tabela a extrair. Zero linhas não provam o contrário: só mostram que os dados atuais não a contradizem |

O arquivo só faz leitura e pode rodar direto no banco do Aiven, com os dados do seed.
