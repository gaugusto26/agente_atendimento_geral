# Provisionando o Postgres da plataforma (self-hosted, ao lado do n8n)

Este banco é **separado** do Postgres interno do n8n (ver decisão no README
da raiz). Se você roda n8n via docker-compose, o jeito mais simples é
adicionar um novo serviço Postgres à mesma stack, na mesma rede, mas com
seu próprio volume/usuário/porta.

## 1. Adicionar o serviço ao seu `docker-compose.yml`

```yaml
services:
  # ... seus serviços existentes do n8n ...

  agent_platform_postgres:
    image: pgvector/pgvector:pg16   # já vem com a extensão pgvector pronta
    restart: unless-stopped
    environment:
      POSTGRES_USER: agent_platform
      POSTGRES_PASSWORD: ${AGENT_PLATFORM_DB_PASSWORD}
      POSTGRES_DB: agent_platform
    volumes:
      - agent_platform_pgdata:/var/lib/postgresql/data
    ports:
      - "5433:5432"   # porta diferente da do Postgres do n8n (geralmente 5432)
    networks:
      - <mesma rede docker do seu n8n>   # ex.: "n8n_default" — confira com `docker network ls`

volumes:
  agent_platform_pgdata:
```

`AGENT_PLATFORM_DB_PASSWORD` vai no `.env` da sua stack (nunca no
`docker-compose.yml` em texto puro). Suba com:

```bash
docker compose up -d agent_platform_postgres
```

## 2. Rodar as migrations

De dentro do container (não precisa `psql` instalado no host):

```bash
for f in database/migrations/*.sql; do
  docker exec -i agent_platform_postgres \
    psql -U agent_platform -d agent_platform < "$f"
done
```

Ou, se preferir rodar do host com `psql` local, usando a porta publicada:

```bash
export DATABASE_URL="postgres://agent_platform:${AGENT_PLATFORM_DB_PASSWORD}@localhost:5433/agent_platform"
for f in database/migrations/*.sql; do psql "$DATABASE_URL" -f "$f"; done
```

(Opcional) seed inicial do Model Registry:
```bash
psql "$DATABASE_URL" -f database/seeds/0001_llm_models.sql
```

## 3. Conectar o n8n a este banco

No n8n, crie uma **credencial Postgres nova** (não reaproveite a credencial
interna do n8n) apontando para:

- Host: `agent_platform_postgres` (nome do serviço — assim os workflows
  falam com o container pelo DNS interno do Docker, sem passar pela porta
  publicada no host)
- Port: `5432` (a porta *interna* do container, não a `5433` publicada)
- Database: `agent_platform`
- User / Password: os mesmos do `docker-compose.yml`

É essa credencial que os nós Postgres das specs em `/n8n/core/*.md` (CORE-00,
CORE-01) devem usar.
