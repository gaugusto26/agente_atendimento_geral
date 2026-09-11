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
