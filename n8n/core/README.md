CORE-00..90. Ver convenção e responsabilidades em `../README.md`.

Nenhum workflow `.json` foi importado ainda (ver `docs/DECISIONS.md#d013` —
o MCP do n8n desta sessão ainda não foi autorizado). Em vez disso, os dois
primeiros workflows da Fase 2 já têm especificação nó-a-nó pronta para
montar diretamente no editor do n8n:

- [`CORE-01-tenant-resolver.md`](./CORE-01-tenant-resolver.md) — sub-workflow,
  resolve `tenant_id` a partir de provider/account/inbox.
- [`CORE-00-inbound-gateway-chatwoot.md`](./CORE-00-inbound-gateway-chatwoot.md) —
  webhook do Chatwoot → Universal Message → persistência → buffer.

Construa o CORE-01 primeiro (é chamado pelo CORE-00). Os demais
(CORE-02 Message Buffer, CORE-03 Context Builder, CORE-10 Agent
Orchestrator, CORE-30 Output Gateway, CORE-90 Logging) ainda não têm
especificação — próximo passo depois que esses dois estiverem validados no
n8n.
