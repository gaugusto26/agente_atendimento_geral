# CORE-00 — Inbound Gateway (Chatwoot)

**Tipo de workflow**: exposto por Webhook (é o único ponto de entrada
público desta primeira fatia da plataforma).

**Responsabilidade única**: receber o payload nativo do Chatwoot, traduzi-lo
para o Universal Message (`schemas/universal-message.schema.json`),
resolver o tenant, persistir e enfileirar para o Message Buffer. Nenhum nó
aqui decide *o que responder* — isso é do CORE-10 Agent Orchestrator, mais
adiante.

Cada provider (Chatwoot, Kommo, DataCry) tem seu **próprio** workflow
CORE-00, porque o formato do payload de entrada é diferente por provider —
mas todos convergem para o mesmo Universal Message e chamam os mesmos
CORE-01/CORE-02 como sub-workflow. Este documento cobre só Chatwoot (Fase
2); os outros ficam para as Fases 6/7.

## Nós

1. **Webhook** (`n8n-nodes-base.webhook`)
   - Method: `POST`.
   - Path: gerar um UUID novo no momento de criar o workflow (nunca
     reaproveitar um `webhookId` de outro projeto/ambiente).
   - Configurar esse mesmo path como webhook de conversa no Chatwoot
     (Settings → Integrations → Webhooks), evento `conversation_updated` e
     `message_created` no mínimo.
   - Response Mode: **"Using 'Respond to Webhook' Node"** (não "Immediately")
     — precisamos responder só depois de persistir, para o Chatwoot não
     reenviar por timeout percebido.

2. **IF — "É mensagem de entrada?"** (`n8n-nodes-base.if`)
   - Condição: `{{ $json.body.message_type }}` *equals* `"incoming"`.
   - Branch falso → **Respond to Webhook** direto (200, corpo `{"ignored":
     true}`) e workflow termina. (Diferente do projeto de referência: aqui
     **não** filtramos por label `agente-off` neste ponto — toda mensagem
     de entrada é persistida independentemente do estado IA×Humano; quem
     decide não responder automaticamente é o Agent Orchestrator, lendo
     `conversation_state`. Isso é a decisão D003.)

3. **Set — "Extrair campos Chatwoot"** (`n8n-nodes-base.set`)
   - Esta é a única parte do workflow que conhece o formato nativo do
     Chatwoot. Nenhum nó depois deste deve ler `$json.body.*` diretamente.
   - Campos a extrair (todos como expressão `={{ ... }}`):
     - `provider` = `"chatwoot"`
     - `channel` = mapear a partir do tipo de inbox do Chatwoot (ex.:
       `{{ $json.body.inbox?.channel_type?.includes('Whatsapp') ? 'whatsapp' : 'webchat' }}`
       — ajustar conforme os `channel_type` reais do Chatwoot em uso.
     - `account_id` = `={{ $json.body.account.id }}`
     - `inbox_id` = `={{ $json.body.inbox.id }}`
     - `contact_external_id` = `={{ $json.body.sender.id }}`
     - `contact_name` = `={{ $json.body.sender.name }}`
     - `contact_phone` = `={{ $json.body.sender.phone_number }}`
     - `conversation_external_id` = `={{ $json.body.conversation.id }}`
     - `message_external_id` = `={{ $json.body.id }}`
     - `message_type` = `={{ $json.body.attachments?.length ? $json.body.attachments[0].file_type : 'text' }}`
     - `message_text` = `={{ $json.body.content || '' }}`
     - `message_timestamp` = `={{ $json.body.created_at }}` (ISO-8601; se o
       Chatwoot mandar epoch, converter com `.toDateTime()`)

4. **Execute Workflow — "CORE-01 Tenant Resolver"**
   (`n8n-nodes-base.executeWorkflow`)
   - Source: "Database" (selecionar o workflow CORE-01 pelo nome/ID).
   - Input: mapear `provider`, `channel`, `account_id`, `inbox_id` do item
     atual.

5. **IF — "Tenant resolvido?"**
   - Condição: `{{ $json.resolved }}` *is true*.
   - Branch falso → **Postgres — "Log evento: tenant_resolution_failed"**
     (insert em `agent_events`, `event_type = 'tenant_resolution_failed'`,
     `payload` com `provider`/`account_id`/`inbox_id`, `trace_id` novo) →
     **Respond to Webhook** (200, `{"ignored": true, "reason":
     "unknown_tenant"}`) → fim. Nunca erro 4xx/5xx para o Chatwoot por um
     tenant não configurado — isso pertence a operação/monitoramento, não a
     um retry de webhook.

6. **Code — "Montar Universal Message"** (`n8n-nodes-base.code`, branch
   verdadeiro)
   - Monta exatamente o formato de
     `schemas/universal-message.schema.json`, combinando o `tenant_id`
     vindo do CORE-01 com os campos extraídos no passo 3. Também valida os
     campos obrigatórios (`tenant_id`, `source.provider`, `source.channel`,
     `contact.external_id`, `conversation.external_id`, `message.id`,
     `message.direction`, `message.type`, `message.timestamp`) e lança erro
     (`throw new Error(...)`) se algum estiver faltando — isso interrompe o
     workflow e o n8n reporta falha de execução, visível no painel de
     execuções.
   - Não há dependência de biblioteca externa (ajv etc.) — validação manual
     dos campos obrigatórios é suficiente aqui e evita depender de pacotes
     npm que podem não estar liberados no Code node do ambiente n8n.

7. **Postgres — "Upsert contato"** (`n8n-nodes-base.postgres`, operação
   *Insert or Update*, tabela `contacts`, colunas de match:
   `tenant_id, external_id`)

8. **Postgres — "Upsert conversa"** (mesma técnica, tabela `conversations`,
   colunas de match: `tenant_id, provider, external_id`; `contact_id` vem
   do resultado do passo anterior)

9. **Postgres — "Garantir conversation_state"** (*Insert or Update* com
   `ON CONFLICT (conversation_id) DO NOTHING`, já que o default da coluna
   `status` é `AI_ACTIVE` — só precisamos garantir que a linha existe na
   primeira mensagem de uma conversa nova)

10. **Postgres — "Inserir mensagem"** (`operation: insert`, tabela
    `messages`). Usar `ON CONFLICT (tenant_id, conversation_id, external_id)
    DO NOTHING` — é a proteção contra webhook duplicado (Seção 19) via a
    constraint já criada em `0002_conversations.sql`. Se a linha já
    existia (`RETURNING` vazio), pular os próximos dois passos.

11. **Postgres — "Enfileirar no buffer"** (insert em `message_buffer` com
    `tenant_id`, `conversation_id`, `message_id`)

12. **Postgres — "Log evento: message_buffered"** (insert em
    `agent_events`)

13. **Execute Workflow — "CORE-02 Message Buffer"**
    - Chamar **sem esperar o resultado** ("Wait For Sub-Workflow Completion"
      = desligado, se a versão do n8n suportar; caso contrário, aceitar a
      latência e chamar de forma síncrona) — o objetivo é não segurar a
      resposta do webhook pela janela de debounce inteira.

14. **Respond to Webhook** — 200, `{"received": true}`.

## Pontos de atenção ao montar isso no n8n

- Credencial Postgres: uma única credencial de projeto, nunca IP/porta
  hardcoded no nó (usar a credencial gerenciada do n8n, apontando para
  `DATABASE_URL`).
- `trace_id`: gerar uma vez no topo do workflow (ex.: no nó "Extrair campos
  Chatwoot", `crypto.randomUUID()` dentro de uma expressão `{{ }}` não
  funciona diretamente — usar um Code node pequeno ou o node "Crypto" do
  n8n) e propagar em todos os inserts de `agent_events` deste fluxo.
- Este workflow **não** dispara nenhuma chamada de LLM — isso é
  responsabilidade do CORE-10 Agent Orchestrator (ainda não especificado).
