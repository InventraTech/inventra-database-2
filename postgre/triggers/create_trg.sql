-- ---------------------------------------------------
-- TRIGGER CREATION
-- ---------------------------------------------------

CREATE TRIGGER trg_validate_stock
BEFORE INSERT OR UPDATE OF current_quantity
ON tb_stock_batch
FOR EACH ROW
EXECUTE FUNCTION fn_validate_stock();

CREATE TRIGGER trg_update_batch_status
BEFORE INSERT OR UPDATE OF current_quantity, status
ON tb_stock_batch
FOR EACH ROW
EXECUTE FUNCTION fn_update_batch_status();

-- qualquer UPDATE: um valor escrito à mão em divergence também é recalculado
CREATE TRIGGER trg_calculate_divergence
BEFORE INSERT OR UPDATE
ON tb_inventory_count
FOR EACH ROW
EXECUTE FUNCTION fn_calculate_divergence();

CREATE TRIGGER trg_requisition_approval
BEFORE UPDATE OF status
ON tb_requisition
FOR EACH ROW
EXECUTE FUNCTION fn_requisition_approval();

CREATE TRIGGER trg_stock_alert
AFTER INSERT OR UPDATE OF current_quantity
ON tb_stock_batch
FOR EACH ROW
EXECUTE FUNCTION fn_stock_alert();

CREATE TRIGGER trg_expiration_alert
AFTER INSERT OR UPDATE OF expiration_date
ON tb_stock_batch
FOR EACH ROW
EXECUTE FUNCTION fn_expiration_alert();

-- só nas colunas da regra: marcar como lido (is_read) não paga o custo da consulta
CREATE TRIGGER trg_alert_batch_consistency
BEFORE INSERT OR UPDATE OF id_batch, id_product, id_kitchen
ON tb_alert
FOR EACH ROW
EXECUTE FUNCTION fn_alert_batch_consistency();

CREATE TRIGGER trg_category_no_cycle
BEFORE INSERT OR UPDATE OF id_parent_category
ON tb_category
FOR EACH ROW
EXECUTE FUNCTION fn_check_category_cycle();

CREATE TRIGGER trg_product_supplier_updated_at
BEFORE UPDATE
ON tb_product_supplier
FOR EACH ROW
EXECUTE FUNCTION fn_product_supplier_updated_at();
