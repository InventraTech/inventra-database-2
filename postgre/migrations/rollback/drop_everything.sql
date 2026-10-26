-- =====================================================
-- FULL TEARDOWN — reverses V001 through V018
-- =====================================================
-- WARNING: destructive and irreversible. Drops every table
-- (and all data in them), view, function, procedure, trigger,
-- constraint and index created by this project, including the
-- data catalog, backup history and access history (DAU), UI click counter and pre-lists. Take
-- a backup first (postgre/backup/backup.sh). Seed data lives in
-- the tables, so it goes with them.
--
-- Order matters: newest layers first (monitoring, backup, catalog, views),
-- triggers before the functions they call, functions/procedures
-- before the tables they reference, constraints and indexes
-- before the tables that own them, log tables last among tables
-- since nothing depends on them. Every statement is IF EXISTS,
-- so this is safe to run even on a partially-created or
-- already-empty database.
--
-- Log and base tables use CASCADE: any object created directly
-- on the database outside this repo (e.g. ad-hoc BI views) that
-- depends on them is removed too. Back up those definitions
-- first if they need to be recreated afterward.

-- ---------------------------------------------------
-- PRE-LIST
-- ---------------------------------------------------

DROP TABLE IF EXISTS tb_pre_list_item;

DROP TABLE IF EXISTS tb_pre_list;

-- ---------------------------------------------------
-- UI CLICK COUNTER
-- ---------------------------------------------------

DROP VIEW IF EXISTS vw_ui_click_ranking;

DROP TABLE IF EXISTS tb_ui_click_counter;

-- ---------------------------------------------------
-- MONITORING (DAU)
-- ---------------------------------------------------

DROP VIEW IF EXISTS vw_dau_by_kitchen;

DROP VIEW IF EXISTS vw_dau;

DROP TRIGGER IF EXISTS trg_register_daily_access
ON tb_user;

DROP FUNCTION IF EXISTS fn_register_daily_access();

DROP TABLE IF EXISTS tb_user_daily_access;

-- ---------------------------------------------------
-- BACKUP AND RECOVERY
-- ---------------------------------------------------

DROP VIEW IF EXISTS vw_backup_status;

DROP PROCEDURE IF EXISTS sp_restore_from_audit(INTEGER);

DROP PROCEDURE IF EXISTS sp_register_backup(VARCHAR, VARCHAR, VARCHAR, TIMESTAMPTZ, TIMESTAMPTZ, BIGINT, VARCHAR, VARCHAR, VARCHAR);

DROP FUNCTION IF EXISTS fn_table_row_counts();

DROP TABLE IF EXISTS tb_backup_history;

-- ---------------------------------------------------
-- DATA CATALOG
-- ---------------------------------------------------

DROP VIEW IF EXISTS vw_data_catalog_table;

DROP VIEW IF EXISTS vw_data_catalog;

DROP PROCEDURE IF EXISTS sp_sync_data_catalog(BOOLEAN);

DROP TABLE IF EXISTS tb_catalog_column;

DROP TABLE IF EXISTS tb_catalog_table;

DROP TABLE IF EXISTS tb_catalog_access_level;

-- ---------------------------------------------------
-- ETL / ANALYTICS VIEWS
-- ---------------------------------------------------

DROP VIEW IF EXISTS vw_product_expiration_urgency;

DROP VIEW IF EXISTS vw_category_monthly_requisition_trend;

DROP VIEW IF EXISTS vw_category_stock_balance;

-- ---------------------------------------------------
-- DATA MART VIEWS (STAR SCHEMA)
-- ---------------------------------------------------

DROP VIEW IF EXISTS fact_inventory_count;

DROP VIEW IF EXISTS fact_requisition_item;

DROP VIEW IF EXISTS fact_stock_movement;

DROP VIEW IF EXISTS dim_date;

DROP VIEW IF EXISTS dim_supplier;

DROP VIEW IF EXISTS dim_kitchen;

DROP VIEW IF EXISTS dim_product;

-- ---------------------------------------------------
-- VIEWS
-- ---------------------------------------------------

DROP VIEW IF EXISTS vw_monthly_waste_proxy_kpi;

DROP VIEW IF EXISTS vw_supplier_profile;

DROP VIEW IF EXISTS vw_batches_needing_attention;

DROP VIEW IF EXISTS vw_products_below_minimum;

DROP VIEW IF EXISTS vw_requisition_pending;

DROP VIEW IF EXISTS vw_stock_movement_log;

DROP VIEW IF EXISTS vw_requisition_summary;

DROP VIEW IF EXISTS vw_stock_value_by_category;

DROP VIEW IF EXISTS vw_active_alerts;

DROP VIEW IF EXISTS vw_daily_expiration_summary;

DROP VIEW IF EXISTS vw_product_stock_position;

DROP VIEW IF EXISTS vw_stock_batch_detail;

DROP VIEW IF EXISTS vw_kitchen_dashboard_kpi;

DROP VIEW IF EXISTS vw_product_supplier_catalog;

DROP VIEW IF EXISTS vw_product_requisition_ranking;

DROP VIEW IF EXISTS vw_kitchen_daily_stock_movement;

DROP VIEW IF EXISTS vw_inventory_count_divergence;

-- ---------------------------------------------------
-- LOG TRIGGERS
-- ---------------------------------------------------

DROP TRIGGER IF EXISTS trg_log_user
ON tb_user;

DROP TRIGGER IF EXISTS trg_log_product
ON tb_product;

DROP TRIGGER IF EXISTS trg_log_supplier
ON tb_supplier;

DROP TRIGGER IF EXISTS trg_log_stock_batch
ON tb_stock_batch;

DROP TRIGGER IF EXISTS trg_log_requisition
ON tb_requisition;

DROP TRIGGER IF EXISTS trg_log_inventory
ON tb_inventory;

DROP TRIGGER IF EXISTS trg_log_alert
ON tb_alert;

-- ---------------------------------------------------
-- BUSINESS TRIGGERS
-- ---------------------------------------------------

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

-- ---------------------------------------------------
-- LOG FUNCTIONS
-- ---------------------------------------------------

DROP FUNCTION IF EXISTS fn_log_user();

DROP FUNCTION IF EXISTS fn_log_product();

DROP FUNCTION IF EXISTS fn_log_supplier();

DROP FUNCTION IF EXISTS fn_log_stock_batch();

DROP FUNCTION IF EXISTS fn_log_requisition();

DROP FUNCTION IF EXISTS fn_log_inventory();

DROP FUNCTION IF EXISTS fn_log_alert();

-- ---------------------------------------------------
-- BUSINESS FUNCTIONS
-- ---------------------------------------------------

DROP FUNCTION IF EXISTS fn_alert_batch_consistency();

DROP FUNCTION IF EXISTS fn_expiration_alert();

DROP FUNCTION IF EXISTS fn_stock_alert();

DROP FUNCTION IF EXISTS fn_requisition_approval();

DROP FUNCTION IF EXISTS fn_calculate_divergence();

DROP FUNCTION IF EXISTS fn_update_batch_status();

DROP FUNCTION IF EXISTS fn_validate_stock();

-- ---------------------------------------------------
-- PROCEDURES
-- ---------------------------------------------------

DROP PROCEDURE IF EXISTS sp_alert_expiring_batches(INTEGER);

DROP PROCEDURE IF EXISTS sp_expire_batches();

DROP PROCEDURE IF EXISTS sp_close_inventory(INTEGER);

DROP PROCEDURE IF EXISTS sp_write_off_stock(INTEGER, DECIMAL);

DROP PROCEDURE IF EXISTS sp_write_off_stock(INTEGER, DECIMAL, UUID, VARCHAR, INTEGER);

DROP PROCEDURE IF EXISTS sp_register_stock_entry(INTEGER, DECIMAL);

DROP PROCEDURE IF EXISTS sp_register_stock_entry(INTEGER, DECIMAL, UUID);

DROP PROCEDURE IF EXISTS sp_cancel_requisition(INTEGER, VARCHAR);

DROP PROCEDURE IF EXISTS sp_cancel_requisition(INTEGER, VARCHAR, UUID);

DROP PROCEDURE IF EXISTS sp_reject_requisition(INTEGER, UUID, VARCHAR);

DROP PROCEDURE IF EXISTS sp_approve_requisition(INTEGER, UUID);

-- ---------------------------------------------------
-- FOREIGN KEYS
-- ---------------------------------------------------

ALTER TABLE tb_user
DROP CONSTRAINT IF EXISTS fk_user_profile;

ALTER TABLE tb_user
DROP CONSTRAINT IF EXISTS fk_user_kitchen;

ALTER TABLE tb_product
DROP CONSTRAINT IF EXISTS fk_product_category;

ALTER TABLE tb_product
DROP CONSTRAINT IF EXISTS fk_product_unit;

ALTER TABLE tb_product_supplier
DROP CONSTRAINT IF EXISTS fk_productsupplier_product;

ALTER TABLE tb_product_supplier
DROP CONSTRAINT IF EXISTS fk_productsupplier_supplier;

ALTER TABLE tb_product_kitchen_parameter
DROP CONSTRAINT IF EXISTS fk_parameter_product;

ALTER TABLE tb_product_kitchen_parameter
DROP CONSTRAINT IF EXISTS fk_parameter_kitchen;

ALTER TABLE tb_stock_batch
DROP CONSTRAINT IF EXISTS fk_batch_product;

ALTER TABLE tb_stock_batch
DROP CONSTRAINT IF EXISTS fk_batch_kitchen;

ALTER TABLE tb_stock_batch
DROP CONSTRAINT IF EXISTS fk_batch_supplier;

ALTER TABLE tb_requisition
DROP CONSTRAINT IF EXISTS fk_requisition_kitchen;

ALTER TABLE tb_requisition
DROP CONSTRAINT IF EXISTS fk_requisition_requester_user;

ALTER TABLE tb_requisition
DROP CONSTRAINT IF EXISTS fk_requisition_approver_user;

ALTER TABLE tb_requisition_item
DROP CONSTRAINT IF EXISTS fk_requisitionitem_requisition;

ALTER TABLE tb_requisition_item
DROP CONSTRAINT IF EXISTS fk_requisitionitem_product;

ALTER TABLE tb_requisition_item
DROP CONSTRAINT IF EXISTS fk_requisitionitem_supplier;

ALTER TABLE tb_inventory
DROP CONSTRAINT IF EXISTS fk_inventory_kitchen;

ALTER TABLE tb_inventory
DROP CONSTRAINT IF EXISTS fk_inventory_user;

ALTER TABLE tb_inventory_count
DROP CONSTRAINT IF EXISTS fk_count_inventory;

ALTER TABLE tb_inventory_count
DROP CONSTRAINT IF EXISTS fk_count_batch;

ALTER TABLE tb_alert
DROP CONSTRAINT IF EXISTS fk_alert_kitchen;

ALTER TABLE tb_alert
DROP CONSTRAINT IF EXISTS fk_alert_product;

ALTER TABLE tb_alert
DROP CONSTRAINT IF EXISTS fk_alert_batch;

ALTER TABLE IF EXISTS tb_alert
DROP CONSTRAINT IF EXISTS fk_alert_user;

ALTER TABLE IF EXISTS tb_alert
DROP CONSTRAINT IF EXISTS fk_alert_target_profile;

ALTER TABLE IF EXISTS tb_alert_read
DROP CONSTRAINT IF EXISTS fk_alertread_alert;

ALTER TABLE IF EXISTS tb_alert_read
DROP CONSTRAINT IF EXISTS fk_alertread_user;

ALTER TABLE IF EXISTS tb_stock_movement
DROP CONSTRAINT IF EXISTS fk_movement_batch;

ALTER TABLE IF EXISTS tb_stock_movement
DROP CONSTRAINT IF EXISTS fk_movement_user;

ALTER TABLE IF EXISTS tb_stock_movement
DROP CONSTRAINT IF EXISTS fk_movement_requisition;

-- ---------------------------------------------------
-- UNIQUE CONSTRAINTS
-- ---------------------------------------------------

ALTER TABLE tb_user
DROP CONSTRAINT IF EXISTS uq_user_firebase_uid;

-- ---------------------------------------------------
-- CHECK CONSTRAINTS
-- ---------------------------------------------------

ALTER TABLE tb_supplier
DROP CONSTRAINT IF EXISTS ck_supplier_rating;

ALTER TABLE tb_stock_batch
DROP CONSTRAINT IF EXISTS ck_batch_status;

ALTER TABLE tb_requisition
DROP CONSTRAINT IF EXISTS ck_requisition_status;

ALTER TABLE tb_requisition
DROP CONSTRAINT IF EXISTS ck_requisition_type;

ALTER TABLE tb_inventory
DROP CONSTRAINT IF EXISTS ck_inventory_status;

ALTER TABLE tb_alert
DROP CONSTRAINT IF EXISTS ck_alert_severity;

ALTER TABLE IF EXISTS tb_kitchen
DROP CONSTRAINT IF EXISTS ck_kitchen_state;

ALTER TABLE IF EXISTS tb_kitchen
DROP CONSTRAINT IF EXISTS ck_kitchen_latitude;

ALTER TABLE IF EXISTS tb_kitchen
DROP CONSTRAINT IF EXISTS ck_kitchen_longitude;

ALTER TABLE IF EXISTS tb_stock_movement
DROP CONSTRAINT IF EXISTS ck_movement_type;

ALTER TABLE IF EXISTS tb_stock_movement
DROP CONSTRAINT IF EXISTS ck_movement_reason;

ALTER TABLE IF EXISTS tb_stock_movement
DROP CONSTRAINT IF EXISTS ck_movement_quantity;

-- ---------------------------------------------------
-- INDEXES
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

-- ---------------------------------------------------
-- LOG TABLE INDEXES
-- ---------------------------------------------------

DROP INDEX IF EXISTS idx_log_stock_batch_id_batch;

-- ---------------------------------------------------
-- LOG TABLES
-- ---------------------------------------------------

DROP TABLE IF EXISTS tb_log_alert CASCADE;
DROP TABLE IF EXISTS tb_log_inventory CASCADE;
DROP TABLE IF EXISTS tb_log_requisition CASCADE;
DROP TABLE IF EXISTS tb_log_stock_batch CASCADE;
DROP TABLE IF EXISTS tb_log_supplier CASCADE;
DROP TABLE IF EXISTS tb_log_product CASCADE;
DROP TABLE IF EXISTS tb_log_user CASCADE;
DROP TABLE IF EXISTS tb_log_base CASCADE;
DROP SEQUENCE IF EXISTS seq_log_id;

-- ---------------------------------------------------
-- TABLES
-- ---------------------------------------------------

DROP TABLE IF EXISTS tb_alert_read CASCADE;
DROP TABLE IF EXISTS tb_stock_movement CASCADE;
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
