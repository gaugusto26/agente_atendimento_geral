-- Conhecimento de negócio (Seção 16), sempre separado de Tenant Config e do
-- prompt do agente. pgvector é o backend padrão de busca vetorial (Seção 17
-- do briefing / D007 em docs/DECISIONS.md) — Supabase não é obrigatório.
--
-- Se a extensão "vector" não estiver disponível no Postgres de destino, esta
-- migration falha explicitamente em vez de degradar silenciosamente: o
-- índice ivfflat/embedding fica para uma migration futura, quando o volume
-- de chunks por tenant justificar o tuning (lists, probes etc.).

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE knowledge_documents (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    category    TEXT NOT NULL CHECK (category IN (
                    'COMPANY','SERVICE','PRODUCT','PRICING','FAQ','POLICY',
                    'PROFESSIONAL','LOCATION','PAYMENT','SALES'
                )),
    title       TEXT,
    content     TEXT NOT NULL,
    source      TEXT,          -- origem do documento (upload, URL, importação manual)
    metadata    JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_knowledge_documents_tenant_category
    ON knowledge_documents(tenant_id, category);

CREATE TABLE knowledge_chunks (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    document_id   UUID NOT NULL REFERENCES knowledge_documents(id) ON DELETE CASCADE,
    chunk_index   INTEGER NOT NULL,
    content       TEXT NOT NULL,
    embedding     VECTOR(1536),  -- dimensão do provider de embeddings configurado; ajustar por tenant/modelo se necessário
    metadata      JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (document_id, chunk_index)
);
CREATE INDEX idx_knowledge_chunks_tenant_id ON knowledge_chunks(tenant_id);

-- TODO(fase 5): criar índice ivfflat/hnsw em `embedding` quando o volume de
-- chunks por tenant estiver definido (o tipo de índice e os parâmetros
-- dependem de contagem de linhas real, não deve ser adivinhado agora).
