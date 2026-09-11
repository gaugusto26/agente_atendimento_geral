-- Seed inicial do Model Registry. Nenhuma credencial aqui — apenas metadados
-- públicos de modelo. Custos são aproximados e devem ser revisados
-- periodicamente contra a tabela de preços de cada provider.

INSERT INTO llm_models
    (provider, model, enabled, supports_tools, supports_vision, supports_json, supports_embeddings, priority, max_context, timeout_ms)
VALUES
    ('openai',    'gpt-4o-mini',              true, true,  true,  true,  false, 100, 128000, 30000),
    ('openai',    'gpt-4o',                   true, true,  true,  true,  false, 50,  128000, 30000),
    ('openai',    'text-embedding-3-small',   true, false, false, false, true,  100, NULL,   15000),
    ('anthropic', 'claude-sonnet-5',          true, true,  true,  true,  false, 60,  200000, 30000),
    ('google',    'gemini-2.5-flash',         true, true,  true,  true,  false, 100, 1000000, 30000)
ON CONFLICT (provider, model) DO NOTHING;

-- NOTA: esta é uma lista de partida para viabilizar o LLM Router na Fase 2.
-- Deve ser revisada/ajustada assim que o profile real por tenant (FAST /
-- STANDARD / ADVANCED / VISION / STRUCTURED) for definido.
