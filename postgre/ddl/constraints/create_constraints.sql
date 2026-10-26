-- ---------------------------------------------------
-- FOREIGN KEYS CREATION
-- ---------------------------------------------------

ALTER TABLE tb_user
ADD CONSTRAINT fk_user_profile
FOREIGN KEY (id_profile) REFERENCES tb_profile (id_profile)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_user
ADD CONSTRAINT fk_user_kitchen
FOREIGN KEY (id_kitchen) REFERENCES tb_kitchen (id_kitchen)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_product
ADD CONSTRAINT fk_product_category
FOREIGN KEY (id_category) REFERENCES tb_category (id_category)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_product
ADD CONSTRAINT fk_product_unit
FOREIGN KEY (id_unit) REFERENCES tb_measurement_unit (id_unit)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_product_supplier
ADD CONSTRAINT fk_productsupplier_product
FOREIGN KEY (id_product) REFERENCES tb_product (id_product)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_product_supplier
ADD CONSTRAINT fk_productsupplier_supplier
FOREIGN KEY (id_supplier) REFERENCES tb_supplier (id_supplier)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_product_kitchen_parameter
ADD CONSTRAINT fk_parameter_product
FOREIGN KEY (id_product) REFERENCES tb_product (id_product)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_product_kitchen_parameter
ADD CONSTRAINT fk_parameter_kitchen
FOREIGN KEY (id_kitchen) REFERENCES tb_kitchen (id_kitchen)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_stock_batch
ADD CONSTRAINT fk_batch_product
FOREIGN KEY (id_product) REFERENCES tb_product (id_product)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_stock_batch
ADD CONSTRAINT fk_batch_kitchen
FOREIGN KEY (id_kitchen) REFERENCES tb_kitchen (id_kitchen)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_stock_batch
ADD CONSTRAINT fk_batch_supplier
FOREIGN KEY (id_supplier) REFERENCES tb_supplier (id_supplier)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_requisition
ADD CONSTRAINT fk_requisition_kitchen
FOREIGN KEY (id_kitchen) REFERENCES tb_kitchen (id_kitchen)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_requisition
ADD CONSTRAINT fk_requisition_requester_user
FOREIGN KEY (id_requester_user) REFERENCES tb_user (id_user)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_requisition
ADD CONSTRAINT fk_requisition_approver_user
FOREIGN KEY (id_approver_user) REFERENCES tb_user (id_user)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_requisition_item
ADD CONSTRAINT fk_requisitionitem_requisition
FOREIGN KEY (id_requisition) REFERENCES tb_requisition (id_requisition)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_requisition_item
ADD CONSTRAINT fk_requisitionitem_product
FOREIGN KEY (id_product) REFERENCES tb_product (id_product)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_requisition_item
ADD CONSTRAINT fk_requisitionitem_supplier
FOREIGN KEY (id_suggested_supplier) REFERENCES tb_supplier (id_supplier)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_inventory
ADD CONSTRAINT fk_inventory_kitchen
FOREIGN KEY (id_kitchen) REFERENCES tb_kitchen (id_kitchen)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_inventory
ADD CONSTRAINT fk_inventory_user
FOREIGN KEY (id_responsible_user) REFERENCES tb_user (id_user)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_inventory_count
ADD CONSTRAINT fk_count_inventory
FOREIGN KEY (id_inventory) REFERENCES tb_inventory (id_inventory)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_inventory_count
ADD CONSTRAINT fk_count_batch
FOREIGN KEY (id_batch) REFERENCES tb_stock_batch (id_batch)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_alert
ADD CONSTRAINT fk_alert_kitchen
FOREIGN KEY (id_kitchen) REFERENCES tb_kitchen (id_kitchen)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_alert
ADD CONSTRAINT fk_alert_product
FOREIGN KEY (id_product) REFERENCES tb_product (id_product)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_alert
ADD CONSTRAINT fk_alert_batch
FOREIGN KEY (id_batch) REFERENCES tb_stock_batch (id_batch)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_alert
ADD CONSTRAINT fk_alert_user
FOREIGN KEY (id_user) REFERENCES tb_user (id_user)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_alert
ADD CONSTRAINT fk_alert_target_profile
FOREIGN KEY (id_target_profile) REFERENCES tb_profile (id_profile)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_alert_read
ADD CONSTRAINT fk_alertread_alert
FOREIGN KEY (id_alert) REFERENCES tb_alert (id_alert)
ON UPDATE NO ACTION ON DELETE CASCADE;

ALTER TABLE tb_alert_read
ADD CONSTRAINT fk_alertread_user
FOREIGN KEY (id_user) REFERENCES tb_user (id_user)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_stock_movement
ADD CONSTRAINT fk_movement_batch
FOREIGN KEY (id_batch) REFERENCES tb_stock_batch (id_batch)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_stock_movement
ADD CONSTRAINT fk_movement_user
FOREIGN KEY (id_user) REFERENCES tb_user (id_user)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_stock_movement
ADD CONSTRAINT fk_movement_requisition
FOREIGN KEY (id_requisition) REFERENCES tb_requisition (id_requisition)
ON UPDATE NO ACTION ON DELETE NO ACTION;

-- ---------------------------------------------------
-- UNIQUE CONSTRAINTS
-- ---------------------------------------------------

ALTER TABLE tb_user
ADD CONSTRAINT uq_user_firebase_uid
UNIQUE (firebase_uid);

ALTER TABLE tb_pre_list
ADD CONSTRAINT uq_prelist_id_source
UNIQUE (id_source);

-- ---------------------------------------------------
-- CHECK CONSTRAINTS
-- ---------------------------------------------------

ALTER TABLE tb_supplier
ADD CONSTRAINT ck_supplier_rating 
CHECK (rating BETWEEN 1 AND 5);

ALTER TABLE tb_stock_batch
ADD CONSTRAINT ck_batch_status 
CHECK (status IN ('ACTIVE', 'WRITTEN_OFF', 'EXPIRED', 'CANCELLED'));

ALTER TABLE tb_requisition
ADD CONSTRAINT ck_requisition_status 
CHECK (status IN ('DRAFT', 'UNDER_REVIEW', 'APPROVED', 'REJECTED', 'CANCELLED'));

ALTER TABLE tb_requisition
ADD CONSTRAINT ck_requisition_type 
CHECK (requisition_type IN ('PURCHASE', 'TRANSFER', 'CONSUMPTION'));

ALTER TABLE tb_inventory
ADD CONSTRAINT ck_inventory_status 
CHECK (status IN ('OPEN', 'CLOSED', 'CANCELLED'));

ALTER TABLE tb_alert
ADD CONSTRAINT ck_alert_severity 
CHECK (severity IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL'));

ALTER TABLE tb_kitchen
ADD CONSTRAINT ck_kitchen_state
CHECK (state ~ '^[A-Z]{2}$');

ALTER TABLE tb_kitchen
ADD CONSTRAINT ck_kitchen_latitude
CHECK (latitude BETWEEN -90 AND 90);

ALTER TABLE tb_kitchen
ADD CONSTRAINT ck_kitchen_longitude
CHECK (longitude BETWEEN -180 AND 180);

ALTER TABLE tb_stock_movement
ADD CONSTRAINT ck_movement_type
CHECK (type IN ('ENTRY', 'WRITE_OFF', 'ADJUSTMENT'));

ALTER TABLE tb_stock_movement
ADD CONSTRAINT ck_movement_reason
CHECK (
	(type = 'WRITE_OFF' AND reason IN ('USAGE', 'LOSS', 'EXPIRED', 'REQUISITION'))
	OR (type <> 'WRITE_OFF' AND reason IS NULL)
);

ALTER TABLE tb_stock_movement
ADD CONSTRAINT ck_movement_quantity
CHECK (
	(type = 'ADJUSTMENT' AND quantity <> 0)
	OR (type <> 'ADJUSTMENT' AND quantity > 0)
);

ALTER TABLE tb_pre_list
ADD CONSTRAINT fk_prelist_kitchen
FOREIGN KEY (id_kitchen) REFERENCES tb_kitchen (id_kitchen)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_pre_list_item
ADD CONSTRAINT fk_prelistitem_prelist
FOREIGN KEY (id_pre_list) REFERENCES tb_pre_list (id_pre_list)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_pre_list_item
ADD CONSTRAINT fk_prelistitem_supplier
FOREIGN KEY (id_supplier) REFERENCES tb_supplier (id_supplier)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_pre_list_item
ADD CONSTRAINT fk_prelistitem_product
FOREIGN KEY (id_product) REFERENCES tb_product (id_product)
ON UPDATE NO ACTION ON DELETE NO ACTION;

ALTER TABLE tb_pre_list_item
ADD CONSTRAINT ck_prelistitem_quantity
CHECK (quantity > 0);
