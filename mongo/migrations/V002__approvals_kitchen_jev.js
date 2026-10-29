// V002: contrato do dbIAI depois do human-in-the-loop (IAI PR #24) e do JEV como juiz único.
// - sessions: conversa por usuário + cozinha (kitchen_id, active) com índice único parcial.
// - metrics: kitchen_id, custo/latência/tokens do JEV (jev, jev_events) e llm_mode.
// - approvals (nova): propostas de ação aguardando o solicitante, com auditoria embutida.
// - notifications (nova): a IAI só cria o índice por enquanto; sem validador.
// Idempotente: cria a coleção ou atualiza o validador com collMod; createIndex não duplica;
// dropIndex só roda se o índice existir.
// Os nomes dos índices repetem o padrão do driver porque a IAI também chama create_index no startup:
// nome diferente para a mesma chave (ou opções diferentes) gera erro na subida da IAI.
// Não reescreve documentos antigos: sessões e métricas sem kitchen_id continuam gravadas, mas a IAI
// só enxerga documentos da cozinha do usuário (backfill é decisão de produto, fora desta migration).
// Uso: mongosh "$MONGO_URI" --file migrations/V002__approvals_kitchen_jev.js
const dbi = db.getSiblingDB(process.env.MONGO_DB || 'dbIAI');

// moderate + warn: documento fora do contrato é aceito e registrado no log do mongod.
function ensureCollection(name, schema) {
  const options = { validator: { $jsonSchema: schema }, validationLevel: 'moderate', validationAction: 'warn' };
  if (dbi.getCollectionNames().includes(name)) {
    dbi.runCommand({ collMod: name, ...options });
  } else {
    dbi.createCollection(name, options);
  }
}

function dropIndexIfExists(coll, name) {
  if (dbi.getCollectionNames().includes(coll) && dbi[coll].getIndexes().some((i) => i.name === name)) {
    dbi[coll].dropIndex(name);
  }
}

ensureCollection('sessions', {
  "bsonType": "object",
  "title": "dbIAI.sessions",
  "description": "Uma conversa do chat da IA, de um usuário em uma cozinha. Ativa enquanto active = true; /chat/encerrar grava o resumo e fecha a sessão.",
  "required": [
    "_id",
    "session_id",
    "user_id",
    "kitchen_id",
    "active",
    "started_at",
    "updated_at",
    "summary",
    "messages"
  ],
  "properties": {
    "_id": {
      "bsonType": "string",
      "description": "UUID v4 gerado pela IAI (doc_id devolvido em /chat/historico)"
    },
    "session_id": {
      "bsonType": "string",
      "description": "Identificador da conversa enviado pelo app; pode se repetir entre sessões encerradas"
    },
    "user_id": {
      "bsonType": "string",
      "description": "Dono da conversa; junto com kitchen_id isola o histórico (tool buscar_historico)"
    },
    "kitchen_id": {
      "bsonType": [
        "int",
        "long"
      ],
      "minimum": 1,
      "description": "Cozinha da conversa; o histórico nunca atravessa cozinhas"
    },
    "active": {
      "bsonType": "bool",
      "description": "true = conversa aberta (no máximo uma por user_id + kitchen_id + session_id); /chat/encerrar muda para false"
    },
    "started_at": {
      "bsonType": "date"
    },
    "updated_at": {
      "bsonType": "date"
    },
    "summary": {
      "bsonType": "string",
      "description": "Resumo gerado pelo LLM ao encerrar; vazio enquanto a sessão está ativa"
    },
    "messages": {
      "bsonType": "array",
      "items": {
        "bsonType": "object",
        "required": [
          "role",
          "content"
        ],
        "properties": {
          "role": {
            "enum": [
              "human",
              "iai",
              "judge"
            ],
            "description": "judge = reprovação do juiz, só para auditoria"
          },
          "content": {
            "bsonType": "string",
            "description": "Texto já anonimizado (e-mail, CPF, RG e telefone viram tokens)"
          },
          "confianca": {
            "bsonType": [
              "double",
              "int"
            ],
            "minimum": 0,
            "description": "Só em role = judge",
            "maximum": 1
          }
        }
      }
    }
  }
});

ensureCollection('metrics', {
  "bsonType": "object",
  "title": "dbIAI.metrics",
  "description": "Um documento por requisição de /chat (ColetorMetricas). Não guarda o texto do prompt nem os argumentos das ferramentas.",
  "required": [
    "timestamp",
    "session_id",
    "user_id",
    "kitchen_id",
    "latencia_total_ms",
    "status",
    "nos",
    "chamadas",
    "tokens_entrada",
    "tokens_saida",
    "custo_usd",
    "erros_componentes",
    "resolvida",
    "agentes_chamados"
  ],
  "properties": {
    "timestamp": {
      "bsonType": "date",
      "description": "Janela de GET /metrics (7 ou 30 dias)"
    },
    "session_id": {
      "bsonType": "string"
    },
    "user_id": {
      "bsonType": "string"
    },
    "kitchen_id": {
      "bsonType": [
        "int",
        "long"
      ],
      "minimum": 1,
      "description": "Cozinha da requisição; GET /metrics só soma a cozinha do usuário"
    },
    "latencia_total_ms": {
      "bsonType": [
        "double",
        "int"
      ],
      "minimum": 0
    },
    "status": {
      "enum": [
        "ok",
        "bloqueado",
        "erro"
      ],
      "description": "bloqueado = guardrail de entrada recusou; não conta como erro"
    },
    "nos": {
      "bsonType": "array",
      "items": {
        "bsonType": "object",
        "required": [
          "no",
          "ms",
          "erro"
        ],
        "properties": {
          "no": {
            "bsonType": "string",
            "description": "Nó do grafo LangGraph"
          },
          "ms": {
            "bsonType": [
              "double",
              "int"
            ],
            "minimum": 0
          },
          "erro": {
            "bsonType": "bool"
          }
        }
      }
    },
    "chamadas": {
      "bsonType": "array",
      "items": {
        "bsonType": "object",
        "required": [
          "modelo",
          "tokens_entrada",
          "tokens_saida",
          "custo_usd",
          "latencia_ms"
        ],
        "properties": {
          "modelo": {
            "bsonType": "string"
          },
          "tokens_entrada": {
            "bsonType": [
              "int",
              "long"
            ],
            "minimum": 0
          },
          "tokens_saida": {
            "bsonType": [
              "int",
              "long"
            ],
            "minimum": 0
          },
          "custo_usd": {
            "bsonType": [
              "double",
              "int"
            ],
            "minimum": 0
          },
          "latencia_ms": {
            "bsonType": [
              "double",
              "int"
            ],
            "minimum": 0
          }
        }
      },
      "description": "Uma entrada por chamada de LLM (Gemini e Groq); o JEV fica em jev[]"
    },
    "tokens_entrada": {
      "bsonType": [
        "int",
        "long"
      ],
      "minimum": 0,
      "description": "Soma de chamadas[] mais os tokens informados pelo JEV"
    },
    "tokens_saida": {
      "bsonType": [
        "int",
        "long"
      ],
      "minimum": 0,
      "description": "Soma de chamadas[] mais os tokens informados pelo JEV"
    },
    "custo_usd": {
      "bsonType": [
        "double",
        "int"
      ],
      "minimum": 0,
      "description": "Custo do turno: LLMs (chamadas[]) mais o JEV (jev[].custo_usd)"
    },
    "erros_componentes": {
      "bsonType": "array",
      "items": {
        "bsonType": "string"
      },
      "description": "llm:*, tool:*, chain:*, jev:*, inclusive os recuperados por fallback"
    },
    "resolvida": {
      "bsonType": "bool",
      "description": "Execução autorizada concluída ou FAQ respondida; bloqueio e erro nunca contam"
    },
    "agentes_chamados": {
      "bsonType": "array",
      "items": {
        "bsonType": "string"
      },
      "description": "Ex.: guardrail_insulto, estoquista, jev, faq (sem o motivo, que fica depois dos dois pontos)"
    },
    "llm_mode": {
      "bsonType": "string",
      "description": "Modo da IAI na requisição (live ou demo)"
    },
    "jev": {
      "bsonType": "array",
      "items": {
        "bsonType": "object",
        "properties": {
          "id": {
            "bsonType": "string",
            "description": "Identificador do julgamento"
          },
          "agent": {
            "bsonType": "string",
            "description": "Especialista julgado (estoquista, comprador, supervisor, faq)"
          },
          "tool": {
            "bsonType": "string",
            "description": "propor_* julgada, ou resposta_final quando o JEV julga o texto da resposta"
          },
          "attempt": {
            "bsonType": [
              "int",
              "long"
            ],
            "minimum": 0,
            "description": "1 = primeira execução do especialista, 2 = nova execução depois de uma reprovação"
          },
          "status": {
            "bsonType": "string"
          },
          "decision": {
            "bsonType": "string",
            "description": "APPROVE, RETRY_SPECIALIST, ASK_USER ou REJECT; mensagens da validação local não têm decisão do JEV"
          },
          "checks": {
            "bsonType": "object",
            "description": "Probabilidade (0 a 1) de cada critério avaliado pelo JEV",
            "additionalProperties": {
              "bsonType": [
                "double",
                "int"
              ]
            }
          },
          "failed_checks": {
            "bsonType": "array",
            "items": {
              "bsonType": "string"
            },
            "description": "Critérios que ficaram abaixo do limiar"
          },
          "duration_ms": {
            "bsonType": [
              "double",
              "int"
            ],
            "minimum": 0,
            "description": "Latência da chamada ao JEV"
          },
          "model": {
            "bsonType": "string",
            "description": "Modelo do JEV que respondeu"
          },
          "usage": {
            "bsonType": "object",
            "description": "Tokens informados pelo JEV",
            "properties": {
              "input_tokens": {
                "bsonType": [
                  "int",
                  "long"
                ],
                "minimum": 0
              },
              "output_tokens": {
                "bsonType": [
                  "int",
                  "long"
                ],
                "minimum": 0
              }
            }
          },
          "custo_usd": {
            "bsonType": [
              "double",
              "int"
            ],
            "minimum": 0,
            "description": "Estimativa do custo desta chamada (só tokens de entrada são cobrados)"
          },
          "error_type": {
            "bsonType": "string",
            "description": "Código seguro da falha do JEV (sem texto de SDK nem corpo HTTP)"
          },
          "created_at": {
            "bsonType": "string",
            "description": "ISO 8601 (texto)"
          },
          "decided_at": {
            "bsonType": "string",
            "description": "ISO 8601 (texto)"
          },
          "finished_at": {
            "bsonType": "string",
            "description": "ISO 8601 (texto)"
          }
        }
      },
      "description": "Uma entrada por julgamento do JEV no turno (propostas e resposta final)"
    },
    "jev_events": {
      "bsonType": "array",
      "items": {
        "bsonType": "object",
        "required": [
          "event",
          "at"
        ],
        "properties": {
          "event": {
            "bsonType": "string",
            "description": "Ex.: jev_revisao_aprovada, jev_revisao_reprovada, validacao_local_aprovada"
          },
          "at": {
            "bsonType": "string",
            "description": "ISO 8601 (texto)"
          },
          "id": {
            "bsonType": "string"
          },
          "agent": {
            "bsonType": "string"
          },
          "tool": {
            "bsonType": "string"
          },
          "attempt": {
            "bsonType": [
              "int",
              "long"
            ],
            "minimum": 0
          }
        }
      },
      "description": "Linha do tempo técnica dos julgamentos, sem argumentos nem conversa"
    },
    "error_type": {
      "bsonType": [
        "string",
        "null"
      ],
      "description": "Tipo da exceção quando status = erro"
    }
  }
});

ensureCollection('approvals', {
  "bsonType": "object",
  "title": "dbIAI.approvals",
  "description": "Proposta de ação sobre o estoque criada pela IA (tools propor_*). Nada é executado até o próprio solicitante aprovar; a proposta é imutável (proposal_hash) e carrega a própria auditoria.",
  "required": [
    "_id",
    "requester_id",
    "kitchen_id",
    "idempotency_key",
    "action",
    "requester",
    "before",
    "justification",
    "proposal_hash",
    "status",
    "created_at",
    "expires_at",
    "audit"
  ],
  "properties": {
    "_id": {
      "bsonType": "string",
      "description": "SHA-256 de [user_id, kitchen_id, idempotency_key]; repetir a mesma proposta devolve o mesmo documento"
    },
    "requester_id": {
      "bsonType": "string",
      "description": "Quem pediu e o único que pode aprovar"
    },
    "kitchen_id": {
      "bsonType": [
        "int",
        "long"
      ],
      "minimum": 1
    },
    "idempotency_key": {
      "bsonType": "string",
      "description": "sha256(turn_id:impressão da ação); um novo turno gera outra chave"
    },
    "action": {
      "bsonType": "object",
      "required": [
        "operation",
        "parameters"
      ],
      "properties": {
        "operation": {
          "bsonType": "string",
          "description": "Operação de negócio, ex.: criar_produto, desativar_fornecedor"
        },
        "parameters": {
          "bsonType": "object",
          "description": "Parâmetros já validados; números como texto decimal"
        }
      }
    },
    "requester": {
      "bsonType": "object",
      "description": "Identidade no momento da proposta",
      "required": [
        "user_id",
        "kitchen_id",
        "role"
      ],
      "properties": {
        "user_id": {
          "bsonType": "string"
        },
        "kitchen_id": {
          "bsonType": [
            "int",
            "long"
          ],
          "minimum": 1
        },
        "role": {
          "bsonType": "string",
          "description": "ESTOQUISTA, COMPRADOR ou SUPERVISOR"
        },
        "name": {
          "bsonType": "string"
        },
        "mocked": {
          "bsonType": "bool"
        }
      }
    },
    "before": {
      "bsonType": "array",
      "items": {
        "bsonType": "object",
        "required": [
          "parameter"
        ],
        "properties": {
          "parameter": {
            "bsonType": "string",
            "description": "Parâmetro da ação que aponta para o registro (ex.: batchId)"
          },
          "record": {
            "bsonType": [
              "object",
              "null"
            ],
            "description": "Retrato do registro da API Spring antes da proposta; null quando é uma checagem de inexistência"
          }
        }
      },
      "description": "Estado do estoque no momento da proposta; a execução revalida e recusa se mudou"
    },
    "justification": {
      "bsonType": "string",
      "description": "Motivo informado pelo especialista (até 1000 caracteres)"
    },
    "proposal_hash": {
      "bsonType": "string",
      "description": "SHA-256 de action + requester + before + justification; a decisão precisa repeti-lo",
      "pattern": "^[a-f0-9]{64}$"
    },
    "status": {
      "enum": [
        "AGUARDANDO_APROVACAO",
        "APROVADA_PENDENTE_INTEGRACAO",
        "EM_EXECUCAO",
        "CONCLUIDA",
        "RECUSADA",
        "FALHOU",
        "EXPIRADA",
        "RESULTADO_INCERTO"
      ],
      "description": "RECUSADA também vale para propostas canceladas pelo juiz (judge_cancelled = true)"
    },
    "created_at": {
      "bsonType": "date"
    },
    "expires_at": {
      "bsonType": "date",
      "description": "created_at + 7 dias; expirada deixa de poder ser aprovada"
    },
    "decided_by": {
      "bsonType": [
        "string",
        "null"
      ],
      "description": "user_id de quem decidiu, ou juiz quando o JEV cancelou"
    },
    "decision": {
      "enum": [
        "approve",
        "reject",
        null
      ],
      "description": "null enquanto aguarda"
    },
    "decision_reason": {
      "bsonType": [
        "string",
        "null"
      ]
    },
    "decided_at": {
      "bsonType": [
        "date",
        "null"
      ]
    },
    "judge_cancelled": {
      "bsonType": "bool",
      "description": "true = o JEV reprovou antes de a proposta chegar ao usuário; fica só para auditoria e some das listas"
    },
    "execution_started_at": {
      "bsonType": "date"
    },
    "executed_at": {
      "bsonType": "date"
    },
    "result": {
      "bsonType": [
        "object",
        "null"
      ],
      "description": "Resultado devolvido pela API Spring (ToolResult)"
    },
    "execution_error": {
      "bsonType": [
        "string",
        "null"
      ]
    },
    "exception_type": {
      "bsonType": "string",
      "description": "Tipo da exceção quando a execução falhou depois de iniciar"
    },
    "technical_executor": {
      "bsonType": "string",
      "description": "Quem executa: iai"
    },
    "business_mode": {
      "bsonType": "string",
      "description": "spring (API real) ou mock (dados de demonstração)"
    },
    "confirmation_policy": {
      "bsonType": "string",
      "description": "requester: só o solicitante confirma"
    },
    "notification": {
      "bsonType": "object",
      "properties": {
        "channel": {
          "bsonType": "string"
        },
        "available": {
          "bsonType": "bool"
        }
      }
    },
    "audit": {
      "bsonType": "array",
      "items": {
        "bsonType": "object",
        "required": [
          "event",
          "at",
          "actor"
        ],
        "properties": {
          "event": {
            "bsonType": "string",
            "description": "PROPOSTA_CRIADA, APROVADA_PENDENTE_INTEGRACAO, RECUSADA, CANCELADA_PELO_JUIZ, EM_EXECUCAO, CONCLUIDA, FALHOU, EXPIRADA, RESULTADO_INCERTO"
          },
          "at": {
            "bsonType": "date"
          },
          "actor": {
            "bsonType": "string",
            "description": "user_id, iai ou juiz"
          }
        }
      },
      "description": "Só cresce; nunca é reescrita"
    }
  }
});

if (!dbi.getCollectionNames().includes('notifications')) {
  dbi.createCollection('notifications');
}

// sessions: uma sessão ativa por usuário + cozinha + session_id (criação concorrente cai no DuplicateKeyError da IAI)
dbi.sessions.createIndex(
  { user_id: 1, kitchen_id: 1, session_id: 1, active: 1 },
  { name: 'user_id_1_kitchen_id_1_session_id_1_active_1', unique: true, partialFilterExpression: { active: true } }
);
// sessions: histórico do usuário na cozinha, mais recente primeiro (recuperar_historico)
dbi.sessions.createIndex({ user_id: 1, kitchen_id: 1, started_at: -1 }, { name: 'user_id_1_kitchen_id_1_started_at_-1' });
// approvals: idempotência por solicitante + cozinha + chave
dbi.approvals.createIndex(
  { requester_id: 1, kitchen_id: 1, idempotency_key: 1 },
  { name: 'requester_id_1_kitchen_id_1_idempotency_key_1', unique: true }
);
// approvals: expiração das propostas pendentes (expire_pending)
dbi.approvals.createIndex({ status: 1, expires_at: 1 }, { name: 'status_1_expires_at_1' });
// notifications: caixa de entrada da cozinha, mais recente primeiro
dbi.notifications.createIndex({ kitchen_id: 1, created_at: -1 }, { name: 'kitchen_id_1_created_at_-1' });
// metrics: janela de 7/30 dias de GET /metrics, por cozinha
dbi.metrics.createIndex({ kitchen_id: 1, timestamp: -1 }, { name: 'kitchen_id_1_timestamp_-1' });

// Substituídos pelos índices acima: toda consulta da IAI já filtra por cozinha.
dropIndexIfExists('sessions', 'session_id_1');
dropIndexIfExists('sessions', 'user_id_1_started_at_-1');
dropIndexIfExists('metrics', 'timestamp_-1');

dbi.schema_migrations.updateOne(
  { _id: 'V002' },
  { $set: { description: 'approvals_kitchen_jev' }, $setOnInsert: { applied_at: new Date() } },
  { upsert: true }
);
