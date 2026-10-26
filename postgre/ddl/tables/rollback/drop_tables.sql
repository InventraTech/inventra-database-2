-- ---------------------------------------------------
-- ROLLBACK TABLES
-- ---------------------------------------------------

DROP TABLE IF EXISTS tb_user CASCADE;

DROP TABLE IF EXISTS tb_profile CASCADE;

DROP TABLE IF EXISTS tb_kitchen CASCADE;

DROP TABLE IF EXISTS tb_product CASCADE;

DROP TABLE IF EXISTS tb_category CASCADE;

DROP TABLE IF EXISTS tb_measurement_unit CASCADE;

DROP TABLE IF EXISTS tb_product_supplier CASCADE;

DROP TABLE IF EXISTS tb_supplier CASCADE;

DROP TABLE IF EXISTS tb_product_kitchen_parameter CASCADE;

DROP TABLE IF EXISTS tb_stock_batch CASCADE;

DROP TABLE IF EXISTS tb_requisition CASCADE;

DROP TABLE IF EXISTS tb_requisition_item CASCADE;

DROP TABLE IF EXISTS tb_inventory CASCADE;

DROP TABLE IF EXISTS tb_inventory_count CASCADE;

DROP TABLE IF EXISTS tb_alert CASCADE;

DROP TABLE IF EXISTS tb_alert_read CASCADE;

DROP TABLE IF EXISTS tb_stock_movement CASCADE;

DROP TABLE IF EXISTS tb_pre_list_item CASCADE;

DROP TABLE IF EXISTS tb_pre_list CASCADE;
