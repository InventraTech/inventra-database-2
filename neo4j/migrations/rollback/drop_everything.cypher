// Reversão completa da projeção: APAGA os nós e arestas do grafo e o schema da V001.
// Só atinge o Neo4j; o PostgreSQL (fonte da verdade) não é tocado, e seeds/seed.ipynb reprojeta tudo.
// Uso: cypher-shell -f migrations/rollback/drop_everything.cypher

MATCH (n)
WHERE n:Requisition OR n:Product OR n:Supplier OR n:SchemaMigration
DETACH DELETE n;

DROP INDEX requisition_kitchen IF EXISTS;
DROP INDEX supplier_active IF EXISTS;
DROP CONSTRAINT requisition_id IF EXISTS;
DROP CONSTRAINT product_id IF EXISTS;
DROP CONSTRAINT supplier_id IF EXISTS;
