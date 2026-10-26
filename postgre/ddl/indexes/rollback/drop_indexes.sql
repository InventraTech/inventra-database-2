-- ---------------------------------------------------
-- ROLLBACK INDEX
-- ---------------------------------------------------

DROP INDEX IF EXISTS idx_user_profile;

DROP INDEX IF EXISTS idx_user_kitchen;

DROP INDEX IF EXISTS idx_user_email;

DROP INDEX IF EXISTS idx_user_active;

DROP INDEX IF EXISTS idx_product_category;

DROP INDEX IF EXISTS idx_product_unit;

DROP INDEX IF EXISTS idx_product_barcode;

DROP INDEX IF EXISTS idx_product_active;

DROP INDEX IF EXISTS idx_productsupplier_product;

DROP INDEX IF EXISTS idx_productsupplier_supplier;

DROP INDEX IF EXISTS idx_parameter_product;

DROP INDEX IF EXISTS idx_parameter_kitchen;

DROP INDEX IF EXISTS idx_batch_product;

DROP INDEX IF EXISTS idx_batch_kitchen;

DROP INDEX IF EXISTS idx_batch_supplier;

DROP INDEX IF EXISTS idx_batch_status;

DROP INDEX IF EXISTS idx_batch_expiration_date;

DROP INDEX IF EXISTS idx_requisition_kitchen;

DROP INDEX IF EXISTS idx_requisition_requester_user;

DROP INDEX IF EXISTS idx_requisition_approver_user;

DROP INDEX IF EXISTS idx_requisition_status;

DROP INDEX IF EXISTS idx_requisition_created_at;

DROP INDEX IF EXISTS idx_requisitionitem_requisition;

DROP INDEX IF EXISTS idx_requisitionitem_product;

DROP INDEX IF EXISTS idx_requisitionitem_supplier;

DROP INDEX IF EXISTS idx_inventory_kitchen;

DROP INDEX IF EXISTS idx_inventory_user;

DROP INDEX IF EXISTS idx_inventory_status;

DROP INDEX IF EXISTS idx_count_inventory;

DROP INDEX IF EXISTS idx_count_batch;

DROP INDEX IF EXISTS idx_alert_kitchen;

DROP INDEX IF EXISTS idx_alert_product;

DROP INDEX IF EXISTS idx_alert_batch;

DROP INDEX IF EXISTS idx_alert_is_read;

DROP INDEX IF EXISTS idx_alert_severity;

DROP INDEX IF EXISTS idx_alert_created_at;

DROP INDEX IF EXISTS idx_batch_kitchen_status_expiration;

DROP INDEX IF EXISTS idx_requisition_status_created_at;

DROP INDEX IF EXISTS idx_productsupplier_product_price;

DROP INDEX IF EXISTS idx_kitchen_location;

DROP INDEX IF EXISTS idx_alert_user;

DROP INDEX IF EXISTS idx_alert_ref_key;

DROP INDEX IF EXISTS idx_alertread_user;

DROP INDEX IF EXISTS idx_movement_batch_created_at;

DROP INDEX IF EXISTS idx_movement_user;

DROP INDEX IF EXISTS idx_movement_requisition;

DROP INDEX IF EXISTS idx_movement_created_at;

DROP INDEX IF EXISTS idx_prelist_list_date;

DROP INDEX IF EXISTS idx_prelist_kitchen;

DROP INDEX IF EXISTS idx_prelistitem_prelist;

DROP INDEX IF EXISTS idx_prelistitem_supplier;

DROP INDEX IF EXISTS idx_prelistitem_product;
