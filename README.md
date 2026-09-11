# Agente de Atendimento Geral — Plataforma Multi-Tenant

Plataforma reutilizável de Agentes de IA para atendimento comercial, suporte,
secretária/agendamento e assistentes internos, servindo **múltiplos clientes
(tenants)** a partir de um mesmo Core, sem lógica hardcoded de cliente.

Este é o projeto novo, construído a partir do zero. As referências
conceituais (uma Secretária IA e um Agente de Vendas anteriores) informaram
o desenho, mas não foram copiadas diretamente — ver `docs/ARCHITECTURE_PLAN.md`
e `docs/DECISIONS.md` para o raciocínio completo.

## Princípios

- Multi-tenant desde o schema de banco.
- Core independente de CRM, canal, provider de LLM e ferramenta de agenda.
- Configuração de tenant separada de conhecimento de negócio (RAG).
- Toda lógica sensível validada por contrato (schema), nunca só confiada ao
  prompt do LLM.
- Segregação total de dados por `tenant_id`.

## Decisão de implementação

O **Core roda em n8n puro** (sem serviço de código separado orquestrando os
workflows) — ver `docs/DECISIONS.md#d011`. Banco de dados é PostgreSQL.

## Estrutura

```
/docs                — plano de arquitetura, decisões (ADRs)
/database/migrations — schema Postgres versionado
/database/seeds       — dados de exemplo/seed (nunca dados reais de tenant)
/config               — JSON Schema + exemplo de Tenant Config
/schemas               — contratos (Universal Message, Tool Call, CRM Action)
/n8n
  /core                — CORE-00..90 (Inbound Gateway, Tenant Resolver, Buffer,
                          Context Builder, Agent Orchestrator, Output Gateway, Logging)
  /crm                  — CRM-00 Router + adapters (Kommo, Chatwoot, DataCry)
  /llm                  — LLM-00 Router + adapters (OpenAI, Anthropic, Google) + Fallback
  /tools                — Calendar, Knowledge, Files, Human Handoff, Tasks
  /agents               — definições de agente (prompt + tools habilitadas) por tipo
  /legacy               — referência histórica (workflows do projeto anterior),
                           preservados como estão, nunca importados diretamente
/scripts               — utilitários de operação/migração
```

## Status

Fase 1 (Fundação) em andamento: schema de banco, contratos e estrutura de
diretórios. Nenhum workflow n8n funcional foi implementado ainda — ver
`docs/ARCHITECTURE_PLAN.md` para as fases seguintes.
