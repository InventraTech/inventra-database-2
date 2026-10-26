// Remove os índices da projeção (os índices das constraints saem com drop_constraints.cypher).
// Uso: cypher-shell -f indexes/rollback/drop_indexes.cypher
DROP INDEX requisition_kitchen IF EXISTS;
DROP INDEX supplier_active IF EXISTS;
