#!/usr/bin/env bash

set -uo pipefail

# --- Configurazione ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(pwd)"
COMPOSE_MODEL="${SCRIPT_DIR}/docker-compose-model.yml"
CADDY_DIR="${SCRIPT_DIR}/caddy"

ENV_VARS=(
  "ACME_EMAIL|Email Let's Encrypt (obbligatoria)"
  "DOMAIN_WEBSITE|Dominio sito pubblico"
  "DOMAIN_ADMIN|Dominio frontend admin"
  "DOMAIN_API|Dominio API backend"
)

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

  if [[ ! -f "${CADDY_DIR}/Caddyfile" ]]; then
    error "File non trovato: ${CADDY_DIR}/Caddyfile"
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

# --- Docker Compose ---
setup_compose() {
  local env_name="$1"
  local env_dir="${BASE_DIR}/${env_name}"
  local compose_file="${env_dir}/docker-compose.yml"
  local caddy_dest="${env_dir}/caddy"

  if [[ -f "$compose_file" ]]; then
    warn "[$env_name] docker-compose.yml già presente — sovrascrittura."
  fi

  cp "$COMPOSE_MODEL" "$compose_file"
  info "[$env_name] docker-compose.yml copiato."

  if [[ -d "$caddy_dest" ]]; then
    warn "[$env_name] caddy/ già presente — sovrascrittura."
    rm -rf "$caddy_dest"
  fi
  cp -r "$CADDY_DIR" "$caddy_dest"
  info "[$env_name] caddy/ copiato."

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

  print_summary

  if [[ ${#FAILED_ENVS[@]} -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
