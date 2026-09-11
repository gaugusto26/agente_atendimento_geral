-- Sessões/eventos de agente, registry de modelos de LLM e log de chamadas
-- (LLM e Tools). Cobre a observabilidade estruturada exigida (Seção 18) e o
-- Model Registry (Seção 12), mantendo LLM e Embeddings como dimensões
-- independentes (um tenant pode usar Anthropic para chat e OpenAI para
-- embeddings).

CREATE TABLE agent_sessions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    agent_type      TEXT NOT NULL,   -- 'general' | 'sales' | 'secretary' | 'internal'
    status          TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'ended')),
    started_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at        TIMESTAMPTZ
);
CREATE INDEX idx_agent_sessions_tenant_conversation
    ON agent_sessions(tenant_id, conversation_id);

-- Eventos estruturados (Seção 18): message_received, llm_requested,
-- tool_failed, handoff_requested, etc. correlacionáveis por trace_id.
CREATE TABLE agent_events (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id         UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    conversation_id   UUID REFERENCES conversations(id) ON DELETE SET NULL,
    agent_session_id  UUID REFERENCES agent_sessions(id) ON DELETE SET NULL,
    event_type        TEXT NOT NULL,
    payload           JSONB NOT NULL DEFAULT '{}'::jsonb,  -- nunca conter secrets
    trace_id          UUID NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_agent_events_tenant_created ON agent_events(tenant_id, created_at);
CREATE INDEX idx_agent_events_trace_id ON agent_events(trace_id);

-- Model Registry (Seção 12). provider+model é a chave; supports_embeddings
-- distingue modelos de chat de modelos de embedding no mesmo registry.
CREATE TABLE llm_models (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider              TEXT NOT NULL,   -- 'openai' | 'anthropic' | 'google' | ...
    model                 TEXT NOT NULL,
    enabled               BOOLEAN NOT NULL DEFAULT TRUE,
    supports_tools        BOOLEAN NOT NULL DEFAULT FALSE,
    supports_vision       BOOLEAN NOT NULL DEFAULT FALSE,
    supports_json         BOOLEAN NOT NULL DEFAULT FALSE,
    supports_embeddings   BOOLEAN NOT NULL DEFAULT FALSE,
    priority              INTEGER NOT NULL DEFAULT 100,
    max_context           INTEGER,
    timeout_ms            INTEGER NOT NULL DEFAULT 30000,
    cost_input            NUMERIC(12,6),   -- custo por 1k tokens de entrada
    cost_output           NUMERIC(12,6),   -- custo por 1k tokens de saída
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (provider, model)
);

CREATE TABLE llm_calls (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    conversation_id     UUID REFERENCES conversations(id) ON DELETE SET NULL,
    agent_session_id    UUID REFERENCES agent_sessions(id) ON DELETE SET NULL,
    profile             TEXT,   -- 'FAST' | 'STANDARD' | 'ADVANCED' | 'VISION' | 'STRUCTURED'
    provider_requested  TEXT,
    model_requested     TEXT,
    provider_used       TEXT,
    model_used          TEXT,
    fallback_used       BOOLEAN NOT NULL DEFAULT FALSE,
    fallback_reason     TEXT,
    latency_ms          INTEGER,
    tokens_input        INTEGER,
    tokens_output       INTEGER,
    cost_estimated      NUMERIC(12,6),
    error               TEXT,
    trace_id            UUID NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_llm_calls_tenant_created ON llm_calls(tenant_id, created_at);
CREATE INDEX idx_llm_calls_trace_id ON llm_calls(trace_id);

CREATE TABLE tool_calls (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id          UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    conversation_id    UUID REFERENCES conversations(id) ON DELETE SET NULL,
    agent_session_id   UUID REFERENCES agent_sessions(id) ON DELETE SET NULL,
    tool               TEXT NOT NULL,   -- 'crm' | 'calendar' | 'knowledge' | 'files' | 'handoff' | 'tasks'
    action             TEXT NOT NULL,
    arguments          JSONB,
    success            BOOLEAN,
    result             JSONB,
    error              TEXT,
    trace_id           UUID NOT NULL,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_tool_calls_tenant_created ON tool_calls(tenant_id, created_at);
