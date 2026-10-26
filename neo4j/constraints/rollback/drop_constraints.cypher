// Remove as constraints da projeção. Os nós continuam; sem as constraints o MERGE perde a garantia de unicidade.
// Uso: cypher-shell -f constraints/rollback/drop_constraints.cypher
DROP CONSTRAINT requisition_id IF EXISTS;
DROP CONSTRAINT product_id IF EXISTS;
DROP CONSTRAINT supplier_id IF EXISTS;
