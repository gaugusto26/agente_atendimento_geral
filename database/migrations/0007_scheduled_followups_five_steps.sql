-- Cadencia de follow-up (D032) ajustada de dias pra horas, e de 4 pra 5
-- etapas: 4 lembretes ("nudge") em 5h/12h/24h/36h sem resposta + 1
-- mensagem final de encerramento ("ultimatum") em 48h (D034). O texto de
-- cada etapa continua fixo no TOOL-12, so o numero de etapas mudou.

ALTER TABLE scheduled_followups DROP CONSTRAINT IF EXISTS scheduled_followups_step_check;
ALTER TABLE scheduled_followups ADD CONSTRAINT scheduled_followups_step_check CHECK (step BETWEEN 1 AND 5);
