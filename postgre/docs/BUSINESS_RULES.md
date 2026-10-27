# Regras de Negócio no Banco

Functions, procedures e triggers que implementam as regras do Inventra direto no PostgreSQL. Definidos em `migrations/V002__business_rules.sql` (negócio) e `migrations/V003__audit_logs.sql` (auditoria), com as alterações de `V007` (movimentações), `V008` (alertas), `V009` (requisições) e `V019` (hierarquia de categorias).

## Functions de negócio

Arquivo: `functions/create_functions.sql`. São regras automáticas, disparadas por trigger e não chamadas diretamente.

| Function | Trigger que chama | O que faz |
|----------|--------------------|-----------|
| `fn_validate_stock` | `trg_validate_stock` | Impede `current_quantity` negativo em `tb_stock_batch` |
| `fn_update_batch_status` | `trg_update_batch_status` | Marca o lote como `WRITTEN_OFF` quando a quantidade chega a zero |
| `fn_calculate_divergence` | `trg_calculate_divergence` | Calcula `divergence` (física − registrada) em `tb_inventory_count`; valor escrito à mão é sobrescrito |
| `fn_alert_batch_consistency` | `trg_alert_batch_consistency` | Em alerta com lote, preenche produto e cozinha com os do lote e recusa valores diferentes |
| `fn_requisition_approval` | `trg_requisition_approval` | Preenche `approved_at` quando o status muda para `APPROVED` |
| `fn_stock_alert` | `trg_stock_alert` | Cria alerta `STOCK` (`HIGH`) quando a soma dos lotes ativos e não vencidos fica **abaixo** do mínimo cadastrado; não duplica se já há um alerta `STOCK` aberto |
| `fn_expiration_alert` | `trg_expiration_alert` | Cria alerta quando um lote já passou da validade; não duplica se já há um alerta `EXPIRATION` aberto |
| `fn_check_category_cycle` | `trg_category_no_cycle` | Recusa a categoria-mãe que criaria um ciclo na hierarquia: sobe pelos ancestrais da nova mãe com CTE recursiva e barra se a própria categoria aparecer (`V019`) |

`fn_category_descendants(p_id_category)` é a exceção: não é de trigger, é chamada direto. Devolve a categoria e todas as subcategorias abaixo dela (CTE recursiva), para filtrar produtos de um grupo inteiro.

**Alerta aberto** é o que ninguém leu ainda: `is_read = false` (leitura antiga, do alerta inteiro) e nenhuma linha em `tb_alert_read` (leitura por pessoa).

## Procedures

Arquivo: `procedures/create_procedures.sql`. Rotinas de negócio chamadas explicitamente via `CALL`.

| Procedure | O que faz |
|-----------|-----------|
| `sp_approve_requisition` | Aprova uma requisição que está em análise |
| `sp_reject_requisition` | Rejeita uma requisição em análise, com motivo |
| `sp_cancel_requisition` | Cancela requisição em rascunho, em análise ou já aprovada. Na aprovada, **estorna** o estoque: devolve aos lotes o que as movimentações `WRITE_OFF` da requisição baixaram e grava um `ADJUSTMENT` por lote |
| `sp_register_stock_entry` | Registra entrada de quantidade num lote e grava a movimentação `ENTRY` |
| `sp_write_off_stock` | Dá baixa de quantidade num lote (valida se há saldo suficiente) e grava a movimentação `WRITE_OFF` com o motivo (`USAGE` por padrão) |
| `sp_close_inventory` | Fecha um inventário que está aberto |
| `sp_expire_batches` | Marca lotes vencidos como `EXPIRED` e gera os alertas (chamada diariamente pela API) |
| `sp_alert_expiring_batches` | Gera alerta `EXPIRING` para lotes ativos que vencem em até `p_days` dias (padrão 3): `HIGH` se vence hoje ou amanhã, `MEDIUM` nos demais; não duplica enquanto o alerta do lote estiver aberto |

Os parâmetros acrescentados (`p_id_user`, `p_reason`, `p_id_requisition`) têm `DEFAULT`, então as chamadas antigas continuam válidas.

## Governança e recuperação

Procedures e functions de suporte, fora do fluxo de negócio. Criadas em `V010` (catálogo), `V011` (backup) e `V013` (monitoramento).

| Objeto | Arquivo | O que faz |
|--------|---------|-----------|
| `sp_sync_data_catalog(p_prune)` | `procedures/create_catalog_procedures.sql` | Inclui no catálogo de dados, sem descrição, toda tabela ou coluna nova; com `p_prune = true`, remove o que saiu do schema. Veja [`DATA_CATALOG.md`](DATA_CATALOG.md) |
| `sp_restore_from_audit(p_id_log)` | `procedures/create_recovery_procedures.sql` | Desfaz um `INSERT`, `UPDATE` ou `DELETE` usando a linha de `tb_log_*`; a própria recuperação também é auditada |
| `sp_register_backup(...)` | `procedures/create_recovery_procedures.sql` | Grava uma execução de backup ou restore em `tb_backup_history` (chamada pelos scripts de `backup/`) |
| `fn_table_row_counts()` | `functions/create_recovery_functions.sql` | Contagem exata de linhas por tabela, para comparar o banco de origem com o restaurado |
| `fn_register_daily_access()` | `functions/create_monitoring_functions.sql` | Chamada por `trg_register_daily_access` (`AFTER UPDATE OF last_login` em `tb_user`): registra o acesso do dia em `tb_user_daily_access`, base do DAU. Veja [`MONITORING.md`](MONITORING.md) |

Procedimentos completos em [`BACKUP_AND_RECOVERY.md`](BACKUP_AND_RECOVERY.md).

## Movimentações de estoque

`tb_stock_movement` guarda quem mexeu no lote, quando, quanto e por quê.

| `type` | `quantity` | `reason` | Quem grava |
|--------|------------|----------|------------|
| `ENTRY` | quantidade que entrou (> 0) | sempre nulo | `sp_register_stock_entry`; a criação do lote é gravada pela API |
| `WRITE_OFF` | quantidade baixada (> 0) | `USAGE`, `LOSS`, `EXPIRED` ou `REQUISITION` | `sp_write_off_stock` |
| `ADJUSTMENT` | diferença, com sinal (≠ 0) | sempre nulo | API (ajuste de saldo) e `sp_cancel_requisition` (estorno) |

`balance_after` é o saldo do lote logo depois da movimentação. `id_requisition` liga a baixa (e o estorno) à requisição que a causou.

## Triggers de negócio

Arquivo: `triggers/create_trg.sql`.

| Trigger | Tabela | Quando dispara | Function |
|---------|--------|-----------------|----------|
| `trg_validate_stock` | `tb_stock_batch` | BEFORE INSERT/UPDATE de `current_quantity` | `fn_validate_stock` |
| `trg_update_batch_status` | `tb_stock_batch` | BEFORE INSERT/UPDATE de `current_quantity`, `status` | `fn_update_batch_status` |
| `trg_calculate_divergence` | `tb_inventory_count` | BEFORE INSERT/UPDATE (qualquer coluna, desde a `V012`) | `fn_calculate_divergence` |
| `trg_alert_batch_consistency` | `tb_alert` | BEFORE INSERT/UPDATE de `id_batch`, `id_product`, `id_kitchen` | `fn_alert_batch_consistency` |
| `trg_requisition_approval` | `tb_requisition` | BEFORE UPDATE de `status` | `fn_requisition_approval` |
| `trg_stock_alert` | `tb_stock_batch` | AFTER INSERT/UPDATE de `current_quantity` | `fn_stock_alert` |
| `trg_expiration_alert` | `tb_stock_batch` | AFTER INSERT/UPDATE de `expiration_date` | `fn_expiration_alert` |
| `trg_category_no_cycle` | `tb_category` | BEFORE INSERT/UPDATE de `id_parent_category` | `fn_check_category_cycle` |

## Auditoria

Functions em `functions/create_log_functions.sql` e triggers em `triggers/create_log_trg.sql`, uma dupla por tabela auditada:

| Tabela auditada | Function | Trigger | Destino |
|-----------------|----------|---------|---------|
| `tb_user` | `fn_log_user` | `trg_log_user` | `tb_log_user` |
| `tb_product` | `fn_log_product` | `trg_log_product` | `tb_log_product` |
| `tb_supplier` | `fn_log_supplier` | `trg_log_supplier` | `tb_log_supplier` |
| `tb_stock_batch` | `fn_log_stock_batch` | `trg_log_stock_batch` | `tb_log_stock_batch` |
| `tb_requisition` | `fn_log_requisition` | `trg_log_requisition` | `tb_log_requisition` |
| `tb_inventory` | `fn_log_inventory` | `trg_log_inventory` | `tb_log_inventory` |
| `tb_alert` | `fn_log_alert` | `trg_log_alert` | `tb_log_alert` |

Todas disparam **AFTER INSERT OR UPDATE OR DELETE** e gravam o registro inteiro (antes e depois, em JSON) usando `NEW`, `OLD`, `TG_OP` e `CURRENT_USER`. Veja [a herança das tabelas de log](ARCHITECTURE.md#herança-de-tabela-nas-tabelas-de-log).
