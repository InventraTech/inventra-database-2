// Garante que o dicionário (schemas/*.schema.json e indexes/create_indexes.js) e a esteira
// (migrations/) descrevem o mesmo banco: compara o validador aplicado pelas migrations com os
// arquivos JSON e os índices das migrations com os de create_indexes.js, que check_migrations.sh
// aplica antes num banco à parte (<MONGO_DB>_dict). Esse banco é apagado no final.
const fs = require('fs');
const path = require('path');

const root = path.resolve(process.env.MONGO_REPO_DIR || '.');
const dbName = process.env.MONGO_DB || 'dbIAI';
const dbi = db.getSiblingDB(dbName);
const failures = [];

// JSON com chaves ordenadas, para comparar sem depender da ordem de inserção.
const canonical = (v) => JSON.stringify(v, (_, x) =>
  x && typeof x === 'object' && !Array.isArray(x) ? Object.fromEntries(Object.entries(x).sort()) : x);

for (const name of ['sessions', 'metrics', 'approvals']) {
  const file = JSON.parse(fs.readFileSync(path.join(root, 'schemas', `${name}.schema.json`), 'utf8'));
  const applied = dbi.getCollectionInfos({ name })[0].options.validator.$jsonSchema;
  if (canonical(file) !== canonical(applied)) {
    failures.push(`${name}: validador das migrations difere de schemas/${name}.schema.json`);
  }
}

const dictName = `${dbName}_dict`;
const indexSpec = (database, coll) => canonical(database[coll].getIndexes()
  .map((i) => ({ name: i.name, key: i.key, unique: !!i.unique, partial: i.partialFilterExpression || null })).sort((a, b) => a.name.localeCompare(b.name)));
const dict = db.getSiblingDB(dictName);
for (const coll of ['sessions', 'metrics', 'approvals', 'notifications']) {
  if (indexSpec(dbi, coll) !== indexSpec(dict, coll)) {
    failures.push(`${coll}: índices das migrations diferem de indexes/create_indexes.js`);
  }
}
dict.dropDatabase();

if (failures.length) {
  failures.forEach((f) => print(`FALHA: ${f}`));
  quit(1);
}
print('dicionário × migrations OK');
