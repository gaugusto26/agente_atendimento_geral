-- Contatos, conversas, mensagens, estado IA×Humano e o buffer de agregação.
--
-- Correção deliberada em relação ao projeto de referência: lá, o buffer e a
-- memória eram chaveados só por "telefone" (coluna n8n_fila_mensagens.telefone),
-- o que colide entre tenants diferentes. Aqui toda chave de agregação é
-- (tenant_id, conversation_id).

CREATE TABLE contacts (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id    UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    external_id  TEXT NOT NULL,     -- id do contato no CRM/canal de origem
    name         TEXT,
    phone        TEXT,
    metadata     JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, external_id)
);
CREATE INDEX idx_contacts_tenant_phone ON contacts(tenant_id, phone);

CREATE TABLE conversations (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id    UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    contact_id   UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    provider     TEXT NOT NULL,     -- 'chatwoot' | 'kommo' | 'datacry'
    external_id  TEXT NOT NULL,     -- id da conversa no provider
    channel      TEXT NOT NULL,     -- 'whatsapp' | 'instagram' | ...
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, provider, external_id)
);
CREATE INDEX idx_conversations_tenant_id ON conversations(tenant_id);
CREATE INDEX idx_conversations_contact_id ON conversations(contact_id);

-- Estado IA×Humano (Seção 8). Independente de como cada CRM representa isso
-- (label no Chatwoot, campo customizado no Kommo, etc.) — a tradução é
-- responsabilidade do respectivo CRM Adapter, nunca do Agent Core.
CREATE TABLE conversation_state (
    conversation_id  UUID PRIMARY KEY REFERENCES conversations(id) ON DELETE CASCADE,
    tenant_id        UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    status           TEXT NOT NULL DEFAULT 'AI_ACTIVE'
                        CHECK (status IN ('AI_ACTIVE', 'AI_PAUSED', 'HUMAN_ACTIVE', 'CLOSED')),
    commercial_stage TEXT
                        CHECK (commercial_stage IS NULL OR commercial_stage IN (
                            'NEW','IN_SERVICE','QUALIFYING','QUALIFIED','PROPOSAL',
                            'WAITING_CUSTOMER','SCHEDULED','HUMAN','WON','LOST'
                        )),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by       TEXT        -- 'system' | 'agent' | 'human:<user_id>'
);
CREATE INDEX idx_conversation_state_tenant_status ON conversation_state(tenant_id, status);

CREATE TABLE messages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    external_id     TEXT,          -- id da mensagem no provider (dedupe de webhook)
    direction       TEXT NOT NULL CHECK (direction IN ('incoming', 'outgoing')),
    type            TEXT NOT NULL, -- 'text' | 'audio' | 'image' | 'file' | ...
    text            TEXT,
    raw             JSONB,         -- payload normalizado (Universal Message), nunca o payload nativo do provider
    processed_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, conversation_id, external_id)
);
CREATE INDEX idx_messages_tenant_conversation_created
    ON messages(tenant_id, conversation_id, created_at);

-- Fila de agregação (substitui n8n_fila_mensagens do projeto de referência).
-- Chave de agregação obrigatória: tenant_id + conversation_id.
CREATE TABLE message_buffer (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    message_id      UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    consumed_at     TIMESTAMPTZ,   -- preenchido quando agregada/processada
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_message_buffer_pending
    ON message_buffer(tenant_id, conversation_id, created_at)
    WHERE consumed_at IS NULL;
