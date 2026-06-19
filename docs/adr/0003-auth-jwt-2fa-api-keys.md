# ADR 0003 — Autenticazione JWT staff, 2FA TOTP e API key M2M

## Status

Accepted

## Context

L'ecosistema Asso P2B richiede:

- **Staff backoffice** (`assop2b-fe-admin`): login umano con JWT, refresh sessione, RBAC team-based
- **Website pubblico** (`assop2b-website`): consumo futuro di contenuti CMS via chiamate server-side autenticate con API key
- **Integrazioni M2M**: servizi esterni senza identità utente

Il backend `assop2b-be-admin` deve esporre un unico gate di autenticazione con due principal distinti, senza mescolare permessi utente e scope macchina.

## Decision

### JWT staff (umano)

| Token | Durata | Storage |
|-------|--------|---------|
| Access | 15 min | `Authorization: Bearer` (FE: sessionStorage) |
| Refresh | 30 gg | Cookie `httpOnly; Secure; SameSite=Strict; path=/api/auth` — host-only sul dominio API (nessun attributo `Domain`) |
| Login challenge | 3 min | JSON (solo durante step 2FA) |

- Audience `staff`; memberships e permessi **non** nel JWT — caricati da DB su `/api/auth/me`
- Refresh rotation con `familyId`; riuso revoca l'intera famiglia

### 2FA TOTP

- Opzionale (enrollment volontario da profilo)
- Secret TOTP cifrato in DB (`TOTP_ENCRYPTION_KEY`)
- Backup codes monouso (hash argon2)
- Flusso login: credenziali → `202 { requires2fa, loginChallengeToken }` → `POST /api/auth/2fa/verify`

### API key M2M

- Formato: `ap2b_{env}_{prefix}_{secret}`
- In DB: solo `prefix` + `secret_hash`; secret mostrato una volta alla creazione
- Scope propri (es. `cms.read`) — **non** ereditano RBAC utente
- Header: `Authorization: Bearer ap2b_...` (discriminato dal prefisso JWT `eyJ`)

### Website → CMS

- Il sito Nuxt effettua fetch **solo server-side** (`runtimeConfig` privata `cmsApiKey`)
- Nessun CORS verso `DOMAIN_WEBSITE` necessario in v1
- Endpoint smoke `GET /api/cms/status` per validare integrazione prima del modulo contenuti

### Variabili ambiente (be-admin)

`JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`, `JWT_LOGIN_CHALLENGE_SECRET`, `TOTP_ENCRYPTION_KEY`, `COOKIE_SECRET`, `API_KEY_ENV`, `WEBSITE_CMS_API_KEY`.

**Provisioning:** `init-vps.sh` (`ensure_auth_credentials`) genera automaticamente i secret sopra in `{env}/.env` se assenti. `ensure_db_credentials` imposta `DB_SEED=true` se assente. Con seed attivo, `WEBSITE_CMS_API_KEY` viene registrata in `api_keys`.

## Consequences

### Positive

- Separazione netta umano vs macchina
- Allineamento al contratto FE esistente (`/api/auth/login`, `/me`, `/refresh`)
- Website pronto per CMS senza esporre segreti al browser

### Negative / trade-off

- Auth portale clienti (`/api/portale/auth/*`) resta fase successiva
- Modulo CMS (tabelle contenuti, CRUD FE) non incluso in questa ADR
- Test integrazione DB richiedono PostgreSQL (Testcontainers o env dedicato)

## Riferimenti

- [ADR 0002 — Drizzle ORM](0002-drizzle-orm.md)
- [ContrattoApi FE — Auth](https://github.com/Asso-P2B/assop2b-fe-admin/blob/main/docs/ContrattoApi.md#auth)
