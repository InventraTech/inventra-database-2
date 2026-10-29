// Tira os validadores $jsonSchema das coleções sem apagar documentos.
const dbi = db.getSiblingDB(process.env.MONGO_DB || 'dbIAI');

for (const name of ['sessions', 'metrics', 'approvals']) {
  if (dbi.getCollectionNames().includes(name)) {
    dbi.runCommand({ collMod: name, validator: {}, validationLevel: 'off' });
  }
}
