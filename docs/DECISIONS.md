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
