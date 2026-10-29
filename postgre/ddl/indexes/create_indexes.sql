-- ---------------------------------------------------
-- INDEX CREATION
-- ---------------------------------------------------

CREATE INDEX idx_user_profile 
ON tb_user (id_profile);

CREATE INDEX idx_user_kitchen 
ON tb_user (id_kitchen);

CREATE INDEX idx_user_active 
ON tb_user (active);

CREATE INDEX idx_product_category 
ON tb_product (id_category);

CREATE INDEX idx_category_parent
ON tb_category (id_parent_category);

CREATE INDEX idx_product_unit
ON tb_product (id_unit);

CREATE INDEX idx_product_active 
ON tb_product (active);

CREATE INDEX idx_productsupplier_supplier 
ON tb_product_supplier (id_supplier);

CREATE INDEX idx_parameter_kitchen 
ON tb_product_kitchen_parameter (id_kitchen);

CREATE INDEX idx_batch_product 
ON tb_stock_batch (id_product);

CREATE INDEX idx_batch_supplier 
ON tb_stock_batch (id_supplier);

CREATE INDEX idx_batch_status 
ON tb_stock_batch (status);

CREATE INDEX idx_batch_expiration_date 
ON tb_stock_batch (expiration_date);

CREATE INDEX idx_requisition_kitchen 
ON tb_requisition (id_kitchen);

CREATE INDEX idx_requisition_requester_user 
ON tb_requisition (id_requester_user);

CREATE INDEX idx_requisition_approver_user 
ON tb_requisition (id_approver_user);

CREATE INDEX idx_requisition_created_at 
ON tb_requisition (created_at);

CREATE INDEX idx_requisition_prelist
ON tb_requisition (id_pre_list);

CREATE UNIQUE INDEX uq_requisition_prelist_active
ON tb_requisition (id_pre_list)
WHERE id_pre_list IS NOT NULL AND status NOT IN ('CANCELLED', 'REJECTED');

CREATE INDEX idx_requisitionitem_requisition 
ON tb_requisition_item (id_requisition);

CREATE INDEX idx_requisitionitem_product 
ON tb_requisition_item (id_product);

CREATE INDEX idx_requisitionitem_supplier 
ON tb_requisition_item (id_suggested_supplier);

CREATE INDEX idx_inventory_kitchen 
ON tb_inventory (id_kitchen);

CREATE INDEX idx_inventory_user 
ON tb_inventory (id_responsible_user);

CREATE INDEX idx_inventory_status 
ON tb_inventory (status);

CREATE INDEX idx_count_inventory 
ON tb_inventory_count (id_inventory);

CREATE INDEX idx_count_batch 
ON tb_inventory_count (id_batch);

CREATE INDEX idx_alert_kitchen 
ON tb_alert (id_kitchen);

CREATE INDEX idx_alert_product 
ON tb_alert (id_product);

CREATE INDEX idx_alert_batch 
ON tb_alert (id_batch);

CREATE INDEX idx_alert_is_read 
ON tb_alert (is_read);

CREATE INDEX idx_alert_severity 
ON tb_alert (severity);

CREATE INDEX idx_alert_created_at 
ON tb_alert (created_at);

CREATE INDEX idx_batch_kitchen_status_expiration
ON tb_stock_batch (id_kitchen, status, expiration_date);

CREATE INDEX idx_requisition_status_created_at
ON tb_requisition (status, created_at DESC);

CREATE INDEX idx_productsupplier_product_price
ON tb_product_supplier (id_product, reference_price);

CREATE INDEX idx_kitchen_location
ON tb_kitchen (latitude, longitude);

CREATE INDEX idx_alert_user
ON tb_alert (id_user);

CREATE INDEX idx_alert_ref_key
ON tb_alert (ref_key);

CREATE INDEX idx_alertread_user
ON tb_alert_read (id_user);

CREATE INDEX idx_movement_batch_created_at
ON tb_stock_movement (id_batch, created_at DESC);

CREATE INDEX idx_movement_user
ON tb_stock_movement (id_user);

CREATE INDEX idx_movement_requisition
ON tb_stock_movement (id_requisition);

CREATE INDEX idx_movement_created_at
ON tb_stock_movement (created_at);

CREATE INDEX idx_prelist_list_date
ON tb_pre_list (list_date);

CREATE INDEX idx_prelist_kitchen
ON tb_pre_list (id_kitchen);

CREATE INDEX idx_prelistitem_prelist
ON tb_pre_list_item (id_pre_list);

CREATE INDEX idx_prelistitem_supplier
ON tb_pre_list_item (id_supplier);

CREATE INDEX idx_prelistitem_product
ON tb_pre_list_item (id_product);
