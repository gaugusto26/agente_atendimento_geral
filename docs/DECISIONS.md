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

**Atualização (2026-09-24) — mitigação parcial, `LLM-00 Router` continua pendente**:
análise de execuções com erro (22 a 24/09) achou 3 casos reais de cliente da
Golden sem nenhuma resposta por `[503] This model is currently experiencing
high demand` do Gemini — sobrecarga momentânea do provider, não billing/rate
limit, mas o efeito é o mesmo previsto acima: sem retry, a cadeia falha e o
cliente não recebe nada. Usuário ativou `Retry On Fail` diretamente no n8n
nos nós "Assistente" e "Assistente (Golden)" do `CORE-10` (mitiga a maioria
dos 503 transitórios, sem precisar de um segundo provider). **Não substitui**
o `LLM-00 Router`: uma indisponibilidade prolongada do Gemini (billing,
rate limit, outage real) continua derrubando o agente inteiro sem
degradação — retry só ajuda em falhas curtas que se resolvem sozinhas em
segundos. `pnKnvq3lf1KvjSRz` publicado (`activeVersionId:
69afb3fa-b27c-4895-b41e-1c267cd4f6e9`).

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

## D025 — Credencial de Gemini dedicada para a Golden (isolamento de custo/quota)

**Contexto**: durante a validação de fluxo, uma chamada de teste esgotou o
crédito pré-pago compartilhado do Google AI Studio (`Google Gemini(PaLM)
Api gui`, credencial usada por todos os tenants), derrubando a resposta
da IA para todo mundo — inclusive a Golden, que tem tráfego real hoje.
Isso é exatamente o cenário que D014 (BYOK) previu, mas ainda não
implementado: sem isolamento de credencial por tenant, um único tenant
(ou um teste) pode esgotar a cota de todos.

**Decisão**: `CORE-10 Agent Orchestrator` ganhou uma ramificação logo após
buscar o conhecimento do tenant: um nó IF ("Tenant Golden?") compara
`tenant_id` contra o UUID da Golden
(`7f3a1c20-19e2-4b8b-9d5a-2b6e4a10f001`). Se for a Golden, usa um par
dedicado de nós — "Assistente (Golden)" + "Google Gemini Chat Model
(Golden)" — com a credencial `GOLDEN OURO GEMINI API KEY` (chave própria,
criada pelo usuário em conta separada do Google AI Studio). Qualquer
outro tenant continua no par original ("Assistente" + "Google Gemini Chat
Model"), com a credencial compartilhada. As duas rotas convergem de volta
no mesmo nó "Salvar resposta como mensagem". `CORE-30 Output Gateway`
teve que ser corrigido: antes lia `$("Assistente").item.json.output` por
nome fixo, o que quebraria na rota da Golden (só "Assistente (Golden)"
roda nesse caso); agora lê `$("Salvar resposta como mensagem").item.json.text`,
que funciona nas duas rotas.

**Consequência (dívida registrada)**: essa é uma ramificação manual
específica para um tenant, não um sistema genérico. Se mais tenants
precisarem de credencial própria, o padrão certo é uma tabela
`tenant_llm_config` (já existe no schema desde a migration `0001`, ainda
sem uso real) guardando qual credencial usar por tenant, com o workflow
lendo essa configuração em vez de checar `tenant_id` explicitamente node
a node — evita crescer uma cadeia de IFs. Não fazer essa generalização
agora (YAGNI) até um segundo tenant precisar do mesmo isolamento.
Testado e confirmado funcionando: a Golden respondeu corretamente (inclusive
recusando um relógio, conforme a regra do script) usando a credencial
nova; o tenant_teste continuou funcionando na credencial compartilhada.
`pnKnvq3lf1KvjSRz` publicado (versão `1dacd16b-a9e5-4fc7-8b15-eee2b9ea41ba`).

---

**Atualização (2026-09-20)**: o tenant `golden_ouro_prata` passou de duas
linhas resumidas (COMPANY + POLICY, escritas por mim durante o
onboarding) para um único documento completo de ~460 linhas — um roteiro
de SDR fornecido pelo usuário (`n8n/agents/golden-ouro-prata-sdr.md`),
com identidade, tom de voz, qualificação comercial, tratamento de
objeções, regras de preço/avaliação e exemplo de conversa. Isso confirma
que o design de D020 suporta bem conteúdo extenso e estruturado, não só
regras curtas — o limite prático é o tamanho do prompt do LLM, não o
schema. Inserção feita via workflow utilitário temporário (Code node
decodificando Base64, para evitar problemas de escaping de aspas do
texto original em JSON) — workflow arquivado depois de usado.

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
`26bfc9da-97de-4c48-a0c4-36b3b0a8fabf`).

**Atualização (2026-09-20) — bug crítico em produção, corrigido**: horas
depois de "testado e corrigido" abaixo, o próprio usuário relatou em
tráfego real: *"o agente parou logo após responder a primeira
mensagem"*. Causa raiz: `CORE-10` salva a resposta do agente em
`messages` **sem preencher `external_id`** (a coluna fica `NULL` —
o id do Chatwoot só é conhecido depois que `CORE-30` envia a mensagem e
recebe a resposta da API). Quando o eco dessa resposta volta pelo webhook
do Chatwoot, "Checar se é eco do agente" procura por
`external_id = <id real do Chatwoot>` em `messages` — não encontra
(porque salvamos `NULL`, nunca o id real) — e trata a própria resposta do
agente como se fosse um humano respondendo manualmente, pausando a
conversa. Resultado: o agente ficava mudo logo após a primeira resposta,
em **toda** conversa, de **todo** tenant, desde que D021 foi publicado.

**Correção**: `CORE-30 Output Gateway` ganhou um nó novo
("Atualizar external_id da mensagem") logo após enviar a mensagem ao
Chatwoot: `UPDATE messages SET external_id = $1 WHERE id = (SELECT id
FROM messages WHERE tenant_id = $2 AND conversation_id = $3 AND
direction = 'outgoing' AND external_id IS NULL ORDER BY created_at DESC
LIMIT 1)`, usando o id retornado pela API do Chatwoot. "Log evento
response_sent" também foi ajustado pra referenciar
`$("Enviar mensagem no Chatwoot").item.json.id` explicitamente em vez de
`$json.id` (que passou a apontar pro nó novo). Publicado
(`04QWtEuiCRQt0vov`, versão `c7b5b0d5-3a26-4e59-a50d-841617a33c36`). As 3
conversas que tinham sido pausadas incorretamente (2 da Golden, 1 de
teste) foram reativadas manualmente.

**Anterior (mesmo dia) — testado e corrigido**: a validação de ponta a
ponta (via execução simulada de webhook no CORE-00) revelou um bug real:
os nós "Checar se é eco do agente" e "Buscar conversa para pausa" usavam
`SELECT ... LIMIT 1` sem `alwaysOutputData` — quando a consulta não
encontrava nenhuma linha (o caso comum: mensagem nova, ainda não é eco),
o nó não emitia nenhum item, e a cadeia inteira parava silenciosamente
sem erro, sem pausar e sem responder o webhook. Corrigido com o mesmo
padrão já usado em "Buscar contato excluído" (D023): `SELECT
COALESCE((SELECT id::text FROM ... LIMIT 1), '') AS id`, que sempre
retorna uma linha (id vazio quando não encontrado). Testado novamente
após a correção: pausa dispara corretamente, `conversation_state.status`
vira `AI_PAUSED`, e a expiração de 30 minutos também foi validada
artificialmente (backdatando `updated_at` e confirmando que a query do
CORE-02 volta a tratar como `AI_ACTIVE`). `tl22TbmEhvxqjpE6` publicado
com a correção (versão `ff906b22-8246-41af-85a0-c4a6b4cc5ed1`).

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

---

## D023 — Lista de contatos excluídos (`excluded_contacts`), independente de grupo

**Contexto**: além do incidente de grupo (D022), identificou-se um número
de telefone específico (`+5515981772842`, contato "Alertas e Mensagens" no
Chatwoot) gerando tráfego indevido para o agente — não é um grupo, é um
contato 1:1 que não deveria receber resposta automática (número
interno/de alerta, não cliente real). Diferente de grupo, não dá para
detectar isso por um padrão no payload — é uma lista específica que
cresce com o tempo (mais números podem precisar ser excluídos depois).

**Decisão**: nova tabela `excluded_contacts` (migration `0005`) —
`tenant_id` (nulo = vale para todos os tenants), `phone` (formato exato
como o Chatwoot normaliza), `reason`. `CORE-00` ganhou um novo passo logo
após o filtro de grupo: consulta `SELECT id FROM excluded_contacts WHERE
phone = $1 LIMIT 1` usando o `contact_phone` extraído do webhook: se
encontrar, responde `{ignored: true, reason: "excluded_contact"}` sem
resolver tenant, persistir nada ou acionar o agente.

**Consequência**: adicionar/remover um número da exclusão é só um `INSERT`/
`DELETE` em `excluded_contacts` — nenhuma mudança de workflow necessária,
consistente com o padrão já usado para tenants/conhecimento. `contact_phone`
só vem preenchido em mensagens de entrada (em mensagens de saída o
`sender` do payload é o usuário do Chatwoot, não o contato — limitação
conhecida da extração atual), então a exclusão hoje só é garantida no
sentido cliente→agente, que é o caso que importa aqui. `tl22TbmEhvxqjpE6`
publicado (versão `8fc823dd-9eae-4e64-868d-ae47ff46b97e`) com
`+5515981772842` já inserido na tabela.

---

## D024 — Painel operacional em n8n (formulários), sem serviço/app novo

**Contexto**: com múltiplos tenants e uma lista de exclusão crescendo, cadastrar
tudo via SQL manual (eu escrevo, Hermes roda) não escala nem é seguro a
longo prazo — o usuário pediu explicitamente por um "painel" depois do
incidente de grupo. Construir uma aplicação web dedicada contradiria D011
(Core em n8n puro, sem novo componente de infra).

**Decisão**: 3 workflows n8n com `n8n Form Trigger`, cada um um formulário
interno que escreve direto no Postgres da plataforma, sem SQL manual:

| Workflow | ID | Função |
|---|---|---|
| PAINEL-01 Onboarding de Tenant | `wvIJS4f12b0AYVYt` | Cria `tenants` + `tenant_features` + `tenant_crm_config` numa submissão |
| PAINEL-02 Adicionar Conhecimento | `Hi1cZ6vKWfM1Eat0` | Insere em `knowledge_documents` para um tenant existente (valida `tenant_key` antes) |
| PAINEL-03 Excluir Contato | `LcCCXfkXcG3yfIeS` | Insere em `excluded_contacts` (D023) |

Todos com `responseMode: lastNode` (só responde depois que o insert
terminar, nunca antes) e `appendAttribution: false`. O `PAINEL-01` não
cria `tenant_channels` — isso continua dependendo de uma mensagem real do
canal novo pra descobrir `account_id`/`inbox_id`, então fica fora do
formulário por ora.

**Consequência (dívida registrada)**: como em todo `create_workflow_from_code`,
a auto-atribuição de credencial (D016) errou nos 3 workflows — corrigida
manualmente logo em seguida. Não há autenticação nesses formulários além
da URL não-adivinhável (mesmo modelo de D019) — aceitável para uso
interno, mas se algum dia forem compartilhados externamente, precisam de
`authentication: basicAuth` ou `n8nUserAuth`. `PAINEL-01` não lida com
`tenant_channels` nem com erro de `tenant_key` duplicado (constraint
`UNIQUE` do banco vai rejeitar, mas a mensagem de erro pro usuário ainda é
genérica do Postgres, não amigável) — melhorar se isso incomodar no uso
real.

---

## D026 — Ferramenta de notificação ao especialista humano (Golden), via AI Agent tool

**Contexto**: depois de validar o pipeline completo (CORE-00→CORE-30) e
isolar a credencial de LLM da Golden (D025), o usuário pediu um último
ajuste: quando a IA (Clara) identifica que um lead está pronto para
agendar a avaliação, o especialista humano da Golden precisa ser avisado
automaticamente — hoje isso só acontecia se o cliente pedisse
explicitamente para falar com alguém, e mesmo assim não havia nenhuma
notificação real, só uma mensagem genérica pro cliente. Entre as opções
(nota interna no Chatwoot, WhatsApp direto, ou os dois), o usuário optou
por **WhatsApp direto para o especialista** (`+55 17 99109-9157`).

**Decisão**: criado `TOOL-10 Notificar Especialista Golden`
(`dvHN17yiFnerXqlh`), um sub-workflow n8n com um `Execute Workflow
Trigger` recebendo `{ resumo: string }`, que busca o contato do
especialista no Chatwoot (conta 7, o mesmo workspace da Golden), abre ou
reaproveita uma conversa aberta com ele, e envia o resumo como mensagem
outgoing via API do Chatwoot (`POST
/api/v1/accounts/7/conversations/{id}/messages`). Retorna
`{ success: boolean, detail: string }`.

Esse sub-workflow foi conectado ao `CORE-10 Agent Orchestrator`
(`pnKnvq3lf1KvjSRz`) como uma **AI Agent tool**
(`@n8n/n8n-nodes-langchain.toolWorkflow`, nó "Notificar Especialista
Tool"), ligado **somente** ao branch "Assistente (Golden)" (o branch
criado em D025) — nenhum outro tenant tem acesso a essa ferramenta, já
que ela é específica do fluxo comercial da Golden. O parâmetro `resumo` é
preenchido pelo próprio LLM via `$fromAI('resumo', <descrição>,
'string')`, com uma descrição detalhada de quando acionar a ferramenta
(material, tipo de peça, avaliação pronta pra agendar) e o que incluir no
resumo. `pnKnvq3lf1KvjSRz` publicado
(`activeVersionId: 8ae97848-ce25-4b80-9fb2-9fb172c6c5e3`).

O script da Golden (`n8n/agents/golden-ouro-prata-sdr.md`, replicado em
`knowledge_documents`) foi atualizado nas seções 8 (Condução para a
avaliação) e 10 (Solicitação de atendimento humano — agora dividida em
10.1 "Notificar Especialista" e 10.2 "Outras situações"), substituindo a
instrução genérica "só execute a transferência se houver ferramenta
autorizada e disponível" por instruções concretas de quando acionar a
ferramenta, o que incluir no resumo, e a regra de só confirmar ao cliente
que o especialista foi avisado se a ferramenta retornar `success: true`.

**Consequência (dívida registrada)**: assim como D025, isso é específico
da Golden — não um sistema genérico de "transferência para humano"
reutilizável por outros tenants. Se um segundo tenant precisar de
notificação semelhante, replicar o padrão (sub-workflow tool + IF de
tenant no CORE-10) é aceitável por ora; generalizar via
`tenant_llm_config`-like config (ex.: `tenant_tools_config`) só quando um
segundo caso real aparecer (YAGNI, mesmo raciocínio de D025). O nó
Postgres de `TOOL-10` sofreu a recorrência de D016 (credencial
auto-atribuída errada) — corrigido manualmente. A inserção do texto
atualizado do script em `knowledge_documents` foi feita via
`n8n-nodes-base.set` (não Postgres/Code+Base64 como em atualizações
anteriores) passando o texto como string JSON direta numa operação
`updateNodeParameters` do `update_workflow` — evita totalmente o
escaping manual de aspas que o Base64 contornava, porque o valor passa
por serialização JSON nativa da chamada de ferramenta, não por um
literal de string em código TS. Workflow utilitário temporário
arquivado depois de usado.

---

**Atualização (2026-09-20)**: o usuário pediu que a notificação inclua o
telefone do possível cliente a agendar, para o especialista saber quem
contatar. Em vez de pedir isso ao LLM via `resumo` (o telefone não é algo
que o cliente digita na conversa — é metadado do canal, não confiável
extrair de texto livre), `CORE-10` passa `conversation_id` (o UUID
interno da conversa, não controlado pelo LLM) como parâmetro fixo do
tool call, e `TOOL-10` ganhou um novo nó "Buscar dados do cliente" que
resolve telefone/nome reais via `conversations JOIN contacts` (mesmo
padrão `COALESCE` de subquery usado em D021/D023, para nunca zerar
linhas). A mensagem final passou a ser: "📞 Cliente: {nome} - {telefone}"
antes do resumo da IA.

Dois bugs de posicionamento de nó apareceram e foram corrigidos no
processo, ambos pela mesma causa raiz — **um nó n8n só é executado (e só
fica disponível para `$("NodeName")`) se estiver no caminho real de
conexões que leva até o nó atual, não basta compartilhar o mesmo
trigger**:
1. Primeira tentativa: "Buscar dados do cliente" ligado em paralelo
   direto no trigger (mesmo padrão usado em outros pontos desta sessão,
   que funcionava por coincidência por estarem todos numa cadeia linear
   única). Erro: `ExpressionError: No path back to referenced node` ao
   usar `$("Buscar dados do cliente").item...` de dentro do node que
   monta a mensagem — n8n exige rastrear o `pairedItem` de volta pela
   cadeia de conexões, e um branch irmão sem conexão para o node atual
   não tem esse caminho.
2. Trocar `.item` por `.first()` (que não depende de `pairedItem`)
   resolveu o erro de expressão, mas revelou o problema real: `Node
   'Buscar dados do cliente' hasn't been executed` — o n8n só executa os
   nodes que estão no caminho de conexões até o node final da run; um
   branch desconectado do caminho principal simplesmente nunca roda.
   Corrigido movendo "Buscar dados do cliente" para dentro da cadeia
   serial principal (depois de "Conversa aberta encontrada?", antes de
   "Enviar notificação ao especialista"), o que também expôs uma
   colisão de nomes: `conversation_id` do cliente (UUID interno) e
   `conversation_id` da conversa do especialista no Chatwoot (inteiro,
   ex. `4`) são coisas diferentes — a URL de envio da mensagem foi
   corrigida para usar explicitamente `$("Encontrar conversa
   aberta").first().json.conversation_id` (o inteiro do Chatwoot), nunca
   `$json.conversation_id` ambíguo.

Testado de ponta a ponta com uma conversa real da Golden (não um UUID
fake): telefone e nome do cliente resolvidos corretamente do banco e a
notificação chegou formatada como esperado — confirmado pelo retorno da
API do Chatwoot (`{success:true}`, mensagem `id 21543` criada na
conversa `4` do especialista). Workflow de teste temporário arquivado
depois de usado. Ainda faltando: testar a IA acionando a ferramenta de
fato dentro de uma conversa real/simulada de ponta a ponta via
`Assistente (Golden)` (só o sub-workflow foi testado diretamente até
agora), e confirmar com o usuário que as mensagens de teste chegaram no
WhatsApp do especialista.

---

**Atualização (2026-09-21)**: usuário pediu reforço no tom de voz —
mensagens mais curtas e humanizadas, e proibição total de emojis. Seção
3 do script reescrita com regras mais concretas (limite de 2-3 frases
por mensagem, evitar repetir de volta o que o cliente disse, variar
aberturas de mensagem em vez de repetir "Entendi!"/"Claro!"/"Sem
problema!", e a regra 6 mudou de "emojis com moderação" para proibição
explícita). Todos os exemplos de mensagem do script (seções 4, 5, 6, 7,
8, 9, 10, 15) tiveram o emoji 😊 removido, para o texto não contradizer
a própria regra nova — um agente seguindo literalmente os exemplos
continuaria usando emoji se os exemplos não fossem corrigidos junto.
Atualizado via o mesmo padrão limpo do D026 (Set node com o texto como
string JSON direta + `updateNodeParameters` com `replace: true`, sem
Base64/Code node). Verificado por query direta no Postgres após a
atualização: a regra de proibição está presente e nenhum emoji restou
no texto salvo.

---

## D027 — Bug crítico: mensagens sem texto (áudio/imagem) travavam a IA sem nenhuma resposta ao cliente

**Contexto**: pedido do usuário pra analisar os logs de execução do n8n em
busca de erros e inconsistências (2026-09-22), depois de um período de
"deixar rodar" para observação em produção. Busca por execuções `error`
nos últimos 2 dias revelou 7 falhas reais em `CORE-02`/`CORE-10` (nomes
técnicos antigos: Message Buffer / Agent Orchestrator) que **não** eram
dos meus próprios testes — aconteceram de verdade, incluindo depois que
o usuário pediu pra aguardar e eu parei de mexer no sistema.

**Causa raiz**: quando um cliente manda uma mensagem sem texto (áudio,
imagem, vídeo, sticker, arquivo — comum em WhatsApp), `CORE-00` grava
`messages.text` como string vazia (`$json.body?.content || ""`, correto
pra esse caso — não há conteúdo textual mesmo). `CORE-02` agregava esse
texto vazio em `aggregated_text: ""` e passava direto pro node do AI
Agent em `CORE-10`. A API do Google Gemini **rejeita input vazio com
erro 400** ("Request has empty input"), travando a execução inteira sem
nenhum fallback — o cliente nunca recebe resposta alguma, e como
`Marcar buffer consumido` já tinha rodado antes da chamada ao agente, a
mensagem nunca é reprocessada automaticamente.

**Descoberta**: confirmado em pelo menos 6 conversas reais distintas da
Golden, desde **2026-09-20 18:02** (a mensagem mais antiga confirmada)
até **2026-09-22 00:42** (a mais recente, capturada durante esta
análise) — ou seja, o bug ficou ativo em produção por quase 2 dias
inteiros sem que ninguém soubesse, porque não existe (ainda) nenhum
alerta de erro de execução configurado (ver dívida em D017/D019 sobre
observabilidade). Clientes afetados (nome/telefone conforme cadastro,
pra follow-up manual se o usuário achar necessário):

| Cliente | Telefone | Quando |
|---|---|---|
| Almeida | +55 17 99114-2194 | 2026-09-20 18:02 |
| Nereide Maria | +55 17 99227-9606 | 2026-09-20 18:08 |
| Valdivino | +55 17 99159-0093 | 2026-09-21 14:58 |
| Eduardo | +55 17 98201-7172 | 2026-09-21 18:37 e 19:11 (duas mensagens de áudio seguidas, ambas travaram) |
| Redomildo Tavares | +55 19 99982-2571 | 2026-09-22 00:42 |

**Decisão**: corrigido em `CORE-02` (nó "Buscar mensagens pendentes" +
"Agregar mensagens"). A query passou a trazer também `messages.type`, e
o código de agregação usa um placeholder textual quando `text` está
vazio, mapeado pelo tipo da mensagem (`audio`, `image`, `video`, `file`,
com fallback genérico) — ex.: `"[O cliente enviou uma mensagem de audio
- sem transcricao disponivel]"`. Isso garante que `aggregated_text`
nunca chega vazio no `CORE-10`, e dá à IA contexto suficiente pra
responder algo sensato (ex.: "Recebi seu áudio, mas por enquanto só
processo texto — pode escrever, por favor?") em vez de travar. Testado
e publicado (`activeVersionId: 10ac2cf4-1898-432d-8d9e-5b0a7d5a3c60`).

**Consequência (dívida registrada)**: (1) nenhum dos 6 clientes afetados
foi notificado automaticamente — cabe ao usuário decidir se quer fazer
contato manual com algum deles, lista acima. (2) Esse é exatamente o
tipo de falha que um error workflow / alerta proativo (D017 menciona
LLM Router/fallback, mas isso é sobre outra camada — falta um alerta
genérico de "execução falhou" pro operador, não só pro LLM) teria
pegado em minutos, não em 2 dias — vale considerar configurar
`errorWorkflow` nas settings dos workflows core apontando pra um
workflow simples de notificação (WhatsApp/e-mail pro usuário) quando
qualquer execução core falhar. (3) O mesmo padrão de "texto vazio quebra
o LLM" pode existir em outros pontos não cobertos por este teste
(ex.: se um tenant novo sem Golden usar outro provider de LLM com
comportamento de erro diferente pra input vazio) — a correção em
`CORE-02` é genérica o bastante (não é Golden-específica) pra cobrir
todos os tenants atuais e futuros que passam por essa mesma cadeia.

---

## D028 — Nomes dos workflows e organização em pastas no n8n

**Contexto**: usuário relatou que os nomes técnicos dos workflows
(`CORE-00 Inbound Gateway (Chatwoot)`, `CORE-10 Agent Orchestrator`,
etc.) e todos os 9 soltos numa pasta só do n8n dificultavam bater o
olho e saber qual é qual — especialmente depois da discussão sobre se
valeria a pena juntar tudo num workflow só (decidido que não, ver
raciocínio abaixo).

**Decisão**: (1) Criadas 3 subpastas dentro de "Agente de atendimento
IA" no n8n: "Fluxo Principal (CORE)", "Ferramentas dos Agentes (TOOL)"
e "Painel Operacional (PAINEL)", e os 9 workflows movidos para a pasta
correspondente. (2) Nome de exibição de cada workflow reescrito em
português simples, mantendo o prefixo técnico (`CORE-NN`/`TOOL-NN`/
`PAINEL-NN`) que já é usado em toda a documentação e no código de
commits — só a parte descritiva mudou:

| Antes | Depois |
|---|---|
| CORE-00 Inbound Gateway (Chatwoot) | CORE-00 · Recebe Mensagem do Cliente (Chatwoot) |
| CORE-01 Tenant Resolver | CORE-01 · Identifica a Empresa (Tenant) |
| CORE-02 Message Buffer | CORE-02 · Junta Mensagens Picadas (Buffer) |
| CORE-10 Agent Orchestrator | CORE-10 · IA Gera a Resposta (Agente) |
| CORE-30 Output Gateway | CORE-30 · Envia Resposta ao Cliente (Chatwoot) |
| TOOL-10 Notificar Especialista Golden | TOOL-10 · Avisar Especialista Golden (WhatsApp) |
| PAINEL-01 Onboarding de Tenant | PAINEL-01 · Cadastrar Empresa Nova |
| PAINEL-02 Adicionar Conhecimento | PAINEL-02 · Adicionar Regra/Conhecimento |
| PAINEL-03 Excluir Contato | PAINEL-03 · Excluir Contato do Agente |

Rename não afeta `workflowId` nem as chamadas via Execute Workflow
(que referenciam por ID, não por nome), então não quebrou nenhuma
conexão entre workflows — confirmado que todas as execuções continuam
funcionando normalmente depois do rename.

**Sobre juntar tudo num workflow só (rejeitado)**: `CORE-01`, `CORE-10`
e `CORE-30` são sub-workflows reutilizados por múltiplas entradas — hoje
só `CORE-00` (Chatwoot) chama essa cadeia, mas o desenho já prevê
`CRM-11`/`CRM-12` (Kommo/DataCry, ainda não implementados) chamando os
mesmos `CORE-01`/`CORE-10`/`CORE-30` sem duplicar lógica. Um workflow
único perderia essa reutilização, e — na prática, durante a
investigação do D027 — foi exatamente a separação por `executionId`
entre sub-workflows que permitiu isolar a falha (áudio → texto vazio →
Gemini 400) em 3 chamadas de ferramenta, rastreando o `executionId` de
erro de um sub-workflow pro outro. Um workflow monolítico tornaria esse
tipo de debug mais lento. A queixa de "muito item pra olhar" é resolvida
pela reorganização em pastas acima e, futuramente, pelo painel externo
(visão do pipeline sem precisar abrir o n8n).

**Consequência (dívida registrada)**: os arquivos `.md` de spec em
`n8n/core/` (títulos, texto) e os nomes de arquivo dos `.json`
exportados (`n8n/core/CORE-00-inbound-gateway-chatwoot.json` etc.) não
foram renomeados — só o campo `name` dentro de cada `.json` foi
atualizado pra bater com o nome novo no n8n. Os nomes de arquivo em si
continuam com a descrição antiga; renomear os arquivos exigiria
atualizar todos os links/menções cruzadas no repo, não fizemos isso
agora por ser puro custo sem ganho funcional.

## D029 — Sticky notes de orientação nos workflows do n8n

**Contexto**: usuário pediu orientações detalhadas em cada workflow,
como post-its nos nós, explicando decisões e observações — pra quem
abrir o canvas no n8n conseguir entender o fluxo sem precisar consultar
a documentação do repo.

**Decisão**: adicionadas sticky notes explicando clusters de nós,
decisões de design e avisos de bugs críticos (ex: a nota em CORE-02
menciona o bug D027 diretamente no nó "Agregar mensagens", pra quem
mexer ali no futuro não reintroduzir o problema) em 8 dos 9 workflows:
CORE-00 (5 notas), CORE-01 (1), CORE-02 (3), CORE-10 (3), CORE-30 (2),
TOOL-10 (2), PAINEL-02 (1), PAINEL-03 (1). PAINEL-01 não recebeu nota
nova porque já tinha uma sticky note grande e completa com o manual
operacional inteiro. Todos publicados no n8n com sucesso.

**Consequência (dívida registrada)**: o `versionId` de cada `.json`
exportado no repo foi atualizado pra bater com a versão publicada no
n8n (histórico de versão correto), mas o **conteúdo das sticky notes em
si não foi replicado dentro dos arrays `nodes` dos `.json`** — os
arquivos no repo ainda refletem só a lógica/queries/código dos nós
funcionais, não as notas de documentação em texto. Prioridade foi
manter o `versionId` (rastreabilidade de qual snapshot é o mais atual)
em vez de duplicar texto de documentação em dois lugares (canvas do
n8n + `.json` do repo), o que criaria risco de divergência. Se for
necessário auditar o texto exato das notas no futuro, a fonte de
verdade é o n8n (via `get_workflow_details`), não o `.json` do repo.

## D030 — Transcrição real de áudio (Google Gemini) no CORE-00

**Contexto**: mesmo depois do D027 (fix do bug crítico que travava a
IA em mensagens sem texto), áudios de clientes continuavam sem ser
efetivamente entendidos — o CORE-02 só substituía o texto vazio por um
placeholder genérico ("[O cliente enviou uma mensagem de áudio - sem
transcrição disponível]"), então a IA nunca sabia o que o cliente
realmente falou no áudio. Usuário pediu pra usar um fluxo pessoal dele
de transcrição de áudio (`WhatsApp - Transcrição de áudios GUI - 7622`,
fora deste projeto, baseado em Wuzapi + Google Gemini) como referência
pra resolver isso de verdade.

**Decisão**: adicionado no `CORE-00`, logo após confirmar que a
mensagem é de entrada válida (já passou pelos filtros de grupo/contato
excluído/tenant resolvido — evita gastar chamada de API à toa), um
branch condicional `É áudio?` (`message_type == audio`):
1. **Baixar áudio (Chatwoot)** — HTTP Request baixa o arquivo original
   via `data_url` do attachment do webhook do Chatwoot (`responseFormat:
   file`).
2. **Transcrever áudio (Gemini)** — Google Gemini (`resource: audio,
   operation: transcribe`, `inputType: binary`), usando a credencial
   genérica `Google Gemini(PaLM) Api gui` (não a key exclusiva da
   Golden, já que o CORE-00 atende todos os tenants).
3. **Aplicar transcrição** — Code node reconstrói o item com os dados
   do tenant (`CORE-01 Tenant Resolver`) + `transcribed_text`.

`Montar Universal Message` foi ajustado pra usar
`tenant.transcribed_text || source.message_text` no campo
`message.text` — ou seja, a transcrição tem prioridade, mas cai pro
texto original (vazio, pra áudio) se não houver transcrição.

Adaptação em relação ao fluxo de referência do usuário: **a transcrição
não é reenviada como mensagem ao cliente** (o fluxo original mandava de
volta via WhatsApp com um prefixo "⚡️ Transcrição"). Aqui ela só
alimenta o entendimento da IA internamente — o cliente continua vendo
só a resposta normal do agente, igual hoje.

**Testado**: validado isoladamente com um workflow temporário (áudio
público de teste, arquivo `brooklyn.flac` da Google Cloud), confirmando
o formato real de saída do node (`content.parts[0].text`, não `text`
puro) e que a transcrição funciona fim a fim antes de publicar no
CORE-00 de produção.

**Consequência (rede de segurança preservada)**: os 2 nós novos têm
`onError: continueRegularOutput`. Se o download ou a transcrição
falhar por qualquer motivo (API fora do ar, `data_url` inválida etc.),
a mensagem segue com texto vazio e cai no placeholder do D027 — nunca
trava o fluxo nem reintroduz o bug crítico anterior. O placeholder do
D027 no CORE-02 continua existindo como último fallback (áudio sem
transcrição bem-sucedida, imagem, vídeo, arquivo).

**Pendência**: envio de áudio (texto→voz) na resposta da IA ainda não
existe — ficou combinado avaliar ElevenLabs (melhor qualidade de voz em
PT-BR) quando essa etapa for priorizada.

## D031 — TOOL-11: gera áudio da resposta via Gemini TTS (sub-workflow, ainda não plugado)

**Contexto**: usuário pediu um fluxo "como o da LLM que cria a mensagem"
(CORE-10) mas que aceitasse mais de uma mensagem — pra gerar áudio da
resposta da IA (texto→voz), já que a resposta pode vir em vários balões
curtos (regra de tom de voz humanizado). Perguntei se seguia com Gemini
(HTTP cru, sem credencial nova, mais frágil) ou trocava pra ElevenLabs
(node pronto, melhor voz PT-BR, mas credencial nova) — usuário escolheu
Gemini por ora.

**Descoberta técnica**: o node nativo do Google Gemini no n8n
(`@n8n/n8n-nodes-langchain.googleGemini`) só expõe `audio: analyze` e
`audio: transcribe` — **não tem operação de geração de áudio (TTS)**.
Só existe TTS pronto no n8n via node do MiniMax (`audio:
textToSpeech`), que é outro provedor. Pra usar Gemini TTS de fato, é
preciso chamar a API REST do Google direto (`generateContent` com
`responseModalities: [AUDIO]`).

**Decisão**: criado `TOOL-11 · Gerar Áudio da Resposta (Gemini TTS)`
(`Nz8vqqYDRpJbyrsm`, pasta TOOL), no mesmo padrão de sub-workflow
chamável do CORE-10 (Execute Workflow Trigger → processamento →
saída):
1. **Gerar Audio Input** — aceita `{ tenant_id, conversation_id, texts:
   string[] }` (uma ou mais mensagens, por isso "aceita mais de um").
2. **Expandir textos** — Code node vira um item por texto.
3. **Gerar audio (Gemini TTS)** — HTTP Request direto pra
   `generativelanguage.googleapis.com`, modelo
   `gemini-2.5-flash-preview-tts`, voz `Kore`, reaproveitando a
   credencial `googlePalmApi` já existente (`aAcNvv8DFFBT08Sy`) via
   `authentication: predefinedCredentialType` — **sem credencial
   nova**. `onError: continueRegularOutput`: se um texto falhar, os
   outros da lista continuam gerando normalmente.
4. **Converter PCM para WAV** — Gemini devolve PCM cru em base64 (taxa
   de amostragem embutida no `mimeType`, ex. `rate=24000`), não um
   arquivo pronto. Code node monta um cabeçalho WAV de 44 bytes na mão
   e concatena com o PCM, virando um binário `audio/wav` reproduzível.

**Bug encontrado e corrigido durante o teste**: depois do node HTTP,
`$json` passa a ser a resposta da API do Gemini — os campos originais
(`tenant_id`, `conversation_id`, `text`) que estavam no item antes da
chamada HTTP somem do `$json` (a chamada HTTP substitui o item, não
mescla). O "Converter PCM para WAV" tinha que buscar esses 3 campos de
volta em `$("Expandir textos").item.json`, não em `$json`. Testado
isoladamente (2 textos, os 2 geraram WAV válido ~150-200KB cada) antes
de publicar.

**Escopo desta entrega**: só a geração do áudio. **Não plugado** no
CORE-10/CORE-30 — o workflow existe e funciona isoladamente, mas
ninguém chama ele em produção ainda. Fica pra quando o usuário decidir
como e quando enviar áudio de fato ao cliente.

**Dívidas registradas**:
- Sem credencial nova (bom), mas HTTP cru é mais frágil a mudança de
  contrato da API do Google do que um node dedicado seria.
- Saída é WAV; nota de voz nativa do WhatsApp normalmente espera
  ogg/opus — pode ser necessário converter antes de enviar via
  Chatwoot, dependendo de como o Chatwoot/WhatsApp Business API tratam
  anexo de áudio que não é ogg/opus. Não testado end-to-end com envio
  real ainda.
- ElevenLabs continua como alternativa de melhor qualidade, avaliada
  e adiada a pedido do usuário.

## D032 — Cadência de follow-up automática (TOOL-12 + CORE-40 + tabela nova)

**Contexto**: usuário pediu um "tool de follow-up" — a IA (CORE-10) precisa
conseguir reengajar um cliente que sumiu da conversa (ex.: "vou pensar",
"te aviso depois") sem precisar de intervenção manual. Desenho fechado com
o usuário: **3 lembretes ("cutucões") + 1 mensagem final de encerramento
("ultimato")**, parando automaticamente se o cliente responder ou se um
humano assumir a conversa.

**Decisão — arquitetura em 3 peças**:

1. **Migration `0006_scheduled_followups.sql`** — tabela nova
   `scheduled_followups` (`tenant_id`, `conversation_id`, `cadence_id`
   agrupando as 4 etapas de uma mesma cadência, `step` 1-4, `kind`
   `nudge`/`ultimatum`, `reason` só para auditoria, `message` já pronto
   pra envio, `scheduled_for`, `status` `pending`/`sent`/`canceled`).
   Aplicada no banco real via workflow temporário (arquivado depois).

2. **`TOOL-12 · Agendar Follow-up`** (`uUeP75hDpxJsZ3nV`, pasta TOOL) —
   AI Agent tool plugada em **ambos** os branches do CORE-10 (Assistente
   padrão e Assistente Golden, diferente do TOOL-10 que é exclusivo da
   Golden — reengajamento é comportamento genérico, não específico de
   tenant). A IA só decide **quando** começar
   (`dias_para_primeiro_contato`, via `$fromAI`) e **por quê**
   (`resumo`, só pra auditoria — nunca vai pro cliente). O texto de cada
   uma das 4 etapas é fixo/padronizado no código do workflow, não escrito
   pela IA por etapa — evita mensagens de cobrança mal calibradas e
   mantém tom consistente. Intervalo fixo de 2 dias entre etapas
   (`baseDays`, `baseDays+2`, `+4`, `+6`).

3. **`CORE-40 · Envia Follow-ups Agendados`** (`Bo9VJIm7M436jpmC`, pasta
   CORE) — Schedule Trigger a cada 30 min. Pra cada etapa vencida:
   cancela a **cadência inteira** (todas as etapas `pending` do mesmo
   `cadence_id`, não só a etapa atual) se o cliente mandou mensagem
   `incoming` depois que a etapa foi criada, ou se a conversa está
   `HUMAN_ACTIVE`/`CLOSED`; senão, envia de verdade via CORE-30 (mesmo
   canal das respostas normais da IA) e marca como `sent`.

**Testado antes de publicar**: TOOL-12 isolado (4 etapas inseridas
corretamente numa conversa real da Golden, depois apagadas) e CORE-40
com dados 100% sintéticos (2 conversas fake — uma com resposta simulada
depois do agendamento, outra sem) confirmando que a rota de cancelamento
e a rota de envio disparam certo, sem tocar em nenhuma conversa real.

**Consequências / dívidas registradas**:
- Se o CORE-30 falhar no meio do envio dentro do CORE-40 (ex.: Chatwoot
  fora do ar), a etapa fica `pending` e é retentada no próximo ciclo de
  30 min — correto pra falha transitória, mas se o envio for bem
  sucedido e algo falhar depois disso (raro), pode reenviar no próximo
  ciclo. Não tratado.
- Intervalo entre etapas (2 dias) e frequência de varredura do CORE-40
  (30 min) estão fixos no código, não configuráveis por tenant ainda —
  generalizar só se um segundo tenant precisar de cadência diferente
  (mesmo raciocínio YAGNI do D025).

## D033 — TOOL-11 trocado de Gemini TTS pra EdgeGo Voice (auto-hospedado)

**Contexto**: o TOOL-11 (D031) usava a API do Gemini via HTTP cru pra
gerar áudio, porque o node nativo do Gemini no n8n não tem operação de
TTS. Isso deixou duas dívidas registradas: (1) integração frágil, sem
node dedicado, sujeita a mudança de contrato da API do Google; (2) saída
em WAV (PCM cru + cabeçalho montado na mão), não no formato Opus que o
WhatsApp espera pra nota de voz nativa. ElevenLabs foi avaliado como
alternativa de melhor qualidade mas adiado por exigir credencial nova.

Usuário encontrou `gaugusto26/edgego-voice` — um servidor TTS próprio,
auto-hospedado, em Go, compatível com a API da OpenAI (`/v1/audio/speech`
e `/v1/persona/{id}/speech`), usando vozes neurais gratuitas do
Microsoft Edge TTS. Já vinha com uma persona pré-configurada
`whatsapp-suporte`, em formato **Opus** — resolvendo exatamente a
segunda dívida do D031.

**Decisão**: o deploy do serviço (Docker, mesma rede do n8n) foi feito
por uma sessão externa ("Hermes", outra sessão/agente de IA do usuário,
não esta) a partir de um prompt fornecido nesta sessão. Confirmado pelo
usuário:
- Serviço rodando e saudável, acessível pelo n8n em `http://edgego-voice:5050`.
- Persona `whatsapp-suporte` gera Opus válido.
- Autenticação Bearer obrigatória, porta 5050 não exposta à internet.
- n8n/Postgres/Chatwoot não foram tocados.
- A API key nunca passou pelo chat — ficou só no `.env` do serviço; o
  usuário criou a credencial `EdgeGo Voice Bearer` (Header Auth,
  `Authorization: Bearer <key>`) diretamente no n8n, e eu só referenciei
  o nome/ID dela (mesma prática de segurança usada em todo o projeto).

No TOOL-11: removidos os nós "Gerar audio (Gemini TTS)" e "Converter PCM
para WAV" (que fazia o parse manual do PCM base64 e montava o cabeçalho
WAV), substituídos por um único node HTTP Request chamando
`POST http://edgego-voice:5050/v1/persona/whatsapp-suporte/speech` com
`responseFormat: file` — o serviço já devolve o áudio Opus pronto, sem
nenhuma conversão manual necessária. Um node "Aplicar metadata" (Code)
reconstrói `tenant_id`/`conversation_id`/`text` (perdidos depois da
chamada HTTP, mesmo padrão de cuidado já documentado no D030) e repassa
o binário do áudio adiante.

**Testado** antes de publicar: 2 textos de teste, ambos geraram Opus
válido (~17KB cada) com metadata preservada corretamente.

**Consequência**: TOOL-11 continua **não plugado** no pipeline principal
(CORE-10/CORE-30) — só a geração ficou mais simples/robusta e resolvida
a questão do formato. ElevenLabs não é mais necessário como alternativa,
já que o EdgeGo Voice é gratuito e auto-hospedado. Fica pendente decidir
quando/como integrar isso ao fluxo de resposta de fato.

## D034 — Cadência de follow-up: de dias pra horas, e de 4 pra 5 etapas

**Contexto**: usuário pediu pra diminuir o tempo da cadência do D032
(que usava dias) pra: **5h sem resposta, 12h, 24h, 36h e 48h como
ultimato** — 4 lembretes + 1 encerramento, mesmas regras de
cancelamento de antes (cliente respondeu, ou disse que não tem mais
interesse — qualquer mensagem `incoming` já cancela a cadência inteira,
não precisa checar o conteúdo).

**Decisão**:
1. **Migration `0007_scheduled_followups_five_steps.sql`** — o `CHECK
   (step BETWEEN 1 AND 4)` da migration 0006 virou `BETWEEN 1 AND 5`
   (`ALTER TABLE ... DROP CONSTRAINT ... ADD CONSTRAINT`). Aplicada no
   banco real via workflow temporário (arquivado depois).
2. **TOOL-12 "Montar cadencia"** reescrito pelo usuário diretamente no
   n8n: os 5 passos agora usam `offsetHours` (5, 12, 24, 36, 48) a
   partir do momento em que a ferramenta é chamada, em vez de
   `offsetDays` calculado sobre um `dias_para_primeiro_contato` variável
   escolhido pela IA.
3. **Removido `dias_para_primeiro_contato`** dos dois lugares que
   dependiam dele (ficaram órfãos depois da mudança acima): o
   `jsonExample` do trigger "Agendar Follow-up Input" no TOOL-12, e o
   `$fromAI('dias_para_primeiro_contato', ...)` na ferramenta "Agendar
   Follow-up Tool" do CORE-10 — a IA agora só decide o `resumo`
   (motivo, só para auditoria); não decide mais quando começar, já que
   os horários são fixos a partir da chamada.
4. Textos que citavam "3 lembretes"/"2 dias" atualizados pra "4
   lembretes"/horas em: descrição do TOOL-12, texto de confirmação
   (`Confirmar agendamento`), sticky note do TOOL-12, e a descrição da
   ferramenta no CORE-10.

**Testado**: cadência de teste numa conversa real da Golden (dados
apagados depois) confirmando os 5 offsets corretos (~5h/12h/24h/36h/48h
a partir da chamada) antes de publicar.

**Consequência**: CORE-40 não precisou de nenhuma mudança — a lógica de
varredura/cancelamento/envio lá é genérica em relação ao número de
etapas e à unidade de tempo, só olha `scheduled_for <= now()`.

---

## D035 — Áudio entra, áudio sai: TOOL-11 plugado no pipeline principal (roteamento determinístico)

**Contexto**: TOOL-11 (D031/D033) gerava áudio da resposta mas nunca foi
conectado ao fluxo real — a IA sempre respondia em texto, mesmo quando o
cliente mandava áudio. Usuário pediu, como regra fixa: *"Audio envia
audio, texto envia texto!"* — se o cliente manda áudio, a resposta
também deve ser áudio; se manda texto, resposta em texto.

**Decisão de design**: essa regra é **determinística**, calculada a
partir do `type` da mensagem desde o `CORE-02` e carregada como
`input_type` até o `CORE-10` — **não é o LLM que decide chamar uma
tool** pra gerar áudio. Uma tool call é probabilística (o modelo pode
esquecer de chamar); o formato de saída (texto vs. áudio) precisa ser
sempre respeitado, então fica fora do julgamento do LLM, no mesmo
espírito do tratamento determinístico de tipo/formato já usado no D030
(transcrição) e D027 (placeholder por tipo de mídia).

**Implementação, nos 3 workflows**:

1. **`CORE-02` ("Agregar mensagens")**: além de montar `aggregated_text`,
   agora também detecta se alguma mensagem do lote bufferizado tem
   `type === 'audio'` e manda `input_type: 'audio'|'text'` pro `CORE-10`
   junto com `aggregated_text` (lote com mistura de áudio + texto ainda
   conta como `audio` — basta uma mensagem de áudio no lote).
2. **`CORE-10`**: depois de "Salvar resposta como mensagem" (a IA já
   gerou o texto normalmente, sem nenhuma mudança no Assistente/branch
   Golden), um IF **"É audio de entrada?"** olha `input_type` (nunca o
   conteúdo da resposta):
   - Se `audio`: chama **"Gerar audio da resposta"** (Execute Workflow →
     TOOL-11) passando o texto que a IA já gerou como `texts: [texto]`.
     Um segundo IF **"Audio gerado?"** checa `audio_generated` — se
     `true`, chama **"CORE-30 Output Gateway (audio)"** com
     `channel_type: 'audio'` (o binário do TOOL-11 flui automaticamente
     no item, não precisa ser passado como campo); se `false` (TOOL-11
     falhou — serviço fora do ar etc.), **fallback pro texto normal**
     via **"CORE-30 Output Gateway (fallback texto)"** — nunca deixa o
     cliente sem resposta só porque a geração de áudio falhou.
   - Se `text`: segue o caminho original inalterado, só que agora
     passando `channel_type: 'text'` explicitamente pro CORE-30.
3. **`CORE-30`**: ganhou `channel_type` no trigger e um IF **"É
   audio?"**:
   - Se `audio`: **"Preparar envio de audio"** (Code) reanexa o binário
     original (`$("Output Gateway Input").item.binary`) — os 3 nós
     Postgres anteriores (conversa/conta/base_url) sobrescrevem o
     binário do item, mesmo padrão de reanexação já usado no TOOL-11 —
     e **"Enviar audio no Chatwoot"** manda a mensagem como
     `multipart/form-data` (`attachments[]` via `formBinaryData` +
     `message_type: outgoing`), não JSON, porque a API do Chatwoot exige
     multipart pra anexo.
   - Se `text`: segue o caminho original ("Enviar mensagem no
     Chatwoot", JSON), sem nenhuma mudança.
   - Os dois caminhos convergem num novo nó **"Mensagem enviada no
     Chatwoot"** (Code) que normaliza o `id` retornado por qualquer um
     dos dois envios num campo estável (`chatwoot_message_id`) — existe
     porque agora há dois nós de envio possíveis, e "Atualizar
     external_id da mensagem"/"Log evento response_sent" (D021, crítico
     pra detecção de eco no CORE-00) precisam de uma referência única,
     não ambígua entre os dois.

**Duas incertezas técnicas validadas antes de construir o pipeline
real** (ambas confirmadas com testes isolados, antes de qualquer
mudança nos workflows de produção):
1. Se o corpo HTTP `multipart/form-data` do n8n realmente anexa dado
   binário corretamente pro Chatwoot — confirmado com uma chamada real
   contra uma conversa sintética inexistente (404 limpo do Chatwoot,
   não erro de parsing da requisição, prova que o multipart foi bem
   formado).
2. Se dado binário sobrevive ao ser passado como entrada de um
   sub-workflow via nó Execute Workflow, inclusive em múltiplos saltos
   (`CORE-10` → `TOOL-11` → `CORE-30`) — confirmado com um teste
   isolado dedicado antes de plugar no fluxo real.

**Testado de ponta a ponta** antes de publicar: execução real com LLM
de verdade (resposta gerada de fato) e geração de áudio real (EdgeGo
Voice, D033) contra dados de conversa sintéticos (`external_id` falso) —
confirmando cada etapa (decisão de roteamento, chamada ao TOOL-11,
binário atravessando os dois saltos de Execute Workflow, montagem do
multipart). Só a entrega final no Chatwoot não pôde ser confirmada com
sucesso real, porque a conversa era sintética (404 esperado, mesma
prática de teste seguro usada em toda a sessão).

**Consequência**: "áudio entra, áudio sai" está ativo em produção para
todos os tenants (a lógica não é específica de nenhum tenant). Se
`EdgeGo Voice` ficar indisponível, o cliente que mandou áudio recebe a
resposta em texto (fallback), nunca fica sem resposta nenhuma. `CORE-02`
(`uBQGxhCMBQEasbLa`, versão `8945c232-c40b-47d3-80fc-fd46015a7f17`),
`CORE-10` (`pnKnvq3lf1KvjSRz`, versão
`a93f257b-86ed-4ec6-a8e7-32ed256b91e0`) e `CORE-30`
(`04QWtEuiCRQt0vov`, versão `1637d7a2-ca52-40b3-9a48-2ebe43a2a8ef`)
publicados.

---

## D036 — LLM Router: segundo modelo Gemini como fallback via error-output branching

**Contexto**: fecha a dívida do D017 (sem LLM Router/fallback), agravada
pelos 3 incidentes reais documentados na atualização de 2026-09-24 (Gemini
503 "high demand", cliente da Golden sem resposta). O retry automático
ativado naquele dia (`retryOnFail`) mitiga falhas curtas, mas não cobre
uma indisponibilidade do modelo primário que persista por vários segundos
ou minutos. Usuário decidiu o escopo: fallback pra um **segundo modelo
Gemini** (mesmo provider, sem credencial nova) e valendo pra **todos os
tenants** (não só a Golden), implementado de forma genérica no `CORE-10`.

**Tentativa descartada**: a documentação do SDK do n8n (`get_node_types`)
descreve o parâmetro `model` do nó AI Agent como
`LanguageModelInstance | LanguageModelInstance[]`, sugerindo suporte
nativo a múltiplos Chat Models conectados na mesma entrada (com
`needsFallback: true` como toggle). Na prática, **essa instância do n8n
rejeita isso**: conectar um segundo `ai_languageModel` no mesmo Agent
(mesmo em índices diferentes) gera o aviso de validação
`DUPLICATE_SUBNODE_CONNECTION` ("this input accepts only one"). Tentativa
revertida antes de publicar qualquer coisa quebrada.

**Decisão**: fallback via **error-output branching**, o mesmo padrão já
usado em outros pontos do projeto (ex.: download/transcrição de áudio no
D030, `onError: continueRegularOutput`) — aqui com `onError:
continueErrorOutput`, que dá ao nó uma segunda saída (erro) em vez de
parar o workflow:

1. `Assistente` e `Assistente (Golden)` ganharam `onError:
   continueErrorOutput` (além do `retryOnFail` já ativo — primeiro tenta
   de novo automaticamente, só cai pro fallback se o retry também
   falhar).
2. Dois nós **novos**, duplicando cada Agent original mas com modelo
   diferente: **"Assistente (Fallback)"** e **"Assistente (Golden
   Fallback)"** — mesmo `systemMessage`/prompt, mesma memória
   (`Memoria da conversa`, reconectada também nesses dois) e mesmas
   tools (`Agendar Follow-up Tool` nos dois; `Notificar Especialista
   Tool` só no fallback da Golden, espelhando a regra D025/D026 de que
   só o branch Golden tem acesso a essa ferramenta).
3. Dois Chat Model novos — **"Google Gemini Chat Model (Fallback)"** e
   **"Google Gemini Chat Model (Golden Fallback)"** — modelo
   `models/gemini-2.5-flash` (diferente do primário
   `gemini-3.1-flash-lite`, pra reduzir a chance de os dois passarem
   pelo mesmo incidente de sobrecarga), usando a mesma credencial do
   branch correspondente (compartilhada ou `GOLDEN OURO GEMINI API
   KEY`) — preserva o isolamento de quota do D025, sem credencial nova.
4. A saída de erro (índice 1) de `Assistente`/`Assistente (Golden)`
   alimenta o Agent de fallback correspondente; ambos os fallbacks
   convergem no mesmo `Salvar resposta como mensagem` que já recebia os
   dois branches originais — nenhuma mudança downstream (CORE-30,
   roteamento de áudio do D035) foi necessária.

**Testado antes de publicar**: quebrado propositalmente o `modelName` do
"Google Gemini Chat Model (Golden)" pra um valor inválido, criados
`contact`/`conversation` sintéticos reais no tenant da Golden (mesmo
padrão de teste seguro de sempre), e executado o `CORE-10` de ponta a
ponta via workflow utilitário temporário. Confirmado nos dados da
execução: `Assistente (Golden)` foi pra saída de erro, `Assistente
(Golden Fallback)` gerou a resposta normalmente ("Ignorei.", coerente com
o texto de teste), e `Salvar resposta como mensagem` gravou certinho.
Modelo primário restaurado, dados sintéticos apagados, e os 3 workflows
utilitários (setup/teste/cleanup) arquivados depois de usados.

**Consequência**: cobre o cenário mais comum de indisponibilidade
(sobrecarga momentânea de um modelo específico do Gemini). **Não** cobre
uma indisponibilidade da conta Google inteira (billing, API key
revogada, outage geral do Gemini) — os dois modelos usam a mesma
credencial por branch, então uma falha na credencial em si ainda derruba
os dois. Um router cross-provider de verdade (ex.: OpenAI como terceira
opção, hoje sem crédito — D017) continua como trabalho pendente se esse
cenário se mostrar necessário. `CORE-10` (`pnKnvq3lf1KvjSRz`) publicado,
`activeVersionId: 53a32cda-92a8-4dde-a8ee-a7d7a94765d9`.
