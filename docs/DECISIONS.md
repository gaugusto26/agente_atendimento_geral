# Architecture Decisions

ADRs deste projeto. As decisões D001–D010 (multi-tenant desde o schema,
normalização de payload, estado IA×Humano no Core, conhecimento fora do
prompt, nenhum valor legado reaproveitado, arquivos com conflito
preservados como estão, Postgres+pgvector sem Supabase obrigatório, Model
Registry separando LLM de Embeddings, fases em ordem, nenhuma implementação
grande antes de aprovação) foram tomadas durante a análise do repositório de
referência e continuam valendo aqui — ver
`docs/DECISIONS.md` em `gaugusto26/Secretaria-IA-Automacao-Atendimento-WhatsApp-n8n-OpenAI`
(branch `claude/nifty-einstein-w85tr6`) para o texto completo de cada uma.

Esta lista continua a numeração com as decisões específicas deste repositório.

---

## D011 — Core roda em n8n puro, sem serviço de código separado

**Contexto**: `docs/ARCHITECTURE_PLAN.md` (versão anterior) listou como
decisão em aberto se o Core deveria ser um serviço HTTP em código
(TypeScript/Python) orquestrado pelo n8n, ou n8n puro. Trade-off: um serviço
em código facilita testes automatizados e reuso, mas introduz um novo
componente de infraestrutura para operar; n8n puro é mais aderente ao que o
usuário já opera e conhece.

**Decisão**: Core em **n8n puro**. Nenhum serviço externo de código
orquestra os workflows. Toda lógica de negócio (buffer, roteamento,
validação de contrato) é implementada com nós nativos do n8n, usando os
contratos versionados em `/schemas` e `/config` como especificação.

**Consequência**: sem novo componente de infra para hospedar; em
contrapartida, lógica mais complexa (ex.: concorrência no Message Buffer,
fallback do LLM Router) precisa ser cuidadosamente implementada com Code
nodes + Postgres, com testes feitos através de execuções reais no n8n (não
há suíte de testes automatizados de código fora do n8n). Workflows
continuam pequenos e de responsabilidade única (Seção 22 do briefing) para
compensar a ausência de testes unitários tradicionais.

---

## D012 — Este repositório (`agente_atendimento_geral`) é o projeto novo; nada foi migrado do repositório de referência

**Contexto**: o usuário confirmou que o projeto deve viver em
`gaugusto26/agente_atendimento_geral`, um repositório GitHub vazio, em vez
de continuar dentro do repositório da "Secretária IA".

**Decisão**: este repositório começa vazio e recebe apenas artefatos novos
(schema, contratos, docs). Os workflows do projeto de referência **não são
copiados** para cá — continuam no repositório original, citados apenas como
referência de leitura (ver `n8n/legacy/README.md`). Isso preserva a decisão
D005/D006 (nenhum valor/infra do ambiente de referência entra no novo
projeto, e os arquivos com conflito de merge não resolvido não são tratados
como fonte de verdade).

**Consequência**: quem quiser consultar o comportamento original completo
precisa abrir o repositório de referência; este repositório fica limpo desde
o primeiro commit.

---

## D013 — Construção de workflows n8n reais aguarda um caminho validado (MCP do n8n, ou especificação manual)

**Contexto**: escrever `.json` de workflow n8n à mão é frágil — foi
exatamente assim que 5 dos 6 workflows do projeto de referência acabaram
com conflitos de merge não resolvidos e viraram JSON inválido. Esta sessão
tem um servidor MCP `n8n` listado, mas ele **requer autenticação que ainda
não foi concedida**.

**Decisão**: a Fase 1 desta sessão entrega contratos, schema de banco e
estrutura de diretórios (tudo texto/SQL/JSON de configuração, que pode ser
revisado e versionado com segurança), mas **não** tenta gerar os arquivos
`.json` de workflow n8n à mão. A criação dos workflows reais (CORE-00 em
diante, Fase 2) fica para quando: (a) o MCP do n8n for autenticado e puder
criar/validar workflows diretamente na instância real, ou (b) o usuário
preferir montá-los no editor do n8n a partir de uma especificação nó-a-nó
que eu preparo.

**Consequência**: nenhum workflow `.json` existe ainda neste repositório —
apenas READMEs de convenção em `/n8n/*`. Isso é intencional, não um item
esquecido.

---

## D014 — Modelo de custo de IA: BYOK (cada tenant usa sua própria chave)

**Contexto**: a plataforma precisa decidir quem paga pelo uso de LLM de
cada tenant. Três modelos foram considerados: (1) BYOK — tenant cadastra
sua própria chave de API e paga o provider diretamente; (2) a plataforma é
dona das chaves e repassa o custo com markup, exigindo cobrança recorrente,
gestão de inadimplência e quotas de gasto por tenant; (3) créditos
pré-pagos, um meio-termo que ainda exige checkout mas evita inadimplência.

**Decisão**: adotar **BYOK** por enquanto. Cada tenant fornece sua própria
chave de API (`tenant_llm_config`/credencial no n8n), e a plataforma nunca
paga por uso de LLM de terceiro. `llm_calls.cost_estimated` continua sendo
gravado normalmente — serve para **visibilidade** de custo por tenant, não
para cobrança.

**Consequência**: nenhuma tabela de `usage`/`billing` nem integração de
pagamento (Stripe/Mercado Pago/etc.) é necessária nesta fase — o schema
atual (`llm_calls`) já é suficiente. Se o modelo mudar no futuro para (2)
ou (3), a mudança é aditiva (novas tabelas + um job de agregação de uso por
período), sem alterar o que já existe.

---

## D015 — Workflows n8n construídos direto na instância real via MCP (supera D013)

**Contexto**: D013 registrou que o MCP do `n8n` desta sessão estava sem
autenticação, e por isso a Fase 2 seguiria por especificação nó-a-nó em
Markdown para o usuário montar manualmente. Durante a sessão o MCP do `n8n`
passou a conectar de verdade (o problema anterior era falha de conexão do
lado da infraestrutura, não falta de autorização).

**Decisão**: a partir daí, todos os workflows (`CORE-01`, `CORE-00`,
`CORE-30`, `CORE-10`, `CORE-02`) foram construídos **diretamente na
instância n8n real do usuário**, via `n8n Workflow SDK` (TypeScript
restrito) + as ferramentas do MCP (`get_workflow_sdk_reference`,
`get_workflow_best_practices`, `search_nodes`, `get_node_types`,
`validate_workflow`, `create_workflow_from_code`, `update_workflow`,
`publish_workflow`, `execute_workflow`, `get_workflow_execution`). Cada
workflow foi validado antes de criar, e testado com uma execução real
(inclusive tráfego de webhook genuíno do Chatwoot) antes de ser considerado
pronto.

**Consequência**: os arquivos `.md` de especificação em `n8n/core/`
(`CORE-00-inbound-gateway-chatwoot.md`, `CORE-01-tenant-resolver.md`,
`CORE-00-CORE-01-validation.md`) continuam no repositório como *documentação
de referência* do desenho original, mas a fonte de verdade agora é o que
está publicado no n8n (ver tabela de IDs na Seção "Status — Fase 2" do
`ARCHITECTURE_PLAN.md`). Nenhum arquivo `.json` de workflow é versionado
neste repositório — os workflows vivem no n8n, não em Git, o que é uma
limitação conhecida (sem histórico de diff textual, sem review de PR sobre
mudanças de workflow) aceita conscientemente pela decisão D011 (n8n puro).

---

## D016 — Auto-atribuição de credencial do MCP não é confiável; sempre conferir e corrigir

**Contexto**: em repetidas ocasiões, `create_workflow_from_code` e
`update_workflow` (via `addNode`) auto-atribuíram a **credencial errada**
em nós Postgres e HTTP — pegaram uma credencial pré-existente qualquer do
mesmo tipo (`Postgres VPS`, usada por workflows antigos não relacionados a
este projeto) em vez da credencial `agent_platform_postgres` pedida
explicitamente por nome via `newCredential('agent_platform_postgres')`.

**Decisão**: depois de **todo** `create_workflow_from_code`/`addNode` que
envolva um nó com credencial, ler o campo `autoAssignedCredentials` da
resposta e, se a credencial atribuída não for exatamente a esperada,
corrigir imediatamente com `setNodeCredential` (por ID, nunca só por nome)
antes de publicar ou testar o workflow.

**Consequência**: mais uma chamada de correção por workflow criado, mas
elimina o risco real de um workflow novo silenciosamente ler/escrever no
Postgres errado (ou pior, no banco de outro projeto do usuário) — o exato
tipo de acoplamento indevido que o projeto inteiro existe para evitar.

---

## D017 — Provider de LLM da Fase 2: Google Gemini (não OpenAI), sem Router ainda

**Contexto**: a credencial `OpenAi account` do usuário estava sem créditos
(`no credits remaining`), e a `Google Gemini(PaLM) Api gui` inicialmente
também bateu num teto de gasto do projeto (`monthly spending cap`), até o
usuário aumentar esse teto no Google AI Studio.

**Decisão**: `CORE-10 Agent Orchestrator` usa o nó
`@n8n/n8n-nodes-langchain.lmChatGoogleGemini` (credencial `googlePalmApi`,
já existente) como model subnode do AI Agent, modelo
`models/gemini-3.1-flash-lite`. Não existe ainda um LLM Router (`LLM-00`)
nem fallback entre providers — é uma chamada direta a um único provider,
consistente com o escopo mínimo da Fase 2 do plano original.

**Consequência**: se essa chave também ficar indisponível (billing, rate
limit), o Agent Orchestrator falha sem fallback — aceitável para a Fase 2,
mas `LLM-00 Router` (Seção 11 do briefing original) continua como trabalho
pendente antes de qualquer uso além de teste/piloto.

---

## D018 — Memória do agente usa tabela própria do n8n, não a tabela `messages` do Core

**Contexto**: o desenho original (Seção 17 do briefing) previa um
`CORE-03 Context Builder` que montaria o contexto do agente a partir do
histórico normalizado em `messages` (últimas mensagens + resumo + dados
importantes), evitando mandar histórico bruto demais para o LLM. Para
ligar o agente rapidamente nesta sessão, usei o nó pronto
`@n8n/n8n-nodes-langchain.memoryPostgresChat` dentro do próprio
`CORE-10 Agent Orchestrator`, com `sessionKey = tenant_id:conversation_id`
e uma tabela própria (`agent_chat_memory`, formato langchain), **sem**
construir o `CORE-03 Context Builder` nem ler de `messages`.

**Decisão**: aceitar essa simplificação para a Fase 2 funcionar hoje.
`agent_chat_memory` e `messages` guardam o histórico de forma duplicada e
com formatos diferentes.

**Consequência (dívida registrada)**: falta construir `CORE-03 Context
Builder` de verdade (lendo de `messages`, aplicando janela/resumo) e decidir
se `memoryPostgresChat` continua como cache de curto prazo do LangChain por
cima disso, ou se é substituído completamente. Não tratar isso antes de
Fase 5 (Knowledge/RAG) provavelmente duplica ainda mais lógica de contexto.

---

## D019 — Verificação de assinatura HMAC do Chatwoot ainda não implementada

**Contexto**: o Chatwoot assina os webhooks que envia (headers
`X-Chatwoot-Signature` / `X-Chatwoot-Timestamp`, confirmados em execuções
reais). O usuário tem o secret de assinatura, mas ainda não foi decidido
nem implementado como o `CORE-00` deveria validar essa assinatura.

**Decisão**: por ora, `CORE-00 Inbound Gateway` continua com
`authentication: none` no nó Webhook — a única proteção é o path do
webhook ser um UUID não-adivinhável
(`a3f1e9c2-7b64-4d8a-9e21-5c6f0b2d1a4e`). Isso foi aceito conscientemente
para não atrasar o teste de ponta a ponta da Fase 2.

**Consequência (dívida registrada)**: antes de qualquer uso além de piloto
interno, adicionar um nó (Code, validando HMAC-SHA256 do corpo bruto contra
o header de assinatura, usando o secret como credencial nova no n8n — nunca
em texto no workflow) logo após o Webhook, respondendo 401 se a assinatura
não bater. Vale para qualquer futuro adapter de canal que suporte
assinatura de webhook (Kommo, WhatsApp Business direto, etc.), não só
Chatwoot.

---

## D020 — Conhecimento de tenant injetado direto no system prompt do agente (sem RAG/embeddings ainda)

**Contexto**: a migration `0004_knowledge.sql` (Fase 1) já criou
`knowledge_documents`/`knowledge_chunks` com `pgvector`, mas nenhuma
ingestão/busca vetorial foi construída (isso é a Fase 5 completa, ainda não
iniciada). Um novo tenant (Golden Ouro e Prata — comprador de metais
preciosos) precisava, ainda hoje, que o agente seguisse regras de negócio
específicas (triagem por urgência/região/item, sempre pedir foto, nunca
agendar visita, nunca passar valor) sem esperar pela Fase 5.

**Decisão**: `CORE-10 Agent Orchestrator` ganhou um nó Postgres novo
("Buscar conhecimento do tenant") logo após "Buscar nome da empresa":
`SELECT COALESCE(string_agg(content, E'\n\n' ORDER BY created_at), '') AS
knowledge_text FROM knowledge_documents WHERE tenant_id = $1;`. O resultado
é concatenado (sem chunking, sem embedding, sem busca por similaridade) e
injetado no `systemMessage` do nó Assistente, junto do nome da empresa.
Cada tenant guarda suas regras como uma ou mais linhas em
`knowledge_documents.content` (texto simples).

**Consequência**: funciona bem para tenants com pouco conteúdo (algumas
regras/parágrafos), que é o caso de todos os tenants ativos hoje. Não
escala para bases de conhecimento grandes (todo o conteúdo de todo
`knowledge_documents` do tenant entra no prompt, sem seleção por
relevância nem limite de tamanho) — quando isso passar a ser um problema,
a Fase 5 (ingestão + `retrieve-as-tool` do `vectorStorePGVector`)
substitui esta consulta por uma busca vetorial real, sem mudar o schema.
Publicado e validado em produção (`activeVersionId
df29bf8f-ee25-4f3f-b7c9-1209b2572650`).

---

## D021 — Pausa automática de 30 minutos quando um humano responde manualmente pelo Chatwoot

**Contexto**: o usuário precisa poder assumir uma conversa manualmente pelo
Chatwoot (ex.: caso sensível, negociação) sem que o agente responda por
cima logo em seguida. Não havia, até então, nenhuma distinção entre uma
mensagem de saída gerada pelo próprio agente (via CORE-30) e uma mensagem
de saída digitada por um humano no Chatwoot — ambas chegam ao webhook do
Chatwoot com `sender.type: "user"`, porque o CORE-30 usa um token de API
pessoal, não um Agent Bot dedicado.

**Decisão**: `CORE-00 Inbound Gateway` agora processa também eventos de
mensagem de **saída** (antes eram ignorados por completo). Para toda
mensagem outgoing: (1) verifica se o `external_id` (id da mensagem no
Chatwoot) já existe em `messages` — se existir, é eco do próprio agente,
ignorado; (2) se não existir, é uma resposta humana genuína — busca a
`conversation_id` correspondente e executa
`UPDATE conversation_state SET status = 'AI_PAUSED', updated_at = now()
WHERE conversation_id = $1`, registrando o evento `automation_paused` em
`agent_events`. Em `CORE-02 Message Buffer`, o nó "Buscar estado da
conversa" foi alterado para tratar `AI_PAUSED` como `AI_ACTIVE`
automaticamente quando `updated_at` tem mais de 30 minutos:
`SELECT CASE WHEN status = 'AI_PAUSED' AND updated_at < now() - interval
'30 minutes' THEN 'AI_ACTIVE' ELSE status END AS status FROM
conversation_state WHERE conversation_id = $1;` — sem job/cron separado,
o próprio buffer resolve o expirado na próxima mensagem do cliente.

**Consequência**: qualquer resposta manual do humano reinicia a janela de
pausa (cada nova resposta atualiza `updated_at`); o agente permanece calado
por 30 minutos após a última intervenção humana e retoma sozinho depois
disso, sem exigir ação explícita de "devolver para a IA". Ambos os
workflows publicados e ativos (`tl22TbmEhvxqjpE6` versão
`562b88f9-f543-4572-a75b-88bdfa9f89ed`; `uBQGxhCMBQEasbLa` versão
`26bfc9da-97de-4c48-a0c4-36b3b0a8fabf`). Ainda não testado com uma resposta
humana real — próximo passo de validação.

---

## D022 — Conversas de grupo excluídas do foco do agente

**Contexto**: incidente em produção no mesmo dia — o número de WhatsApp
usado como canal de um tenant também está adicionado a grupos pessoais do
usuário. Como o Chatwoot trata mensagens de grupo com o mesmo tipo de
evento de webhook (`message_created`/`message_updated`) que conversas
individuais, e o `CORE-00` processava qualquer mensagem do inbox
configurado, o agente respondeu automaticamente dentro de grupos reais
(ex.: "Canal O Tech Lead - Geral"), lendo e respondendo mensagens de
terceiros sem contexto — experiência ruim e potencial vazamento de
comportamento do agente fora do escopo 1:1 esperado.

**Decisão**: `CORE-00 Inbound Gateway` agora identifica conversa de grupo
logo após "Extrair campos Chatwoot" (antes de qualquer resolução de
tenant), usando a convenção de JID do WhatsApp: o campo
`conversation.meta.sender.identifier` do payload do Chatwoot termina em
`@g.us` para grupos e em `@s.whatsapp.net` para contatos individuais. Um
novo campo booleano `is_group` é extraído
(`({{ $json.body?.conversation?.meta?.sender?.identifier || "" }}).endsWith("@g.us")`)
e um nó IF ("É grupo?") logo em seguida decide: se for grupo, responde
`{ignored: true, reason: "group_conversation"}` imediatamente, sem
resolver tenant, sem persistir nada, sem acionar o buffer ou o agente. Se
não for grupo, o fluxo segue normalmente (incoming e outgoing).

**Consequência**: o agente nunca mais processa mensagens de grupo, em
nenhum tenant — a checagem é genérica (baseada no formato do JID do
WhatsApp via Chatwoot), não específica de um tenant, então protege todos
os tenants atuais e futuros automaticamente. Filtro aplicado antes de
qualquer chamada de banco ou sub-workflow, então também é a checagem mais
barata do pipeline. `tl22TbmEhvxqjpE6` publicado e ativo (versão
`e88e7d8b-0517-420d-8721-eda797903b25`).

**Nota operacional**: durante o incidente, o usuário desativou manualmente
todos os workflows do Core (`CORE-00`, `CORE-01`, `CORE-02`, `CORE-10`,
`CORE-30`) para estancar o problema. Todos foram republicados nesta
correção, na ordem de dependência (sub-workflows antes de quem os chama),
já que `publish_workflow` recusa publicar um workflow cujos
sub-workflows referenciados (via Execute Workflow) não estejam
publicados.
