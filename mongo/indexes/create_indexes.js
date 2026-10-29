// Índices do dbIAI. Os nomes repetem o padrão do driver (campo_ordem) porque a IAI
// também chama create_index no startup: nome diferente para a mesma chave gera erro.
// Cada createIndex fica numa linha só: scripts/workspace/build.py lê este arquivo por linha.
// Uso: mongosh "$MONGO_URI" --file indexes/create_indexes.js
const dbi = db.getSiblingDB(process.env.MONGO_DB || 'dbIAI');

// sessions: uma sessão ativa por usuário + cozinha + session_id (doc_id_da_sessao / iniciar_sessao)
dbi.sessions.createIndex({ user_id: 1, kitchen_id: 1, session_id: 1, active: 1 }, { name: 'user_id_1_kitchen_id_1_session_id_1_active_1', unique: true, partialFilterExpression: { active: true } });
// sessions: histórico do usuário na cozinha, mais recente primeiro (recuperar_historico)
dbi.sessions.createIndex({ user_id: 1, kitchen_id: 1, started_at: -1 }, { name: 'user_id_1_kitchen_id_1_started_at_-1' });

// approvals: idempotência por solicitante + cozinha + chave (create_proposal)
dbi.approvals.createIndex({ requester_id: 1, kitchen_id: 1, idempotency_key: 1 }, { name: 'requester_id_1_kitchen_id_1_idempotency_key_1', unique: true });
// approvals: expiração das propostas pendentes (expire_pending)
dbi.approvals.createIndex({ status: 1, expires_at: 1 }, { name: 'status_1_expires_at_1' });

// notifications: caixa de entrada da cozinha, mais recente primeiro (ainda sem escrita pela IAI)
dbi.notifications.createIndex({ kitchen_id: 1, created_at: -1 }, { name: 'kitchen_id_1_created_at_-1' });

// metrics: janela de 7/30 dias de GET /metrics, por cozinha
dbi.metrics.createIndex({ kitchen_id: 1, timestamp: -1 }, { name: 'kitchen_id_1_timestamp_-1' });
