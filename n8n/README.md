# Workflows n8n — convenção de nomes e responsabilidades

Core roda em **n8n puro** (D011 em `docs/DECISIONS.md`) — sem serviço de
código externo orquestrando os workflows. Cada workflow é pequeno, com
responsabilidade única, e troca dados com os demais apenas através dos
contratos em `/schemas` e `/config`.

## Convenção

`<GRUPO>-<NÚMERO> <Nome>`, agrupados em subpastas por área:

```
/n8n/core
  CORE-00 Inbound Gateway     — normaliza payload de canal/CRM em Universal Message
  CORE-01 Tenant Resolver     — resolve tenant_id a partir da origem do evento
  CORE-02 Message Buffer      — agrega mensagens, chave (tenant_id, conversation_id)
  CORE-03 Context Builder     — monta memória + tenant config + knowledge
  CORE-10 Agent Orchestrator  — invoca LLM Router e Tools, aplica AI×Humano
  CORE-30 Output Gateway      — envia resposta pelo canal de origem
  CORE-90 Logging             — grava agent_events / trace_id

/n8n/crm
  CRM-00 Router
  CRM-10 Kommo
  CRM-11 Chatwoot
  CRM-12 DataCry

/n8n/llm
  LLM-00 Router
  LLM-10 OpenAI
  LLM-11 Anthropic
  LLM-12 Google
  LLM-90 Fallback

/n8n/tools
  TOOL-10 Calendar
  TOOL-11 Knowledge
  TOOL-12 Files
  TOOL-13 Human Handoff
  TOOL-14 Tasks

/n8n/agents
  definições de agente (prompt + tools habilitadas) por tipo — general,
  sales, secretary, internal — nunca com dados de um tenant específico
  embutidos no texto do prompt.

/n8n/legacy
  referência histórica do projeto anterior. Preservado como está, nunca
  importado nem executado diretamente.
```

## Regras

- Nenhum workflow fora de `/n8n/crm/<provider>` ou `/n8n/legacy` deve
  referenciar um campo específico de payload de Chatwoot/Kommo/DataCry.
- Toda tool call que um Agent executa é validada contra
  `schemas/tool-call.schema.json` antes de rodar.
- Nenhum ID de agenda, endpoint ou credencial fica hardcoded em um nó — vem
  de `config/tenant.*.json` ou de credencial gerenciada pelo próprio n8n.
- Fase 2 do plano (`docs/ARCHITECTURE_PLAN.md`) é o primeiro fluxo real a
  implementar aqui: Chatwoot → CORE-00..30, sem Calendar e sem RAG.

Esta pasta ainda não tem workflows implementados — ver "Status" no
`README.md` da raiz do projeto.
