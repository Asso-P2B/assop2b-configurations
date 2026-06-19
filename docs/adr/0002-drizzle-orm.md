# ADR 0002 — Drizzle ORM per persistenza applicativa (assop2b-be-admin)

## Status

Accepted

## Context

[ADR 0001](0001-confini-stack-condiviso-vs-environment.md) definisce l'infrastruttura PostgreSQL condivisa: un container `postgres` per VPS, database e utenti separati per environment (`assop2b_{env}`), `DATABASE_URL` provisionata da `init-vps.sh` in `{env}/.env`.

La persistenza applicativa del CRM è responsabilità del repository `assop2b-be-admin` (Fastify 5 + TypeScript), che consuma quel database senza gestire l'engine PostgreSQL.

### Ripartizione responsabilità

| Layer | Repository | Responsabilità |
|-------|------------|----------------|
| Infrastruttura DB | `assop2b-configurations` | Engine PostgreSQL, utenti/DB per env, rete Docker, variabile `DATABASE_URL` |
| Accesso dati | `assop2b-be-admin` | Schema applicativo, migrazioni, query, RBAC enforcement lato server |

Il dominio CRM prevede:

- RBAC dinamico con relazioni molti-a-molti (permessi, ruoli, membership team)
- Filtri per scope operativo (`X-Team-Id`)
- Modelli ricchi (contatti con anagrafica, consensi GDPR, provenienza)
- Migrazioni schema versionate nel repository BE

Alternative valutate: Prisma (DX CRUD, meno controllo su query complesse), TypeORM/Sequelize (meno idiomatici in stack Fastify moderno), SQL raw (troppo boilerplate).

## Decision

Adottiamo **Drizzle ORM** in `assop2b-be-admin` con:

| Componente | Percorso in `assop2b-be-admin` |
|------------|-------------------------------|
| Schema TypeScript | `src/db/schema/` |
| Migrazioni SQL (`drizzle-kit`) | `drizzle/migrations/` |
| Pool `pg` + plugin Fastify | `src/plugins/db.ts` (`fastify.db`) |
| Migrazioni all'avvio container | `DB_MIGRATE_ON_START=true` (default nel `Dockerfile`) |

Le migrazioni restano **codice nel repo BE**, non in `assop2b-configurations`. Lo stack configurations fornisce solo il database vuoto per environment; lo schema CRM viene applicato dal container `be-admin` all'avvio o manualmente via `pnpm db:migrate`.

## Consequences

### Positive

- Type-safety end-to-end senza runtime pesante
- Query relazionali esplicite per RBAC e scope team
- Allineamento naturale con Fastify e Vitest
- PostgreSQL-first (JSONB, enum, constraint)
- Catalogo ADR centralizzato in `assop2b-configurations` per decisioni cross-repo

### Negative / trade-off

- Meno scaffolding automatico rispetto a Prisma — serve un layer repository esplicito in `assop2b-be-admin`
- `drizzle-zod` non incluso in v1 (da valutare con le prime route validate)
- `assop2b-configurations` non gestisce lo schema CRM — solo l'infrastruttura Postgres su cui Drizzle opera

## Follow-up

- Implementare schema applicativo in `assop2b-be-admin` allineato al [ContrattoApi](https://github.com/Asso-P2B/assop2b-fe-admin/blob/main/docs/ContrattoApi.md) (sedi → RBAC → contatti → accessi portale)
- Test integrazione DB (Testcontainers o Postgres dedicato) quando esisterà schema applicativo

## Riferimenti

- [ADR 0001 — Confini stack condiviso vs environment](0001-confini-stack-condiviso-vs-environment.md)
- [README — PostgreSQL](../../README.md#postgresql)
- [`assop2b-be-admin` — Database (Drizzle)](https://github.com/Asso-P2B/assop2b-be-admin#database-drizzle-orm)
