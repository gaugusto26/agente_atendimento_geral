-- Lista de contatos que o agente nunca deve processar, independente de tenant/canal
-- (ex.: números internos de alerta/monitoramento, testes, pessoas que pediram para
-- nunca receber resposta automática). Complementa a exclusão de grupos, que é
-- detectada direto no payload do Chatwoot (D022) e não precisa de tabela.

CREATE TABLE excluded_contacts (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID REFERENCES tenants(id) ON DELETE CASCADE,  -- NULL = vale para todos os tenants
    phone       TEXT NOT NULL,   -- formato exatamente como o Chatwoot normaliza (ex.: "+5515981772842")
    reason      TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_excluded_contacts_phone ON excluded_contacts(phone);
