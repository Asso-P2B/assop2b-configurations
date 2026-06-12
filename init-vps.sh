#!/usr/bin/env bash

set -uo pipefail

# --- Configurazione ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(pwd)"
COMPOSE_MODEL="${SCRIPT_DIR}/docker-compose-model.yml"
COMPOSE_SHARED_MODEL="${SCRIPT_DIR}/docker-compose-shared-model.yml"

ENV_VARS=(
  "DOMAIN_WEBSITE|Dominio sito pubblico"
  "DOMAIN_ADMIN|Dominio frontend admin"
  "DOMAIN_API|Dominio API backend"
)

SHARED_ENV_VARS=(
  "ACME_EMAIL|Email Let's Encrypt (obbligatoria)"
)

KNOWN_ENVS=(dev stage prod)

REPOS=(
  "assop2b-website|https://github.com/Asso-P2B/assop2b-website.git"
  "assop2b-be-admin|https://github.com/Asso-P2B/assop2b-be-admin.git"
  "assop2b-fe-admin|https://github.com/Asso-P2B/assop2b-fe-admin.git"
)


# --- Stato ---
GIT_USERNAME=""
GIT_TOKEN=""
GIT_ASKPASS_SCRIPT=""
CREDENTIALS_ACTIVE=false
FAILED_ENVS=()
SUCCESS_ENVS=()
DISCOVERED_ENVS=()

# --- Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# --- Cleanup credenziali one-shot ---
cleanup_credentials() {
  if [[ "$CREDENTIALS_ACTIVE" == true ]]; then
    unset GIT_USERNAME GIT_TOKEN GIT_ASKPASS
    if [[ -n "$GIT_ASKPASS_SCRIPT" && -f "$GIT_ASKPASS_SCRIPT" ]]; then
      if command -v shred >/dev/null 2>&1; then
        shred -u "$GIT_ASKPASS_SCRIPT" 2>/dev/null || rm -f "$GIT_ASKPASS_SCRIPT"
      else
        rm -f "$GIT_ASKPASS_SCRIPT"
      fi
    fi
    GIT_ASKPASS_SCRIPT=""
    CREDENTIALS_ACTIVE=false
    info "Credenziali GitHub eliminate dalla sessione."
  fi
}

trap cleanup_credentials EXIT INT TERM

# --- Prerequisiti ---
check_prerequisites() {
  local missing=()

  for cmd in git docker; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if ! docker compose version >/dev/null 2>&1; then
    missing+=("docker compose (plugin v2)")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    error "Prerequisiti mancanti: ${missing[*]}"
    exit 1
  fi

  if [[ ! -f "$COMPOSE_MODEL" ]]; then
    error "File non trovato: ${COMPOSE_MODEL}"
    exit 1
  fi

  if [[ ! -f "$COMPOSE_SHARED_MODEL" ]]; then
    error "File non trovato: ${COMPOSE_SHARED_MODEL}"
    exit 1
  fi

  success "Prerequisiti verificati."
}

# --- Autenticazione GitHub one-shot ---
setup_github_auth() {
  echo
  info "Autenticazione GitHub one-shot (le credenziali non verranno salvate sulla macchina)."
  echo

  read -r -p "GitHub username: " GIT_USERNAME
  if [[ -z "$GIT_USERNAME" ]]; then
    error "Username obbligatorio."
    exit 1
  fi

  read -r -s -p "GitHub Personal Access Token (PAT, scope repo): " GIT_TOKEN
  echo
  if [[ -z "$GIT_TOKEN" ]]; then
    error "PAT obbligatorio."
    exit 1
  fi

  GIT_ASKPASS_SCRIPT="$(mktemp /tmp/git-askpass.XXXXXX)"
  chmod 700 "$GIT_ASKPASS_SCRIPT"

  cat > "$GIT_ASKPASS_SCRIPT" << 'ASKPASS_EOF'
#!/usr/bin/env bash
prompt="${1:-}"
if [[ "$prompt" == *[Uu]ser* ]]; then
  printf '%s\n' "$GIT_USERNAME"
elif [[ "$prompt" == *[Pp]ass* ]]; then
  printf '%s\n' "$GIT_TOKEN"
fi
exit 0
ASKPASS_EOF

  export GIT_USERNAME GIT_TOKEN
  export GIT_ASKPASS="$GIT_ASKPASS_SCRIPT"
  export GIT_TERMINAL_PROMPT=0
  CREDENTIALS_ACTIVE=true

  success "Autenticazione configurata per la sessione corrente."
}

git_auth() {
  git \
    -c credential.helper= \
    -c 'credential.helper=!f() { exit 1; }; f' \
    -c "core.askPass=${GIT_ASKPASS_SCRIPT}" \
    "$@"
}

# --- Selezione environment ---
branch_for_env() {
  case "$1" in
    dev)   echo "dev" ;;
    stage) echo "stage" ;;
    prod)  echo "main" ;;
    *)     echo "" ;;
  esac
}

parse_environments() {
  local input="$1"
  local -a selected=()
  local token part

  input="${input//,/ }"
  read -r -a tokens <<< "$input"

  for token in "${tokens[@]}"; do
    token="$(echo "$token" | tr '[:upper:]' '[:lower:]' | xargs)"
    [[ -z "$token" ]] && continue

    case "$token" in
      1|dev)   part="dev" ;;
      2|stage) part="stage" ;;
      3|prod)  part="prod" ;;
      4|all|tutti|tutto)
        selected=(dev stage prod)
        break
        ;;
      *)
        warn "Scelta ignorata: '$token'"
        continue
        ;;
    esac

    local already=false
    for s in "${selected[@]}"; do
      [[ "$s" == "$part" ]] && already=true && break
    done
    [[ "$already" == false ]] && selected+=("$part")
  done

  if [[ ${#selected[@]} -eq 0 ]]; then
    return 1
  fi

  SELECTED_ENVS=("${selected[@]}")
  return 0
}

prompt_environments() {
  local choice

  while true; do
    echo
    echo "Quali environment inizializzare?"
    echo "  1) dev"
    echo "  2) stage"
    echo "  3) prod"
    echo "  4) tutti"
    echo
    read -r -p "Scelta (es. 1,2 oppure 4): " choice

    if parse_environments "$choice"; then
      info "Environment selezionati: ${SELECTED_ENVS[*]}"
      return 0
    fi

    warn "Nessuna scelta valida. Riprova."
  done
}

# --- Clone / update repository ---
clone_or_update_repo() {
  local repo_dir="$1"
  local repo_url="$2"
  local branch="$3"
  local env_name="$4"

  if [[ -d "$repo_dir/.git" ]]; then
    warn "[$env_name] Repository già presente: $(basename "$repo_dir") — aggiornamento branch '$branch'..."
    (
      cd "$repo_dir"
      git_auth remote set-url origin "$repo_url"
      git_auth fetch origin "$branch"
      git_auth checkout "$branch"
      git_auth pull origin "$branch"
    )
    success "[$env_name] $(basename "$repo_dir") aggiornato (branch: $branch)."
    return 0
  fi

  if [[ -e "$repo_dir" ]]; then
    error "[$env_name] La cartella '$repo_dir' esiste ma non è un repository git. Rimuovila manualmente e riprova."
    return 1
  fi

  info "[$env_name] Clone $(basename "$repo_dir") (branch: $branch)..."
  if git_auth clone -b "$branch" "$repo_url" "$repo_dir"; then
    git_auth -C "$repo_dir" remote set-url origin "$repo_url"
    success "[$env_name] $(basename "$repo_dir") clonato."
    return 0
  fi

  error "[$env_name] Clone fallito per $(basename "$repo_dir")."
  return 1
}

setup_repositories() {
  local env_name="$1"
  local branch="$2"
  local env_dir="${BASE_DIR}/${env_name}"
  local repo_entry repo_name repo_url repo_dir
  local failed=false

  mkdir -p "$env_dir"

  for repo_entry in "${REPOS[@]}"; do
    repo_name="${repo_entry%%|*}"
    repo_url="${repo_entry#*|}"
    repo_dir="${env_dir}/${repo_name}"

    if ! clone_or_update_repo "$repo_dir" "$repo_url" "$branch" "$env_name"; then
      failed=true
    fi
  done

  [[ "$failed" == true ]] && return 1
  return 0
}

# --- File .env per environment ---
prompt_env_file() {
  local env_name="$1"
  local env_dir="$2"
  local env_file="${env_dir}/.env"
  local overwrite=false
  local confirm
  local entry key label value

  if [[ -f "$env_file" ]]; then
    read -r -p "[$env_name] .env già presente. Sovrascrivere? (s/N): " confirm
    case "$confirm" in
      s|S|si|Si|SI) overwrite=true ;;
      *)
        info "[$env_name] .env esistente conservato."
        return 0
        ;;
    esac
  else
    overwrite=true
  fi

  echo
  info "=== Configurazione .env per: $env_name ==="
  info "Usa domini distinti per ogni environment (es. dev.example.com, stage.example.com)."
  echo

  : > "$env_file"

  for entry in "${ENV_VARS[@]}"; do
    key="${entry%%|*}"
    label="${entry#*|}"

    while true; do
      read -r -p "${label}: " value
      value="$(echo "$value" | xargs)"
      if [[ -n "$value" ]]; then
        printf '%s=%s\n' "$key" "$value" >> "$env_file"
        break
      fi
      warn "Valore obbligatorio. Riprova."
    done
  done

  success "[$env_name] .env creato."
  return 0
}

# --- Utility ---
read_env_var() {
  local env_file="$1"
  local key="$2"
  grep -E "^${key}=" "$env_file" 2>/dev/null | cut -d= -f2- | head -1
}

# --- Stack condiviso (Caddy + futuri servizi) ---
discover_environments() {
  local env
  DISCOVERED_ENVS=()

  for env in "${KNOWN_ENVS[@]}"; do
    if [[ -f "${BASE_DIR}/${env}/.env" ]]; then
      DISCOVERED_ENVS+=("$env")
    fi
  done
}

prompt_shared_env() {
  local env_file="${BASE_DIR}/.env.shared"
  local confirm
  local entry key label value

  if [[ -f "$env_file" ]]; then
    read -r -p ".env.shared già presente. Sovrascrivere? (s/N): " confirm
    case "$confirm" in
      s|S|si|Si|SI) ;;
      *)
        info ".env.shared esistente conservato."
        return 0
        ;;
    esac
  fi

  echo
  info "=== Configurazione .env.shared (stack condiviso) ==="
  echo

  : > "$env_file"

  for entry in "${SHARED_ENV_VARS[@]}"; do
    key="${entry%%|*}"
    label="${entry#*|}"

    while true; do
      read -r -p "${label}: " value
      value="$(echo "$value" | xargs)"
      if [[ -n "$value" ]]; then
        printf '%s=%s\n' "$key" "$value" >> "$env_file"
        break
      fi
      warn "Valore obbligatorio. Riprova."
    done
  done

  success ".env.shared creato."
}

generate_caddyfile() {
  local acme_email="$1"
  local caddyfile="${BASE_DIR}/caddy/Caddyfile"
  local env env_file domain_website domain_admin domain_api

  mkdir -p "${BASE_DIR}/caddy"

  cat > "$caddyfile" << EOF
{
	email ${acme_email}
}
EOF

  for env in "${DISCOVERED_ENVS[@]}"; do
    env_file="${BASE_DIR}/${env}/.env"
    domain_website="$(read_env_var "$env_file" DOMAIN_WEBSITE)"
    domain_admin="$(read_env_var "$env_file" DOMAIN_ADMIN)"
    domain_api="$(read_env_var "$env_file" DOMAIN_API)"

    cat >> "$caddyfile" << EOF

${domain_website} {
	reverse_proxy assop2b-${env}-website:3000
}

${domain_admin} {
	reverse_proxy assop2b-${env}-fe-admin:80
}

${domain_api} {
	reverse_proxy assop2b-${env}-be-admin:8080
}
EOF
  done

  success "caddy/Caddyfile generato."
}

generate_shared_compose() {
  local compose_file="${BASE_DIR}/docker-compose.shared.yml"
  local env line

  {
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" == "__CADDY_NETWORKS__" ]]; then
        for env in "${DISCOVERED_ENVS[@]}"; do
          echo "      - assop2b-${env}"
        done
      elif [[ "$line" == "__EXTERNAL_NETWORKS__" ]]; then
        for env in "${DISCOVERED_ENVS[@]}"; do
          echo "  assop2b-${env}:"
          echo "    external: true"
        done
      else
        echo "$line"
      fi
    done < "$COMPOSE_SHARED_MODEL"
  } > "$compose_file"

  success "docker-compose.shared.yml generato."
}

setup_shared() {
  local acme_email
  local shared_compose="${BASE_DIR}/docker-compose.shared.yml"

  discover_environments

  if [[ ${#DISCOVERED_ENVS[@]} -eq 0 ]]; then
    warn "Nessun environment con .env trovato — stack condiviso non avviato."
    return 1
  fi

  info "Environment rilevati per Caddy: ${DISCOVERED_ENVS[*]}"

  prompt_shared_env

  acme_email="$(read_env_var "${BASE_DIR}/.env.shared" ACME_EMAIL)"
  if [[ -z "$acme_email" ]]; then
    error "ACME_EMAIL mancante in .env.shared."
    return 1
  fi

  generate_caddyfile "$acme_email"
  generate_shared_compose

  info "Avvio stack condiviso..."
  if (cd "$BASE_DIR" && docker compose -f "$shared_compose" up -d); then
    success "Stack condiviso avviato."
    return 0
  fi

  error "docker compose up fallito per lo stack condiviso."
  return 1
}

# --- Docker Compose per environment ---
setup_compose() {
  local env_name="$1"
  local env_dir="${BASE_DIR}/${env_name}"
  local compose_file="${env_dir}/docker-compose.yml"

  if [[ -f "$compose_file" ]]; then
    warn "[$env_name] docker-compose.yml già presente — sovrascrittura."
  fi

  sed "s/__ENV__/${env_name}/g" "$COMPOSE_MODEL" > "$compose_file"
  info "[$env_name] docker-compose.yml generato."

  prompt_env_file "$env_name" "$env_dir"

  info "[$env_name] Avvio container..."
  if (cd "$env_dir" && docker compose up -d); then
    success "[$env_name] Container avviati."
    return 0
  fi

  error "[$env_name] docker compose up fallito (verifica il contenuto di docker-compose.yml)."
  return 1
}

# --- Inizializzazione singolo environment ---
init_environment() {
  local env_name="$1"
  local branch
  local env_ok=true

  branch="$(branch_for_env "$env_name")"

  echo
  info "=== Inizializzazione environment: $env_name (branch: $branch) ==="

  if ! setup_repositories "$env_name" "$branch"; then
    env_ok=false
  fi

  if ! setup_compose "$env_name"; then
    env_ok=false
  fi

  if [[ "$env_ok" == true ]]; then
    SUCCESS_ENVS+=("$env_name")
    success "Environment '$env_name' inizializzato in ${BASE_DIR}/${env_name}/"
  else
    FAILED_ENVS+=("$env_name")
    error "Environment '$env_name' completato con errori."
  fi
}

# --- Riepilogo ---
print_summary() {
  echo
  echo "========================================"
  echo " Riepilogo inizializzazione VPS"
  echo "========================================"
  echo "Directory base: ${BASE_DIR}"
  echo

  if [[ ${#SUCCESS_ENVS[@]} -gt 0 ]]; then
    success "Completati: ${SUCCESS_ENVS[*]}"
    for env in "${SUCCESS_ENVS[@]}"; do
      echo "  - ${BASE_DIR}/${env}/ (branch: $(branch_for_env "$env"))"
    done
  fi

  if [[ ${#FAILED_ENVS[@]} -gt 0 ]]; then
    error "Falliti: ${FAILED_ENVS[*]}"
  fi

  echo
  if [[ -f "${BASE_DIR}/docker-compose.shared.yml" ]]; then
    info "Stack condiviso: ${BASE_DIR}/docker-compose.shared.yml"
  fi

  echo
  info "I repository clonati non manterranno credenziali GitHub dopo la chiusura dello script."
}

# --- Main ---
main() {
  echo
  echo "========================================"
  echo " Asso-P2B — Inizializzazione VPS"
  echo "========================================"

  check_prerequisites
  setup_github_auth
  prompt_environments

  for env in "${SELECTED_ENVS[@]}"; do
    init_environment "$env" || true
  done

  setup_shared || true

  print_summary

  if [[ ${#FAILED_ENVS[@]} -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
