-- ---------------------------------------------------
-- ROLLBACK TRIGGERS
-- ---------------------------------------------------

DROP TRIGGER IF EXISTS trg_category_no_cycle
ON tb_category;

DROP TRIGGER IF EXISTS trg_alert_batch_consistency
ON tb_alert;

DROP TRIGGER IF EXISTS trg_expiration_alert
ON tb_stock_batch;

DROP TRIGGER IF EXISTS trg_stock_alert
ON tb_stock_batch;

DROP TRIGGER IF EXISTS trg_requisition_approval
ON tb_requisition;

DROP TRIGGER IF EXISTS trg_calculate_divergence
ON tb_inventory_count;

DROP TRIGGER IF EXISTS trg_update_batch_status
ON tb_stock_batch;

DROP TRIGGER IF EXISTS trg_validate_stock
ON tb_stock_batch;