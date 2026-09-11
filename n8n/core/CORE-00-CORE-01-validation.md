# Como validar CORE-01 e CORE-00 (Chatwoot)

Roteiro prático para testar os dois workflows depois de montados no n8n,
contra um Postgres real com as migrations já aplicadas.

## 0. Pré-requisitos

1. Rodar as migrations no banco de destino:
   ```bash
   psql "$DATABASE_URL" -f database/migrations/0001_tenants.sql
   psql "$DATABASE_URL" -f database/migrations/0002_conversations.sql
   psql "$DATABASE_URL" -f database/migrations/0003_agents_llm.sql
   psql "$DATABASE_URL" -f database/migrations/0004_knowledge.sql
   ```
   (a 0004 exige a extensão `vector` disponível no Postgres — se falhar só
   nela, pode seguir com a validação do CORE-00/CORE-01, que não dependem
   de knowledge).
2. No n8n, criar/confirmar a credencial Postgres apontando para esse banco.
3. Criar um tenant de teste e um canal, para o CORE-01 ter o que resolver:
   ```sql
   INSERT INTO tenants (id, tenant_key, name)
   VALUES ('11111111-1111-1111-1111-111111111111', 'tenant_teste', 'Tenant de Teste');

   INSERT INTO tenant_features (tenant_id)
   VALUES ('11111111-1111-1111-1111-111111111111');

   INSERT INTO tenant_channels (tenant_id, provider, channel, external_account_id, external_inbox_id)
   VALUES ('11111111-1111-1111-1111-111111111111', 'chatwoot', 'whatsapp', '1', '5');
   ```
   (`external_account_id`/`external_inbox_id` = `'1'`/`'5'` são só exemplo —
   troque pelos IDs reais da conta/inbox do Chatwoot que você vai usar no
   teste, ou mantenha esses mesmos valores e use-os também no payload do
   passo 2 abaixo.)

## 1. Validar CORE-01 isoladamente

No editor do n8n, abra o workflow CORE-01 e use **"Test workflow"** com
dado de entrada manual (clique no nó "Execute Workflow Trigger" → "Pin Data"
ou "Test step"), simulando o JSON de input:

**Caso A — deve resolver:**
```json
{ "provider": "chatwoot", "channel": "whatsapp", "account_id": "1", "inbox_id": "5" }
```
Resultado esperado: `resolved: true` e `tenant_id` =
`11111111-1111-1111-1111-111111111111`.

**Caso B — não deve resolver (tenant inexistente):**
```json
{ "provider": "chatwoot", "channel": "whatsapp", "account_id": "999", "inbox_id": "999" }
```
Resultado esperado: `resolved: false`, sem erro de execução.

Se qualquer um dos dois não bater, o problema está na query SQL do passo 2
da spec (`CORE-01-tenant-resolver.md`) — me manda o erro/resultado que você
viu e eu ajusto.

## 2. Validar CORE-00 ponta a ponta

Ative o workflow CORE-00 (ou use a "Test URL" do nó Webhook, que fica ativa
só durante uma execução de teste) e dispare um POST simulando o payload do
Chatwoot:

```bash
curl -X POST "<URL_DO_WEBHOOK_CORE00>" \
  -H "Content-Type: application/json" \
  -d '{
    "message_type": "incoming",
    "id": 993828,
    "content": "Oi, quero marcar uma consulta",
    "created_at": "2026-09-11T12:00:00.000Z",
    "account": { "id": 1 },
    "inbox": { "id": 5, "channel_type": "Channel::Whatsapp" },
    "sender": { "id": 42, "name": "Maria", "phone_number": "5511999999999" },
    "conversation": { "id": 12891 }
  }'
```

Resultado esperado: `200 {"received": true}`.

Depois, confira no Postgres se tudo foi persistido:

```sql
SELECT id, external_id, name, phone FROM contacts
  WHERE tenant_id = '11111111-1111-1111-1111-111111111111';

SELECT id, external_id, provider, channel FROM conversations
  WHERE tenant_id = '11111111-1111-1111-1111-111111111111';

SELECT status FROM conversation_state cs
  JOIN conversations c ON c.id = cs.conversation_id
  WHERE c.tenant_id = '11111111-1111-1111-1111-111111111111';
-- esperado: 'AI_ACTIVE'

SELECT id, direction, type, text FROM messages
  WHERE tenant_id = '11111111-1111-1111-1111-111111111111';

SELECT id, consumed_at FROM message_buffer
  WHERE tenant_id = '11111111-1111-1111-1111-111111111111';
-- esperado: 1 linha, consumed_at IS NULL (ainda não foi consumida —
-- normal, CORE-02 ainda não existe)

SELECT event_type, trace_id FROM agent_events
  WHERE tenant_id = '11111111-1111-1111-1111-111111111111'
  ORDER BY created_at;
```

## 3. Testar idempotência (proteção contra webhook duplicado)

Rode o **mesmo** `curl` do passo 2 de novo, sem alterar nada (mesmo
`"id": 993828`).

Resultado esperado: ainda `200 {"received": true}`, mas
`SELECT count(*) FROM messages WHERE tenant_id = '...' AND external_id = '993828'`
continua retornando **1** (não 2). Se aparecer uma segunda linha, o `ON
CONFLICT` do nó "Inserir mensagem" não está configurado com as colunas
certas (`tenant_id, conversation_id, external_id`) — confira a
configuração de "Insert or Update" / a constraint `UNIQUE` da tabela
`messages`.

## 4. Testar o caso de tenant desconhecido

Repita o `curl` do passo 2 trocando `"account": { "id": 1 }` para
`"account": { "id": 999 }` (nenhum `tenant_channels` cadastrado para essa
conta).

Resultado esperado: ainda `200`, mas com corpo
`{"ignored": true, "reason": "unknown_tenant"}`, e uma linha nova em
`agent_events` com `event_type = 'tenant_resolution_failed'`. Nenhuma linha
deve aparecer em `contacts`/`conversations`/`messages` para essa conta.

## 5. Testar o filtro de mensagem de saída

Repita o `curl` trocando `"message_type": "incoming"` para
`"message_type": "outgoing"`.

Resultado esperado: `200 {"ignored": true}`, nada é persistido.

---

Qualquer divergência entre o que você observar no n8n e o que está descrito
aqui (nome de campo do Chatwoot diferente, comportamento de nó diferente),
me manda o print/erro — ajusto a spec antes de seguirmos para o CORE-02.
