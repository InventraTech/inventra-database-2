// Remove os índices criados por create_indexes.js (o _id_ fica).
const dbi = db.getSiblingDB(process.env.MONGO_DB || 'dbIAI');

const drop = (coll, name) => {
  if (dbi.getCollectionNames().includes(coll) && dbi[coll].getIndexes().some((i) => i.name === name)) {
    dbi[coll].dropIndex(name);
  }
};
drop('sessions', 'user_id_1_kitchen_id_1_session_id_1_active_1');
drop('sessions', 'user_id_1_kitchen_id_1_started_at_-1');
drop('approvals', 'requester_id_1_kitchen_id_1_idempotency_key_1');
drop('approvals', 'status_1_expires_at_1');
drop('notifications', 'kitchen_id_1_created_at_-1');
drop('metrics', 'kitchen_id_1_timestamp_-1');
