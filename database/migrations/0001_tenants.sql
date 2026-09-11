-- Fundação multi-tenant: todo tenant, seus canais e configuração de CRM/LLM/features.
-- Nenhuma dessas tabelas guarda conhecimento de negócio (FAQ, preços, etc.) —
-- isso vive em knowledge_documents/knowledge_chunks (0004_knowledge.sql).

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE tenants (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_key  TEXT NOT NULL UNIQUE,       -- ex.: "clinica_x" — usado em configs e logs
    name        TEXT NOT NULL,
    timezone    TEXT NOT NULL DEFAULT 'America/Sao_Paulo',
    language    TEXT NOT NULL DEFAULT 'pt-BR',
    enabled     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Flags de feature por tenant (Seção 6 do briefing). 1:1 com tenants.
CREATE TABLE tenant_features (
    tenant_id       UUID PRIMARY KEY REFERENCES tenants(id) ON DELETE CASCADE,
    audio           BOOLEAN NOT NULL DEFAULT FALSE,
    vision          BOOLEAN NOT NULL DEFAULT FALSE,
    calendar        BOOLEAN NOT NULL DEFAULT FALSE,
    knowledge       BOOLEAN NOT NULL DEFAULT FALSE,
    files           BOOLEAN NOT NULL DEFAULT FALSE,
    followup        BOOLEAN NOT NULL DEFAULT FALSE,
    human_handoff   BOOLEAN NOT NULL DEFAULT FALSE,
    buffer_enabled  BOOLEAN NOT NULL DEFAULT TRUE,
    buffer_seconds  INTEGER NOT NULL DEFAULT 4,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Um tenant pode ter múltiplos canais (whatsapp, instagram, ...) por provider de CRM.
CREATE TABLE tenant_channels (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    provider            TEXT NOT NULL,      -- 'chatwoot' | 'kommo' | 'datacry'
    channel             TEXT NOT NULL,      -- 'whatsapp' | 'instagram' | 'facebook' | 'webchat'
    external_account_id TEXT,
    external_inbox_id   TEXT,
    enabled             BOOLEAN NOT NULL DEFAULT TRUE,
    config              JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, provider, channel, external_account_id)
);
CREATE INDEX idx_tenant_channels_tenant_id ON tenant_channels(tenant_id);

-- Config de CRM do tenant. Um provider ativo por tenant no desenho atual.
CREATE TABLE tenant_crm_config (
    tenant_id   UUID PRIMARY KEY REFERENCES tenants(id) ON DELETE CASCADE,
    provider    TEXT NOT NULL,      -- 'chatwoot' | 'kommo' | 'datacry'
    config      JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Config de LLM do tenant (profile + fallback). Ver llm_models (0003) para o registry real.
CREATE TABLE tenant_llm_config (
    tenant_id         UUID PRIMARY KEY REFERENCES tenants(id) ON DELETE CASCADE,
    profile           TEXT NOT NULL DEFAULT 'balanced',
    fallback_enabled  BOOLEAN NOT NULL DEFAULT TRUE,
    config            JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
