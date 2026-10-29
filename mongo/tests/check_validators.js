// Confere, depois das migrations, que cada coleção tem o validador esperado, os índices
// esperados e que o $jsonSchema separa documentos válidos dos inválidos.
// Os documentos de teste são removidos no final.
const dbi = db.getSiblingDB(process.env.MONGO_DB || 'dbIAI');
const failures = [];
const check = (ok, msg) => { if (!ok) failures.push(msg); };

const info = (name) => dbi.getCollectionInfos({ name })[0];
for (const name of ['sessions', 'metrics', 'approvals']) {
  const options = (info(name) || {}).options || {};
  check(options.validator && options.validator.$jsonSchema, `${name}: sem validador $jsonSchema`);
  check(options.validationLevel === 'moderate', `${name}: validationLevel = ${options.validationLevel}`);
  check(options.validationAction === 'warn', `${name}: validationAction = ${options.validationAction}`);
}
check(info('notifications'), 'notifications: coleção ausente');

const expectedIndexes = {
  sessions: {
    'user_id_1_kitchen_id_1_session_id_1_active_1': { user_id: 1, kitchen_id: 1, session_id: 1, active: 1 },
    'user_id_1_kitchen_id_1_started_at_-1': { user_id: 1, kitchen_id: 1, started_at: -1 },
  },
  approvals: {
    requester_id_1_kitchen_id_1_idempotency_key_1: { requester_id: 1, kitchen_id: 1, idempotency_key: 1 },
    status_1_expires_at_1: { status: 1, expires_at: 1 },
  },
  notifications: { 'kitchen_id_1_created_at_-1': { kitchen_id: 1, created_at: -1 } },
  metrics: { 'kitchen_id_1_timestamp_-1': { kitchen_id: 1, timestamp: -1 } },
};
for (const [coll, indexes] of Object.entries(expectedIndexes)) {
  const actual = Object.fromEntries(dbi[coll].getIndexes().map((i) => [i.name, i.key]));
  for (const [name, key] of Object.entries(indexes)) {
    check(JSON.stringify(actual[name]) === JSON.stringify(key), `${coll}: índice ${name} ausente ou diferente`);
  }
}
// Índices da V001 trocados pela V002 não podem sobrar (a IAI não os usa mais).
for (const [coll, name] of [['sessions', 'session_id_1'], ['sessions', 'user_id_1_started_at_-1'], ['metrics', 'timestamp_-1']]) {
  check(!dbi[coll].getIndexes().some((i) => i.name === name), `${coll}: índice antigo ${name} ainda existe`);
}
const sessionUnique = dbi.sessions.getIndexes().find((i) => i.name === 'user_id_1_kitchen_id_1_session_id_1_active_1') || {};
check(sessionUnique.unique === true, 'sessions: índice de sessão ativa não é único');
check(JSON.stringify(sessionUnique.partialFilterExpression) === JSON.stringify({ active: true }),
  'sessions: índice de sessão ativa sem filtro parcial active = true');
const approvalUnique = dbi.approvals.getIndexes().find((i) => i.name === 'requester_id_1_kitchen_id_1_idempotency_key_1') || {};
check(approvalUnique.unique === true, 'approvals: índice de idempotência não é único');

// Formato gravado pela IAI (memory.py, metrics.py e approvals.py, branch main).
const now = new Date();
const hash = 'a'.repeat(64);
const session = (id, extra = {}) => ({
  _id: id, session_id: id, user_id: 'ci-user', kitchen_id: 3, active: true, started_at: now, updated_at: now, summary: '',
  messages: [
    { role: 'human', content: 'quantos tomates temos?' },
    { role: 'iai', content: 'Há 12 kg.' },
    { role: 'judge', content: 'sem fato de estoque', confianca: 0.4 },
  ],
  ...extra,
});
const validSession = session('ci-valid-session');
const invalidSessions = [
  session('ci-bad-role', { messages: [{ role: 'admin', content: 'x' }] }),
  session('ci-bad-date', { started_at: '2026-01-01' }),
  session('ci-no-kitchen', { kitchen_id: undefined }),
  session('ci-bad-active', { active: 'sim' }),
];
const jev = {
  id: 'j1', agent: 'estoquista', tool: 'propor_baixa_estoque', attempt: 1, status: 'APPROVE', decision: 'APPROVE',
  checks: { intent_match: 0.97, tool_needed: 0.91 }, failed_checks: [], duration_ms: 412.5,
  model: 'jev-1', usage: { input_tokens: 800, output_tokens: 6 }, custo_usd: 0.0000336,
  created_at: now.toISOString(), decided_at: now.toISOString(), finished_at: now.toISOString(),
};
const validMetric = {
  timestamp: now, session_id: 'ci', user_id: 'ci-user', kitchen_id: 3, latencia_total_ms: 812.4, status: 'ok',
  nos: [{ no: 'roteador', ms: 120.5, erro: false }],
  chamadas: [{ modelo: 'gemini-2.5-flash', tokens_entrada: 900, tokens_saida: 120, custo_usd: 0.00057, latencia_ms: 640.1 }],
  tokens_entrada: 1700, tokens_saida: 126, custo_usd: 0.0006036, erros_componentes: [], resolvida: true,
  agentes_chamados: ['roteador', 'estoquista', 'jev'], llm_mode: 'live', error_type: null,
  jev: [jev], jev_events: [{ event: 'jev_revisao_aprovada', at: now.toISOString(), id: 'j1', agent: 'estoquista', tool: 'propor_baixa_estoque', attempt: 1 }],
  ci: true,
};
const invalidMetrics = [
  { ...validMetric, status: 'timeout' },
  { ...validMetric, custo_usd: -1 },
  { ...validMetric, resolvida: 'sim' },
  { ...validMetric, kitchen_id: undefined },
  { ...validMetric, jev: [{ ...jev, duration_ms: -5 }] },
  { ...validMetric, jev: [{ ...jev, usage: { input_tokens: 'muitos' } }] },
];
const approval = (id, extra = {}) => ({
  _id: id, requester_id: 'ci-user', kitchen_id: 3, idempotency_key: id,
  action: { operation: 'desativar_produto', parameters: { productId: 7 } },
  requester: { user_id: 'ci-user', kitchen_id: 3, role: 'SUPERVISOR', name: 'CI', mocked: false },
  before: [{ parameter: 'productId', record: { id: 7, active: true } }],
  justification: 'produto descontinuado', proposal_hash: hash, status: 'AGUARDANDO_APROVACAO',
  created_at: now, expires_at: now, decided_by: null, decision: null, decided_at: null, result: null, execution_error: null,
  technical_executor: 'iai', business_mode: 'spring', confirmation_policy: 'requester',
  notification: { channel: 'requester_inbox', available: true },
  audit: [{ event: 'PROPOSTA_CRIADA', at: now, actor: 'ci-user' }],
  ...extra,
});
const validApprovals = [
  approval('ci-ap-valid'),
  approval('ci-ap-done', { status: 'CONCLUIDA', decided_by: 'ci-user', decision: 'approve', decided_at: now, executed_at: now, result: { ok: true } }),
  approval('ci-ap-judge', { status: 'RECUSADA', decided_by: 'juiz', decision: 'reject', decided_at: now, judge_cancelled: true }),
];
const invalidApprovals = [
  approval('ci-ap-status', { status: 'PENDENTE' }),
  approval('ci-ap-hash', { proposal_hash: 'curto' }),
  approval('ci-ap-decision', { decision: 'talvez' }),
  approval('ci-ap-audit', { audit: [{ event: 'PROPOSTA_CRIADA' }] }),
  approval('ci-ap-before', { before: [{ record: {} }] }),
];

dbi.sessions.insertMany([validSession, ...invalidSessions]);
dbi.metrics.insertMany([validMetric, ...invalidMetrics].map((m) => ({ ...m, ci: true })));
dbi.approvals.insertMany([...validApprovals, ...invalidApprovals]);

const schemaOf = (name) => info(name).options.validator;
const ciSessions = { _id: { $regex: '^ci-' } };
check(dbi.sessions.countDocuments({ ...ciSessions, $nor: [schemaOf('sessions')] }) === invalidSessions.length,
  'sessions: o validador não separou os documentos inválidos');
check(dbi.sessions.countDocuments({ _id: 'ci-valid-session', ...schemaOf('sessions') }) === 1,
  'sessions: documento válido reprovado');
check(dbi.metrics.countDocuments({ ci: true, $nor: [schemaOf('metrics')] }) === invalidMetrics.length,
  'metrics: o validador não separou os documentos inválidos');
check(dbi.approvals.countDocuments({ _id: { $regex: '^ci-ap-' }, $nor: [schemaOf('approvals')] }) === invalidApprovals.length,
  'approvals: o validador não separou os documentos inválidos');
check(dbi.approvals.countDocuments({ _id: { $in: validApprovals.map((a) => a._id) }, ...schemaOf('approvals') }) === validApprovals.length,
  'approvals: documento válido reprovado');

// Índice único parcial: duas sessões ativas iguais colidem; uma encerrada não conta.
const duplicada = (id, extra) => ({ ...validSession, _id: id, ...extra });
let colidiu = false;
try { dbi.sessions.insertOne(duplicada('ci-dup-ativa', {})); } catch (e) { colidiu = e.code === 11000; }
check(colidiu, 'sessions: duas sessões ativas iguais deveriam violar o índice único');
dbi.sessions.updateOne({ _id: 'ci-valid-session' }, { $set: { active: false } });
let aceitou = true;
try { dbi.sessions.insertOne(duplicada('ci-dup-encerrada', { active: false })); } catch (e) { aceitou = false; }
check(aceitou, 'sessions: sessão encerrada não deveria colidir com a ativa');
// Idempotência: mesma chave de proposta do mesmo solicitante e cozinha é recusada.
let propostaDuplicada = false;
try { dbi.approvals.insertOne(approval('ci-ap-dup', { idempotency_key: 'ci-ap-valid' })); } catch (e) { propostaDuplicada = e.code === 11000; }
check(propostaDuplicada, 'approvals: idempotency_key repetida deveria violar o índice único');

dbi.sessions.deleteMany(ciSessions);
dbi.metrics.deleteMany({ ci: true });
dbi.approvals.deleteMany({ _id: { $regex: '^ci-ap-' } });

for (const version of ['V001', 'V002']) {
  check(dbi.schema_migrations.countDocuments({ _id: version }) === 1, `schema_migrations: ${version} não registrada`);
}

if (failures.length) {
  failures.forEach((f) => print(`FALHA: ${f}`));
  quit(1);
}
print('validadores e índices OK');
