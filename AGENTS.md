# assop2b-configurations

Configurazione del deploy di AssoP2B su una VPS: stack condiviso e uno stack per ambiente (dev, stage, prod), con `init-vps.sh`.

Solo la parte del progetto. Il metodo (rami, PR, piano, verifiche) sta nelle regole globali del kit.

## Stack e comandi

- Stack: Docker Compose, Caddy, script shell.
- `init-vps.sh` si lancia solo sul server, e lo lancia l'utente.
- Ramo base delle PR: `main`. Il merge non fa partire niente: il repo non ha `.github/workflows/` (ADR 0007).

## Zona critica

Tutto il repo: è il deploy di tutti gli ambienti, produzione compresa.

## Issue, spec e ADR

La riga `- Issue:` la legge uno script del kit: `owner/repo` tra apici inversi, niente altro sulla riga.

- Issue: `Asso-P2B/assop2b-docs`
- Project: https://github.com/orgs/Asso-P2B/projects/1
- Spec: `specs/` in `Asso-P2B/assop2b-docs`
- ADR: `adr/` in `Asso-P2B/assop2b-docs`

## Vincoli

- Repo pubblico: niente requisiti o dati del cliente, niente credenziali (ADR 0004).
