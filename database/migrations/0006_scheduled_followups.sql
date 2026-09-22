-- Cadência de follow-up agendada pela própria IA (via ferramenta TOOL-12
-- "Agendar Follow-up"). A IA decide QUANDO faz sentido reengajar (ex.:
-- cliente disse "vou pensar" ou "te aviso depois") — nesse momento já tem
-- todo o contexto da conversa, então só registra o motivo (auditoria) e a
-- data do primeiro toque. O texto de cada etapa é padronizado pelo sistema
-- (não escrito pela IA por etapa), pra manter tom consistente.
--
-- Cadência fixa: 3 lembretes ("nudge") + 1 mensagem final de encerramento
-- ("ultimatum"), sempre no mesmo cadence_id. Um workflow agendado (CORE-40)
-- varre esta tabela periodicamente e, pra cada etapa vencida:
--   - cancela a etapa (e todo o resto da cadência) se o cliente já
--     respondeu (messages.created_at > scheduled_followups.created_at) ou
--     se um humano assumiu a conversa (conversation_state.status);
--   - senão, envia a mensagem via CORE-30 e marca como enviada.

CREATE TABLE scheduled_followups (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    cadence_id      UUID NOT NULL,   -- agrupa as 4 etapas de uma mesma cadência
    step            INT NOT NULL CHECK (step BETWEEN 1 AND 4),
    kind            TEXT NOT NULL CHECK (kind IN ('nudge', 'ultimatum')),
    reason          TEXT NOT NULL,   -- por que a IA agendou (auditoria, não vai pro cliente)
    message         TEXT NOT NULL,   -- texto pronto a ser enviado quando disparar
    scheduled_for   TIMESTAMPTZ NOT NULL,
    status          TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'sent', 'canceled')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    sent_at         TIMESTAMPTZ
);
CREATE INDEX idx_scheduled_followups_due
    ON scheduled_followups(scheduled_for)
    WHERE status = 'pending';
CREATE INDEX idx_scheduled_followups_cadence
    ON scheduled_followups(cadence_id);
