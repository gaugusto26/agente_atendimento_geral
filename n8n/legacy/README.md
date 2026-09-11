# Legacy — referência, não copiado para este repositório

Os workflows do projeto de referência ("Secretária IA") **não foram
copiados** para dentro deste repositório novo. Eles continuam no repositório
original (`gaugusto26/Secretaria-IA-Automacao-Atendimento-WhatsApp-n8n-OpenAI`,
branch `claude/nifty-einstein-w85tr6`, pasta raiz).

Motivo (ver `docs/DECISIONS.md#d006` e `#d005`): 5 dos 6 arquivos têm
marcadores de conflito de merge Git não resolvidos e não são JSON válido
hoje, e todos contêm infraestrutura hardcoded do ambiente do cliente de
referência (IPs, endpoint MCP, ID de voz, ID de pasta do Drive) que não deve
entrar no histórico deste projeto novo, nem como exemplo.

Um resumo já analisado da lógica desses workflows está em
`docs/ARCHITECTURE_PLAN.md` (Seção "Estado atual do repositório" / "Problemas
encontrados") no repositório original. Consulte esse documento para extrair
conceitos — nunca importe os arquivos legados diretamente aqui.
