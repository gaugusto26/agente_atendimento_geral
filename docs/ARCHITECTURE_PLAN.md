# Architecture Plan — Agent Platform

> Projeto novo. A análise completa do repositório de referência ("Secretária
> IA") está em `docs/ARCHITECTURE_PLAN.md` do repositório
> `gaugusto26/Secretaria-IA-Automacao-Atendimento-WhatsApp-n8n-OpenAI`
> (branch `claude/nifty-einstein-w85tr6`). Este documento assume aquela
> análise como contexto e foca no que é construído aqui.

## 1. Decisões que definem esta Fase 1

- **Core em n8n puro** — sem serviço de código separado orquestrando os
  workflows (`docs/DECISIONS.md#d011`). Lógica de validação de contrato,
  buffer, roteamento etc. é implementada com nós nativos do n8n (Code, HTTP
  Request, Postgres, Switch) operando sobre os contratos definidos em
  `/schemas` e `/config`.
- **Repositório**: `gaugusto26/agente_atendimento_geral`, projeto novo,
  vazio — nada foi migrado/reestruturado de outro repositório; os workflows
  legados permanecem apenas como referência externa (ver
  `n8n/legacy/README.md`).
- **Banco**: PostgreSQL, multi-tenant desde a primeira migration.
- **Knowledge/RAG**: PostgreSQL + pgvector como padrão (Supabase não
  obrigatório).

## 2. O que já existe neste repositório (Fase 1 — Fundação)

```
/README.md                          — visão geral do projeto
/.env.example                       — variáveis de ambiente, sem valores reais
/docs
  ARCHITECTURE_PLAN.md              — este arquivo
  DECISIONS.md                      — ADRs
/database
  /migrations
    0001_tenants.sql                — tenants, tenant_features, tenant_channels,
                                       tenant_crm_config, tenant_llm_config
    0002_conversations.sql          — contacts, conversations, conversation_state,
                                       messages, message_buffer
    0003_agents_llm.sql             — agent_sessions, agent_events, llm_models,
                                       llm_calls, tool_calls
    0004_knowledge.sql              — knowledge_documents, knowledge_chunks (pgvector)
  /seeds
    0001_llm_models.sql             — seed inicial do Model Registry
/config
  tenant.schema.json                — JSON Schema do Tenant Config (Seção 6)
  tenant.example.json               — exemplo sem dados reais
/schemas
  universal-message.schema.json     — contrato do Inbound Gateway (Seção 5)
  tool-call.schema.json             — contrato de tool calling (Seção 13)
  crm-action.schema.json            — contrato do CRM Router (Seção 9)
/n8n
  core/ crm/ llm/ tools/ agents/    — READMEs com convenção de nomes e
                                       responsabilidades; nenhum workflow
                                       implementado ainda
  legacy/                           — README explicando por que os workflows
                                       antigos NÃO foram copiados para cá
/scripts                            — placeholder para utilitários de migração/seed
```

Todas as tabelas (exceto `tenants`) carregam `tenant_id` com índice. Chaves
de agregação (buffer, conversa, sessão de agente) usam
`tenant_id + conversation_id`, nunca só telefone — correção direta do
problema identificado no projeto de referência.

## 3. O que falta para a Fase 1 estar completa

- **Interfaces base como workflows n8n reais** (item 9 da Fase 1 do
  briefing): CRM Adapter, LLM Adapter, Channel Adapter, Calendar Adapter,
  Storage Adapter. Ainda não foram criados workflows `.json` reais — apenas
  a estrutura de pastas e os contratos que eles vão implementar.
  - Motivo de não ter avançado direto para isso: hand-crafting de JSON de
    workflow n8n é propenso a erro (foi exatamente a causa dos 5 arquivos
    quebrados no projeto de referência). O caminho mais seguro é criar esses
    workflows **dentro do próprio n8n** (import/export validado pela própria
    ferramenta) ou, se disponível, via a integração MCP do n8n para
    criar/validar workflows programaticamente. Ver Seção 6 (Riscos/decisões
    pendentes).
- Rodar as migrations contra um Postgres real e validar (nenhum ambiente de
  banco foi provisionado nesta sessão).

## 4. Próxima fase (Fase 2 — primeiro fluxo funcional)

Sem Calendar e sem RAG, conforme o plano original:

```
Chatwoot → CORE-00 Inbound Gateway → CORE-01 Tenant Resolver
         → CORE-02 Message Buffer → CORE-03 Context Builder
         → LLM-00 Router → CORE-10 Agent Orchestrator
         → CORE-30 Output Gateway → Chatwoot
```

Objetivo: usuário manda mensagem → sistema recebe → resolve tenant → agrupa
mensagens → verifica estado IA/Humano (`conversation_state`) → consulta LLM
→ responde. Cada etapa grava eventos em `agent_events` (CORE-90 Logging).

## 5. Módulos e ordem de dependência (igual ao repositório de referência)

1. Contratos (`/schemas`, `/config`) — já criados nesta Fase 1.
2. `/database/migrations` — já criadas; faltam rodar contra um banco real.
3. CORE-00 Inbound Gateway + CORE-01 Tenant Resolver (primeiro workflow
   real a construir — sem ele nada mais tem tenant_id para operar).
4. CORE-02 Message Buffer (usa `message_buffer`, chave `tenant_id +
   conversation_id`).
5. CRM-11 Chatwoot (primeiro adapter concreto, alinhado à Fase 2).
6. LLM-10 OpenAI + LLM-00 Router (mínimo para o Agent Orchestrator
   responder).
7. CORE-10 Agent Orchestrator + CORE-30 Output Gateway.

## 6. Riscos e decisões pendentes

- **Como construir os workflows n8n com segurança** (ver Seção 3 acima): a
  melhor opção é usar o MCP do n8n (aparece na lista de servidores desta
  sessão, mas está **sem autenticação configurada**) para criar/editar
  workflows diretamente na instância real, com validação da própria
  ferramenta — em vez de eu escrever `.json` de workflow à mão, que é onde
  o projeto de referência quebrou. Alternativa: eu preparo uma especificação
  nó-a-nó (inputs/outputs, expressões) para cada workflow, e você monta no
  editor do n8n a partir dela.
- **Credenciais reais do CRM/LLM/Calendar**: nenhuma foi solicitada nem
  usada. Precisam ser cadastradas como credenciais do próprio n8n (nunca em
  arquivo de workflow) quando os workflows reais forem construídos.
- **Ambiente Postgres de destino**: onde as migrations vão rodar (Supabase,
  RDS, instância própria) ainda não foi definido — impacta se `pgvector`
  está disponível por padrão.
- Demais riscos e decisões herdados do repositório de referência (arquivos
  legados quebrados, DataCry sem documentação de API) continuam válidos —
  ver o `ARCHITECTURE_PLAN.md` original para o detalhamento completo.
