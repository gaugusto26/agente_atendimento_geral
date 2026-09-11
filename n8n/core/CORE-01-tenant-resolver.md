# CORE-01 — Tenant Resolver

**Tipo de workflow**: sub-workflow (chamado por outros workflows via nó
"Execute Workflow"), nunca exposto por webhook público.

**Responsabilidade única**: dado de onde uma mensagem veio (provider +
identificadores de conta/inbox), devolver o `tenant_id` correspondente — ou
`resolved: false` se nenhum tenant estiver configurado para essa origem.
Nenhum outro workflow deve consultar `tenant_channels` diretamente; todos
passam por aqui.

## Input esperado

```json
{
  "provider": "chatwoot",
  "channel": "whatsapp",
  "account_id": "1",
  "inbox_id": "5"
}
```

## Nós

1. **Execute Workflow Trigger**
   - É o primeiro nó de todo sub-workflow chamável no n8n. Defina o "Input
     Source" como *"Using JSON Example"* e cole o JSON de input acima —
     isso documenta o contrato e habilita autocomplete de `$json.provider`
     etc. nos nós seguintes.

2. **Postgres — "Buscar canal do tenant"** (`n8n-nodes-base.postgres`,
   operação *Execute Query*)
   - Credencial: a credencial Postgres do projeto (`DATABASE_URL`).
   - Query (usar Query Parameters, nunca concatenar string):
     ```sql
     SELECT tc.tenant_id, t.enabled AS tenant_enabled
     FROM tenant_channels tc
     JOIN tenants t ON t.id = tc.tenant_id
     WHERE tc.provider = $1
       AND tc.enabled = true
       AND tc.external_account_id = $2
       AND (tc.external_inbox_id = $3 OR tc.external_inbox_id IS NULL)
     ORDER BY tc.external_inbox_id NULLS LAST
     LIMIT 1;
     ```
   - Query Parameters: `={{ $json.provider }}`, `={{ $json.account_id }}`,
     `={{ $json.inbox_id }}`.
   - Motivo do `ORDER BY ... NULLS LAST`: permite cadastrar um canal
     "catch-all" por conta (sem inbox específico) e um mais específico por
     inbox, preferindo sempre o mais específico.

3. **IF — "Tenant encontrado?"** (`n8n-nodes-base.if`)
   - Condição: `{{ $json.tenant_id }}` *is not empty* **AND**
     `{{ $json.tenant_enabled }}` *is true*.

4. **Branch verdadeiro → Set — "Resolvido"**
   - `tenant_id` = `={{ $json.tenant_id }}`
   - `resolved` = `true` (boolean)

5. **Branch falso → Set — "Não resolvido"**
   - `tenant_id` = `null`
   - `resolved` = `false` (boolean)
   - `reason` = `"no_tenant_channel_match"`

Ambos os ramos do `IF` convergem implicitamente no output do workflow (n8n
retorna o item que efetivamente rodou por último quando chamado via
"Execute Workflow"). Não é necessário nó de merge.

## Quem chama este workflow

- CORE-00 Inbound Gateway, logo após normalizar os campos brutos do
  provider e antes de montar o Universal Message completo.

## Não faz parte deste workflow

- Não decide estado IA×Humano (isso é `conversation_state`, tratado no
  Agent Orchestrator / CORE-10).
- Não persiste nada — é uma consulta pura.
