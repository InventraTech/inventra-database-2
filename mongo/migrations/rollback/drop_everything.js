// Reversão completa do dbIAI: APAGA as conversas, as métricas e as propostas da IA.
// Uso: mongosh "$MONGO_URI" --file migrations/rollback/drop_everything.js
const dbi = db.getSiblingDB(process.env.MONGO_DB || 'dbIAI');

for (const name of ['sessions', 'metrics', 'approvals', 'notifications', 'schema_migrations']) {
  dbi.getCollection(name).drop();
}
