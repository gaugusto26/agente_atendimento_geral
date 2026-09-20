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
  core/                              — specs + roteiro de validação (referência);
                                       os workflows reais (Fase 2, concluída)
                                       estão publicados no n8n, não neste repo
  crm/ llm/ tools/ agents/           — READMEs com convenção de nomes e
                                       responsabilidades; ainda sem workflow
  legacy/                           — README explicando por que os workflows
                                       antigos NÃO foram copiados para cá
/scripts                            — placeholder para utilitários de migração/seed
```

Todas as tabelas (exceto `tenants`) carregam `tenant_id` com índice. Chaves
de agregação (buffer, conversa, sessão de agente) usam
`tenant_id + conversation_id`, nunca só telefone — correção direta do
problema identificado no projeto de referência.

## 3. Fase 1 — concluída

Migrations rodadas e validadas contra um Postgres real (`agent_platform_postgres`,
container dedicado na stack self-hosted do usuário, separado do Postgres
interno do n8n — ver `database/README.md`). As 17 tabelas existem e foram
exercitadas com dados reais.

## 4. Fase 2 — primeiro fluxo funcional: **concluída e validada com tráfego real**

```
Chatwoot → CORE-00 Inbound Gateway → CORE-01 Tenant Resolver
         → CORE-02 Message Buffer → CORE-10 Agent Orchestrator (Gemini + memória)
         → CORE-30 Output Gateway → Chatwoot
```

Sem Calendar e sem RAG, como previsto. **Sem CORE-03 Context Builder** e
**sem LLM-00 Router** — ver D018/D017 em `DECISIONS.md` (simplificações
aceitas para validar o fluxo rapidamente; dívida registrada, não esquecida).

### Workflows publicados no n8n (`https://n8n.digitalfive.com.br`)

| Workflow | ID | Responsabilidade |
|---|---|---|
| CORE-00 Inbound Gateway (Chatwoot) | `tl22TbmEhvxqjpE6` | Webhook → Universal Message → persistência idempotente → enfileira buffer |
| CORE-01 Tenant Resolver | `SORheYP8kFYlvQh1` | Resolve `tenant_id` a partir de provider/account/inbox |
| CORE-02 Message Buffer | `uBQGxhCMBQEasbLa` | Debounce 4s, confirma mensagem mais recente, checa `AI_ACTIVE`, agrega |
| CORE-10 Agent Orchestrator | `pnKnvq3lf1KvjSRz` | AI Agent (Gemini) + memória Postgres por sessão `tenant_id:conversation_id` |
| CORE-30 Output Gateway | `04QWtEuiCRQt0vov` | Resolve base_url/account/conversation no Postgres, envia resposta ao Chatwoot |

Construídos diretamente na instância n8n do usuário via MCP (`n8n Workflow
SDK` + ferramentas de create/update/validate/execute) — ver D015 em
`DECISIONS.md`. Não existe `.json` de workflow versionado neste repositório;
os `.md` em `n8n/core/` (specs + roteiro de validação) continuam como
documentação de referência do desenho, mas o que roda de verdade é o que
está publicado no n8n.

**Validado com execução real**: mensagem enviada por WhatsApp → Chatwoot →
webhook (assinatura HMAC do Chatwoot presente no header, mas ainda não
verificada pelo CORE-00 — D019) → tenant resolvido → buffer → Gemini gerou
resposta contextualizada em PT-BR → resposta persistida em `messages` →
enviada de volta ao Chatwoot com sucesso → confirmada visualmente pelo
usuário na conversa real.

Também testados e corretos: idempotência (mensagem duplicada não duplica
`messages`/`message_buffer`), tenant desconhecido (ignorado sem erro),
buffer agregando múltiplas mensagens pendentes em uma única chamada ao
agente.

### 4.1 Extensões pós-Fase 2 (mesmo dia, tráfego real de cliente)

Duas capacidades adicionadas depois da validação inicial, para sustentar
uso real no mesmo dia (ver D020/D021 em `DECISIONS.md`):

- **Conhecimento de tenant no prompt** — `CORE-10` concatena
  `knowledge_documents.content` do tenant e injeta no `systemMessage` do
  Assistente (sem RAG/embeddings ainda — interino até a Fase 5). Permite
  onboarding de um novo tenant (ex.: Golden Ouro e Prata) só com linhas
  em `knowledge_documents`, zero mudança de workflow.
- **Pausa automática de 30 min em resposta humana manual** — `CORE-00`
  agora também processa mensagens de **saída** do Chatwoot: distingue eco
  do próprio agente (via `messages.external_id`) de resposta humana
  genuína, e para esta última marca `conversation_state.status =
  'AI_PAUSED'`. `CORE-02` trata `AI_PAUSED` como `AI_ACTIVE` de novo
  automaticamente após 30 minutos sem atualização (sem job separado).
  Mensagem de saída deixou de ser simplesmente "ignorada" — agora tem
  rota própria.

Ambas publicadas e ativas; pausa automática ainda sem teste com resposta
humana real de ponta a ponta (próximo passo).

- **Exclusão de grupos do foco do agente (D022)** — incidente real:
  o WhatsApp de um tenant também está em grupos pessoais do usuário, e o
  agente respondeu automaticamente dentro de um grupo. `CORE-00` agora
  detecta conversa de grupo (`identifier` do Chatwoot terminando em
  `@g.us`, convenção de JID do WhatsApp) logo após extrair os campos do
  webhook, antes de resolver tenant, e ignora a mensagem por completo
  (`{ignored:true, reason:"group_conversation"}"`) sem persistir nada nem
  acionar o agente. Vale para todos os tenants automaticamente.
- **Lista de contatos excluídos (D023)** — nova tabela `excluded_contacts`
  (migration `0005`), consultada logo após o filtro de grupo. Um número
  de telefone lá dentro faz o `CORE-00` ignorar a mensagem por completo,
  sem tocar em tenant/banco/agente. Gerenciável só com SQL (base pro
  futuro painel), sem mudança de workflow.

## 4.2 Painel operacional (D024)

3 formulários n8n (`n8n Form Trigger`), sem app/serviço novo (mantém D011):

| Workflow | Função |
|---|---|
| PAINEL-01 Onboarding de Tenant | Cria tenant + features + CRM config numa submissão |
| PAINEL-02 Adicionar Conhecimento | Insere regra/FAQ em `knowledge_documents` de um tenant |
| PAINEL-03 Excluir Contato | Insere número em `excluded_contacts` (D023) |

Substitui o fluxo manual "eu escrevo SQL, Hermes roda" para essas 3
operações recorrentes. `tenant_channels` (canal/inbox) continua fora do
formulário — só dá pra descobrir depois de uma mensagem real do número.

## 5. Próximas fases (não iniciadas)

- **Fase 3 — Human Handoff**: `handoff.request`, tradução por CRM Adapter
  (Chatwoot → label/estado), Agent Orchestrator checando
  `conversation_state.status` antes de responder (hoje o CORE-02 já checa
  `AI_ACTIVE`, mas não há ferramenta para a IA *pedir* handoff).
- **Fase 4 — Calendar**: TOOL-10, Google Calendar, `config.calendars[]` já
  desenhado no schema do Tenant Config.
- **Fase 5 — Knowledge/RAG**: `knowledge_documents`/`knowledge_chunks` já
  existem (migration `0004`); falta ingestão e o `retrieve-as-tool` do
  `vectorStorePGVector` no Agent.
- **Fase 6 — Kommo** / **Fase 7 — DataCry**: novos `CORE-00` (um por
  provider, mesma técnica do Chatwoot) + adapters de CRM Router.

Antes dessas fases, vale fechar as dívidas da Fase 2 (D017–D019):
LLM Router com fallback, CORE-03 Context Builder de verdade, e verificação
HMAC do webhook do Chatwoot.

## 6. Riscos atualizados

- **Auto-atribuição de credencial do MCP do n8n não é confiável** — sempre
  conferir `autoAssignedCredentials` e corrigir por ID (ver D016). Um
  esquecimento aqui faz um workflow novo ler/escrever no banco errado
  silenciosamente.
- **Workflows vivem só no n8n, não em Git** — sem diff textual, sem review
  de PR sobre mudança de workflow, sem rollback via `git revert` (só via
  histórico de versão do próprio n8n, `get_workflow_history`/
  `restore_workflow_version`). Aceito conscientemente por D011, mas exige
  disciplina operacional (nomear bem cada `versionName`/`versionDescription`
  ao publicar).
- **Sem LLM Router/fallback** (D017): uma indisponibilidade do único
  provider configurado (billing, rate limit) derruba o agente inteiro sem
  degradação graciosa.
- **HMAC do Chatwoot não verificado** (D019): qualquer requisição POST no
  path do webhook é aceita como se fosse do Chatwoot.
- **Conhecimento injetado sem limite de tamanho** (D020): todo o conteúdo
  de `knowledge_documents` do tenant entra no prompt sem seleção por
  relevância — aceitável hoje (tenants com pouco conteúdo), não escala.
- **Pausa automática (D021) testada e corrigida** (2026-09-20): validação
  revelou e corrigiu um bug real (consulta sem `alwaysOutputData` travava
  a cadeia silenciosamente quando não achava eco/conversa — mesma classe
  de bug do filtro de contato excluído, já resolvido com `COALESCE`).
  Pausa e expiração de 30 minutos confirmadas funcionando.
- **Credencial de LLM isolada por tenant só existe para a Golden** (D025)
  — implementado como ramificação manual no CORE-10, não como sistema
  genérico. Se mais tenants precisarem, vale generalizar via
  `tenant_llm_config` em vez de crescer uma cadeia de IFs.
- **Incidente de grupo (D022) exigiu desativar manualmente todos os
  workflows do Core** — todos foram republicados após a correção; serve
  de lembrete que não existe hoje um "kill switch" granular (ex.: pausar
  só um tenant, ou só respostas em grupo) sem desligar tudo.
- Demais riscos herdados do repositório de referência (arquivos legados
  quebrados, DataCry sem documentação de API) continuam válidos.
