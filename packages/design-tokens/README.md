# @assop2b/design-tokens

Single source of truth per la palette ASSO P2B — brand colors dal logo e token semantici WCAG 2.2 AA.

## Brand anchor (non modificare)

| Token | Hex | Uso |
|-------|-----|-----|
| `--brand-primary` | `#004D77` | Blu istituzionale — primary, heading, CTA, ring |
| `--brand-secondary` | `#5D92AA` | Blu chiaro — accent decorativo, sidebar indicator, chart |
| `--brand-surface` | `#002B42` | Navy profondo — sidebar, login panel |
| `--brand-secondary-text` | `#3D6F86` | Variante scura per testo piccolo su sfondo chiaro |

## Regole d'uso

- **`brand-secondary` su bianco** — contrasto ~3.3:1, insufficiente per testo normale. Usare solo per superfici, icone grandi, indicatori UI (≥ 3:1).
- **`brand-secondary-text`** — usare quando serve il tono brand in copy piccola su sfondo chiaro (≥ 4.5:1).
- **Dark mode primary button** — `--primary-foreground: #0A1520` su `--primary: #5E92AA` per rispettare AA.

## Token semantici

Light e dark mode espongono i token shadcn-compatibili: `background`, `foreground`, `primary`, `secondary`, `muted`, `accent`, `destructive`, `border`, `input`, `ring`, `sidebar-*`, `chart-*`.

Tailwind 4 utilities: `bg-primary`, `text-muted-foreground`, `border-border`, ecc.

## Installazione

### Dev locale (repo sibling)

```json
"@assop2b/design-tokens": "file:../assop2b-configurations/packages/design-tokens"
```

```css
@import "tailwindcss";
@import "@assop2b/design-tokens";
```

### CI / Docker (git dependency)

```json
"@assop2b/design-tokens": "github:AssoP2B/assop2b-configurations#main:packages/design-tokens"
```

Richiede accesso GitHub in build (`GITHUB_TOKEN` o PAT).

## Contrasti verificati (light mode)

| Coppia | Ratio | Soglia |
|--------|-------|--------|
| foreground / background | 16.47:1 | 4.5:1 |
| primary-foreground / primary | 9.02:1 | 4.5:1 |
| muted-foreground / background | 6.14:1 | 4.5:1 |
| destructive / background | 5.49:1 | 4.5:1 |
| brand-secondary-text / background | 5.37:1 | 4.5:1 |
| brand-secondary / background (UI) | 3.33:1 | 3:1 |

## Validazione

```bash
cd packages/design-tokens
node scripts/check-contrast.mjs
```

## Consumer

- `assop2b-website` — `app/assets/css/main.css`
- `assop2b-fe-admin` — `src/style.css` (+ alias `brand`, `brand-accent`, `surface`)
