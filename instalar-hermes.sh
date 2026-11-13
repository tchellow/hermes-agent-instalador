#!/usr/bin/env bash
# =============================================================================
# Instalador do Hermes Agent para Ubuntu
#   Docker + Hermes (container isolado) + OpenRouter (DeepSeek) + Telegram
#
# Uso:  ./instalar-hermes.sh [--sem-telegram] [--dashboard] [--nao-iniciar]
#                            [--sem-validar] [-h]
#
# Pode ser executado de novo com segurança: o que já existe é reaproveitado.
# =============================================================================
set -Eeuo pipefail

# ---------- Configuração (pode ser sobrescrita por variáveis de ambiente) ----
HERMES_DIR="${HERMES_DIR:-$HOME/hermes}"
HERMES_REPO="${HERMES_REPO:-https://github.com/NousResearch/hermes-agent.git}"
HERMES_VERSION="${HERMES_VERSION:-}"            # vazio = última versão estável
HERMES_MODEL="${HERMES_MODEL:-deepseek/deepseek-v4.1-flash}"
HERMES_MEM_LIMIT="${HERMES_MEM_LIMIT:-2g}"
HERMES_CPUS="${HERMES_CPUS:-2}"

COM_TELEGRAM=1
COM_DASHBOARD=0
INICIAR=1
VALIDAR=1

# ---------- Saída ------------------------------------------------------------
if [[ -t 1 ]]; then
  C_AZ=$'\e[1;34m'; C_VD=$'\e[1;32m'; C_AM=$'\e[1;33m'; C_VM=$'\e[1;31m'; C_0=$'\e[0m'
else
  C_AZ=; C_VD=; C_AM=; C_VM=; C_0=
fi
etapa() { printf '\n%s==> %s%s\n' "$C_AZ" "$*" "$C_0"; }
ok()    { printf '%s  ✓ %s%s\n' "$C_VD" "$*" "$C_0"; }
aviso() { printf '%s  ! %s%s\n' "$C_AM" "$*" "$C_0" >&2; }
erro()  { printf '%s  ✗ %s%s\n' "$C_VM" "$*" "$C_0" >&2; exit 1; }
trap 'erro "Falhou na linha $LINENO. Corrija o problema e rode o script de novo."' ERR

uso() {
  cat <<'EOF'
Instalador do Hermes Agent (Docker + OpenRouter + Telegram) para Ubuntu.

Uso: ./instalar-hermes.sh [opções]

Opções:
  --sem-telegram   Não configura o bot do Telegram (dá para configurar depois).
  --dashboard      Liga também o painel web em http://localhost:9119 (com login).
  --nao-iniciar    Instala e configura, mas não liga o Hermes no final.
  --sem-validar    Não confere a chave do OpenRouter e o token do Telegram online.
  -h, --help       Mostra esta ajuda.

Variáveis de ambiente opcionais:
  HERMES_DIR        Pasta da instalação          (padrão: ~/hermes)
  HERMES_VERSION    Versão do Hermes, ex. v0.23.1 (padrão: última estável)
  HERMES_MODEL      Modelo no OpenRouter         (padrão: deepseek/deepseek-v4.1-flash)
  HERMES_MEM_LIMIT  Limite de memória            (padrão: 2g)
  HERMES_CPUS       Limite de CPUs               (padrão: 2)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sem-telegram) COM_TELEGRAM=0 ;;
    --dashboard)    COM_DASHBOARD=1 ;;
    --nao-iniciar)  INICIAR=0 ;;
    --sem-validar)  VALIDAR=0 ;;
    -h|--help)      uso; exit 0 ;;
    *) uso; erro "Opção desconhecida: $1" ;;
  esac
  shift
done

# ---------- Verificações iniciais -------------------------------------------
verificar_sistema() {
  etapa "Verificando o sistema"
  [[ $EUID -ne 0 ]] || erro "Rode como seu usuário normal, sem sudo. O script pede a senha quando precisar."
  command -v sudo >/dev/null || erro "O comando sudo não foi encontrado."

  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" != "ubuntu" ]]; then
    aviso "Sistema detectado: ${PRETTY_NAME:-desconhecido}. O script foi feito para Ubuntu 24.04 ou 26.04 LTS."
  else
    ok "${PRETTY_NAME}"
  fi

  case "$(uname -m)" in
    x86_64|aarch64) ok "Arquitetura $(uname -m)" ;;
    *) erro "Arquitetura $(uname -m) não suportada (use 64 bits: x86_64 ou arm64)." ;;
  esac

  local livre
  livre=$(df -BG --output=avail "$HOME" | tail -1 | tr -dc '0-9')
  if (( livre < 15 )); then
    aviso "Só ${livre} GB livres. A instalação precisa de uns 10 GB."
  else
    ok "${livre} GB livres em disco"
  fi

  sudo -v || erro "Não foi possível usar o sudo."
  if ! command -v git >/dev/null || ! command -v curl >/dev/null || ! command -v openssl >/dev/null; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq git curl ca-certificates openssl >/dev/null
  fi
  ok "git, curl e openssl disponíveis"
}

# ---------- Docker ----------------------------------------------------------
DOCKER=(docker)

instalar_docker() {
  etapa "Docker"
  if command -v docker >/dev/null && docker compose version >/dev/null 2>&1 \
     || sudo docker compose version >/dev/null 2>&1; then
    ok "Docker já instalado"
  else
    echo "  Instalando o Docker pelo repositório oficial (docs.docker.com)..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq ca-certificates curl >/dev/null
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    # shellcheck disable=SC1091
    sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
    sudo apt-get update -qq
    sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io \
      docker-buildx-plugin docker-compose-plugin >/dev/null
    ok "Docker instalado"
  fi
  sudo systemctl enable --now docker >/dev/null 2>&1 || true

  if ! id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
    sudo usermod -aG docker "$USER"
    ok "Usuário $USER adicionado ao grupo docker (vale a partir do próximo login)"
  fi

  # Nesta sessão o grupo pode ainda não estar ativo: usa sudo se precisar.
  if docker info >/dev/null 2>&1; then
    DOCKER=(docker)
  else
    DOCKER=(sudo docker)
  fi
  ok "$("${DOCKER[@]}" compose version)"
}

dc() { (cd "$HERMES_DIR" && "${DOCKER[@]}" compose "$@"); }

# ---------- Código do Hermes -------------------------------------------------
baixar_hermes() {
  etapa "Baixando o Hermes Agent"
  if [[ -z "$HERMES_VERSION" ]]; then
    HERMES_VERSION=$(git ls-remote --tags --refs "$HERMES_REPO" \
      | awk -F/ '{print $3}' | grep -E '^v[0-9]{1,3}\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
    [[ -n "$HERMES_VERSION" ]] || erro "Não consegui descobrir a última versão estável do Hermes."
  fi
  ok "Versão escolhida: $HERMES_VERSION"

  mkdir -p "$HERMES_DIR/data"
  if [[ -d "$HERMES_DIR/src/.git" ]]; then
    git -C "$HERMES_DIR/src" fetch --tags --quiet
  else
    git clone --quiet "$HERMES_REPO" "$HERMES_DIR/src"
  fi
  git -C "$HERMES_DIR/src" -c advice.detachedHead=false checkout --quiet "$HERMES_VERSION"
  ok "Código em $HERMES_DIR/src"
}

escrever_compose() {
  cat > "$HERMES_DIR/docker-compose.yml" <<'EOF'
# Hermes Agent — gerado por instalar-hermes.sh
# Container isolado: rede própria, sem acesso ao Docker do computador,
# com limite de memória e CPU. Dados em ./data (config, memória, chaves).
name: hermes

services:
  gateway:
    build: ./src
    image: ${HERMES_IMAGE:-hermes-agent}:${HERMES_VERSION}
    container_name: hermes
    restart: unless-stopped
    volumes:
      - ./data:/opt/data
    environment:
      - HERMES_UID=${HERMES_UID:-1000}
      - HERMES_GID=${HERMES_GID:-1000}
    command: ["gateway", "run"]
    mem_limit: ${HERMES_MEM_LIMIT:-2g}
    cpus: ${HERMES_CPUS:-2}
    networks: [hermes]

  # Painel web (opcional): docker compose --profile dashboard up -d
  dashboard:
    image: ${HERMES_IMAGE:-hermes-agent}:${HERMES_VERSION}
    container_name: hermes-dashboard
    restart: unless-stopped
    profiles: [dashboard]
    depends_on: [gateway]
    volumes:
      - ./data:/opt/data
    environment:
      - HERMES_UID=${HERMES_UID:-1000}
      - HERMES_GID=${HERMES_GID:-1000}
      - HERMES_DASHBOARD_BASIC_AUTH_USERNAME=${DASHBOARD_USER}
      - HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=${DASHBOARD_PASSWORD}
      - HERMES_DASHBOARD_BASIC_AUTH_SECRET=${DASHBOARD_SECRET}
    command: ["dashboard", "--host", "0.0.0.0", "--port", "9119", "--no-open"]
    ports:
      - "${DASHBOARD_BIND:-127.0.0.1}:9119:9119"
    mem_limit: 1g
    networks: [hermes]

networks:
  hermes:
EOF
}

escrever_env() {
  local env="$HERMES_DIR/.env"
  if [[ -f "$env" ]]; then
    sed -i "s/^HERMES_VERSION=.*/HERMES_VERSION=$HERMES_VERSION/" "$env"
    ok ".env existente mantido (versão atualizada para $HERMES_VERSION)"
  else
    umask 077
    cat > "$env" <<EOF
HERMES_VERSION=$HERMES_VERSION
HERMES_UID=$(id -u)
HERMES_GID=$(id -g)
HERMES_MEM_LIMIT=$HERMES_MEM_LIMIT
HERMES_CPUS=$HERMES_CPUS
DASHBOARD_BIND=127.0.0.1
DASHBOARD_USER=admin
DASHBOARD_PASSWORD=$(openssl rand -base64 18 | tr -d '/+=')
DASHBOARD_SECRET=$(openssl rand -hex 32)
EOF
    umask 022
    ok ".env criado (senha do painel gerada aleatoriamente)"
  fi
  chmod 600 "$env"
}

montar_imagem() {
  etapa "Montando a imagem do Hermes (10 a 20 minutos na primeira vez)"
  escrever_compose
  escrever_env
  dc build gateway
  ok "Imagem pronta"
}

# ---------- Segredos ---------------------------------------------------------
# Os segredos são lidos sem eco e passados ao curl por stdin (-K -),
# para não aparecerem na tela, no histórico do shell nem na lista de processos.
OR_KEY=""; TG_TOKEN=""; TG_ID=""

ja_configurado() { grep -qE "^$1=.+" "$HERMES_DIR/data/.env" 2>/dev/null; }

perguntar_sn() { # $1 = pergunta; padrão = não
  local r; read -rp "  $1 [s/N] " r; [[ "$r" =~ ^[sS] ]]
}

validar_openrouter() {
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' -K - <<EOF
url = "https://openrouter.ai/api/v1/key"
header = "Authorization: Bearer $1"
EOF
  ) || true
  [[ "$code" == "200" ]]
}

ler_openrouter() {
  etapa "OpenRouter (modelo de IA)"
  if ja_configurado OPENROUTER_API_KEY && ! perguntar_sn "Já existe uma chave do OpenRouter. Trocar?"; then
    ok "Chave existente mantida"
  else
    echo "  Crie a chave em https://openrouter.ai/keys (defina um limite de crédito nela)."
    local _
    for _ in 1 2 3; do
      read -rsp "  Cole a chave do OpenRouter (não aparece na tela) e aperte Enter: " OR_KEY; echo
      if [[ ! "$OR_KEY" =~ ^sk-or- ]]; then
        aviso "A chave deve começar com sk-or-"; OR_KEY=""; continue
      fi
      if (( VALIDAR )) && ! validar_openrouter "$OR_KEY"; then
        aviso "O OpenRouter recusou essa chave. Confira e tente de novo."; OR_KEY=""; continue
      fi
      break
    done
    [[ -n "$OR_KEY" ]] || erro "Sem uma chave válida do OpenRouter não dá para continuar."
    ok "Chave do OpenRouter aceita"
  fi

  local m
  read -rp "  Modelo [${HERMES_MODEL}]: " m
  HERMES_MODEL="${m:-$HERMES_MODEL}"
  if (( VALIDAR )); then
    if curl -fsS https://openrouter.ai/api/v1/models | grep -qF "\"$HERMES_MODEL\""; then
      ok "Modelo $HERMES_MODEL encontrado no OpenRouter"
    else
      aviso "Não encontrei $HERMES_MODEL no catálogo do OpenRouter. Confira o nome em https://openrouter.ai/models"
    fi
  fi
}

ler_telegram() {
  (( COM_TELEGRAM )) || return 0
  etapa "Telegram"
  if ja_configurado TELEGRAM_BOT_TOKEN && ! perguntar_sn "Já existe um bot do Telegram configurado. Trocar?"; then
    ok "Bot existente mantido"; return 0
  fi
  cat <<'EOF'
  1. No Telegram, fale com @BotFather, mande /newbot e copie o token.
     Use um bot NOVO: um bot já usado por outro programa entra em conflito.
  2. Fale com @userinfobot para descobrir o seu ID numérico.
EOF
  local _ resp
  for _ in 1 2 3; do
    read -rsp "  Cole o token do bot (não aparece na tela) e aperte Enter: " TG_TOKEN; echo
    if [[ ! "$TG_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]{30,}$ ]]; then
      aviso "Formato inválido. O token é parecido com 123456789:ABCdef..."; TG_TOKEN=""; continue
    fi
    if (( VALIDAR )); then
      resp=$(curl -s -K - <<<"url = \"https://api.telegram.org/bot${TG_TOKEN}/getMe\"") || true
      if [[ "$resp" != *'"ok":true'* ]]; then
        aviso "O Telegram recusou esse token. Confira e tente de novo."; TG_TOKEN=""; continue
      fi
      ok "Bot encontrado: @$(grep -o '"username":"[^"]*"' <<<"$resp" | cut -d'"' -f4)"
    fi
    break
  done
  [[ -n "$TG_TOKEN" ]] || erro "Sem um token válido do Telegram. Rode de novo ou use --sem-telegram."

  for _ in 1 2 3; do
    read -rp "  Seu ID do Telegram (só números): " TG_ID
    [[ "$TG_ID" =~ ^[0-9]{5,}$ ]] && break
    aviso "O ID tem só números (veja no @userinfobot)."; TG_ID=""
  done
  [[ -n "$TG_ID" ]] || erro "ID do Telegram inválido."
  ok "Só o ID $TG_ID poderá falar com o agente"
}

# ---------- Configuração dentro do Hermes -----------------------------------
cfg() { # $1 = chave, $2 = valor
  local out
  out=$(dc run --rm -T gateway config set "$1" "$2" 2>&1) || true
  grep -q "Set $1" <<<"$out" || { tail -5 <<<"$out" >&2; erro "Falha ao gravar $1."; }
}

configurar_hermes() {
  etapa "Configurando o Hermes"
  if [[ -n "$OR_KEY" ]]; then cfg OPENROUTER_API_KEY "$OR_KEY"; ok "Chave do OpenRouter gravada"; fi
  cfg model.provider openrouter
  cfg model.default "$HERMES_MODEL"
  ok "Modelo: $HERMES_MODEL (via OpenRouter)"
  if [[ -n "$TG_TOKEN" ]]; then
    cfg TELEGRAM_BOT_TOKEN "$TG_TOKEN"
    cfg TELEGRAM_ALLOWED_USERS "$TG_ID"
    cfg TELEGRAM_HOME_CHANNEL "$TG_ID"
    ok "Telegram configurado"
  fi
  OR_KEY=""; TG_TOKEN=""
  chmod 600 "$HERMES_DIR/data/.env" 2>/dev/null || true
}

# ---------- Iniciar ----------------------------------------------------------
iniciar() {
  (( INICIAR )) || { etapa "Instalação concluída (Hermes não iniciado, --nao-iniciar)"; return 0; }
  etapa "Ligando o Hermes"
  local log="$HERMES_DIR/data/logs/gateway.log" n0=0 prof=()
  local ja_rodando=0
  [[ -f "$log" ]] && n0=$(wc -l < "$log")
  if (( COM_DASHBOARD )); then prof=(--profile dashboard); fi
  if dc ps --status running --services 2>/dev/null | grep -qx gateway; then ja_rodando=1; fi
  dc "${prof[@]}" up -d
  if (( ja_rodando )); then
    dc restart gateway >/dev/null   # já estava no ar: recarrega a configuração nova
  fi

  echo "  Aguardando o gateway (até 2 minutos)..."
  local _ novo=""
  for _ in $(seq 1 60); do
    sleep 2
    [[ -f "$log" ]] || continue
    novo=$(tail -n +"$((n0 + 1))" "$log")
    grep -q "Gateway running" <<<"$novo" && break
  done
  if grep -q "Gateway running" <<<"$novo"; then
    ok "Gateway no ar"
  else
    aviso "O gateway não confirmou a partida. Veja: tail -50 $log"
  fi
  if grep -qE "^TELEGRAM_BOT_TOKEN=.+" "$HERMES_DIR/data/.env" 2>/dev/null; then
    if grep -q "telegram connected" <<<"$novo"; then
      ok "Telegram conectado: mande \"oi\" para o seu bot"
    else
      aviso "O Telegram ainda não conectou. Veja: grep -i telegram $log | tail"
    fi
  fi
}

resumo() {
  cat <<EOF

${C_VD}Pronto!${C_0}

  Pasta:           $HERMES_DIR
  Versão:          $HERMES_VERSION
  Modelo:          $HERMES_MODEL (OpenRouter)
  Log do agente:   $HERMES_DIR/data/logs/gateway.log

  Comandos úteis (dentro de $HERMES_DIR):
    docker compose ps                         # ver se está no ar
    docker compose restart gateway            # reiniciar
    docker compose exec -it gateway hermes    # conversar pelo terminal
    tail -f data/logs/gateway.log             # acompanhar o log
EOF
  if (( COM_DASHBOARD )); then
    cat <<EOF
    Painel web: http://localhost:9119  (usuário admin;
                senha: grep DASHBOARD_PASSWORD $HERMES_DIR/.env)
EOF
  fi
  if [[ "${DOCKER[*]}" == "sudo docker" ]]; then
    printf '\n%s  Saia da sessão e entre de novo para usar "docker" sem sudo.%s\n' "$C_AM" "$C_0"
  fi
  cat <<EOF

  Segurança: nunca compartilhe $HERMES_DIR/.env nem a pasta data/ (têm suas chaves).
EOF
}

main() {
  verificar_sistema
  instalar_docker
  baixar_hermes
  montar_imagem
  ler_openrouter
  ler_telegram
  configurar_hermes
  iniciar
  resumo
}

# Só executa quando chamado diretamente (permite "source" em testes).
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main; fi
