#!/usr/bin/env bash
# create-user-wsl.sh — Cria e configura usuário WSL DevOps
# Pode ser chamado por qualquer usuário — eleva para root automaticamente
set -euo pipefail

# ── Auto-elevação ──────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    exec sudo bash "$0" "$@"
fi

# ── Variáveis ──────────────────────────────────────────
DEV_GROUP="dev"
SUDOERS_DEV="/etc/sudoers.d/dev-nopasswd"
SUDOERS_ENVCTL="/etc/sudoers.d/envctl"
P10K_TEMPLATE="/opt/zsh-global/p10k.template"
ENVCTL_DIR="/opt/envctl"

# ── Header ─────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════╗"
echo "║   CRIAR USUÁRIO WSL — EnvCtl         ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Detectar Docker ────────────────────────────────────
DOCKER_INSTALLED=false
if command -v docker &>/dev/null; then
    echo "  ✓ Docker: $(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')"
    DOCKER_INSTALLED=true
else
    echo "  ✗ Docker não detectado"
fi
echo ""

# ── Nome do usuário ────────────────────────────────────
read -rp "  Nome do usuário: " USER_NAME
USER_NAME="${USER_NAME// /}"

if [[ -z "$USER_NAME" ]]; then
    echo "  Nome inválido."
    exit 1
fi

if id "$USER_NAME" &>/dev/null; then
    echo ""
    echo "  ⚠ Usuário '$USER_NAME' já existe."
    read -rp "  Reconfigurar ambiente zsh? (s/n): " RECONFIG
    if [[ "$RECONFIG" != "s" ]]; then
        exit 0
    fi
    SKIP_CREATE=true
else
    SKIP_CREATE=false
fi

USER_HOME="/home/$USER_NAME"

# ── Grupo dev ──────────────────────────────────────────
if ! getent group "$DEV_GROUP" &>/dev/null; then
    groupadd "$DEV_GROUP"
    echo "  ✓ Grupo '$DEV_GROUP' criado"
fi

# ── Criar usuário ──────────────────────────────────────
if [ "$SKIP_CREATE" = false ]; then
    echo ""
    useradd -m -s /usr/bin/zsh -G sudo,"$DEV_GROUP" "$USER_NAME"
    echo "  ✓ Usuário criado"
    echo ""
    echo "  Define a senha para $USER_NAME:"
    passwd "$USER_NAME"
fi

# ── Grupos ─────────────────────────────────────────────
usermod -aG sudo "$USER_NAME"
usermod -aG "$DEV_GROUP" "$USER_NAME"
[ "$DOCKER_INSTALLED" = true ] && getent group docker &>/dev/null && usermod -aG docker "$USER_NAME"
echo "  ✓ Grupos configurados"

# ── Sudoers dev ────────────────────────────────────────
if [ ! -f "$SUDOERS_DEV" ]; then
    echo "%$DEV_GROUP ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_DEV"
    chmod 440 "$SUDOERS_DEV"
    echo "  ✓ Sudoers dev configurado"
fi

# ── Permissões home ────────────────────────────────────
chown "$USER_NAME:$USER_NAME" "$USER_HOME"
chmod 750 "$USER_HOME"

# ── Pacotes base ───────────────────────────────────────
echo ""
echo "  Instalando pacotes base..."
apt-get update -qq
apt-get install -y -qq zsh git curl fzf ca-certificates gnupg lsb-release apt-transport-https
echo "  ✓ Pacotes instalados"

# ── kubectl ────────────────────────────────────────────
if ! command -v kubectl &>/dev/null; then
    echo "  Instalando kubectl..."
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key \
        | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' \
        > /etc/apt/sources.list.d/kubernetes.list
    apt-get update -qq 2>/dev/null && apt-get install -y -qq kubectl 2>/dev/null 1>/dev/null
    echo "  ✓ kubectl instalado"
fi

# ── Helm ───────────────────────────────────────────────
if ! command -v helm &>/dev/null; then
    echo "  Instalando Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash &>/dev/null 2>/dev/null
    echo "  ✓ Helm instalado"
fi

# ── Oh My Zsh ──────────────────────────────────────────
if [ ! -d "$USER_HOME/.oh-my-zsh" ]; then
    echo "  Instalando Oh My Zsh..."
    sudo -u "$USER_NAME" git clone -q https://github.com/ohmyzsh/ohmyzsh.git "$USER_HOME/.oh-my-zsh" 2>/dev/null 1>/dev/null
    echo "  ✓ Oh My Zsh instalado"
fi

# ── Powerlevel10k ──────────────────────────────────────
P10K_DIR="$USER_HOME/.oh-my-zsh/custom/themes/powerlevel10k"
if [ ! -d "$P10K_DIR" ]; then
    echo "  Instalando Powerlevel10k..."
    sudo -u "$USER_NAME" git clone -q --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR" 2>/dev/null 1>/dev/null
    echo "  ✓ Powerlevel10k instalado"
fi

# ── Plugins ────────────────────────────────────────────
PLUGINS_DIR="$USER_HOME/.oh-my-zsh/custom/plugins"
for PLUGIN in zsh-autosuggestions zsh-syntax-highlighting; do
    if [ ! -d "$PLUGINS_DIR/$PLUGIN" ]; then
        sudo -u "$USER_NAME" git clone -q "https://github.com/zsh-users/$PLUGIN" "$PLUGINS_DIR/$PLUGIN" 2>/dev/null 1>/dev/null
    fi
done
echo "  ✓ Plugins instalados"

# ── .zshrc padrão ──────────────────────────────────────
cat > "$USER_HOME/.zshrc" <<'ZSHEOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git docker kubectl helm zsh-autosuggestions zsh-syntax-highlighting fzf)
source $ZSH/oh-my-zsh.sh
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias dc='docker compose'
alias dps='docker ps'
alias ll='ls -lah'
alias update='sudo apt update && sudo apt upgrade -y'
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
ZSHEOF
echo "  ✓ .zshrc configurado"

# ── p10k template ──────────────────────────────────────
if [ -f "$P10K_TEMPLATE" ] && [ ! -f "$USER_HOME/.p10k.zsh" ]; then
    cp "$P10K_TEMPLATE" "$USER_HOME/.p10k.zsh"
    echo "  ✓ Powerlevel10k template aplicado"
fi

# ── Permissões finais ──────────────────────────────────
chown -R "$USER_NAME:$USER_NAME" "$USER_HOME"
chmod -R go-w "$USER_HOME/.oh-my-zsh" 2>/dev/null || true

# ── Atualiza sudoers EnvCtl ────────────────────────────
if [ -f "$SUDOERS_ENVCTL" ]; then
    ALL_USERS=$(getent passwd \
        | awk -F: '$6 ~ /^\/home\// && $7 ~ /(bash|zsh|sh)$/ {print $1}' \
        | grep -v "^devops$" | sort | tr '\n' ',' | sed 's/,$//')
    if [ -n "$ALL_USERS" ]; then
        echo "devops ALL=($ALL_USERS) NOPASSWD: /usr/bin/zsh, /bin/zsh" > "$SUDOERS_ENVCTL"
        chmod 440 "$SUDOERS_ENVCTL"
        echo "  ✓ Sudoers EnvCtl atualizado"
    fi
fi

# ── Cria profile EnvCtl ────────────────────────────────
if [ -d "$ENVCTL_DIR/profiles" ]; then
    PROFILE="$ENVCTL_DIR/profiles/$USER_NAME.yaml"
    if [ ! -f "$PROFILE" ]; then
        cat > "$PROFILE" <<YAML
name: $USER_NAME
description: "SEM_DESCRICAO"
category: generic
wsl_user: $USER_NAME
color: gray
kubeconfig: ""
namespace: ""
env: {}
aliases:
  ll: ls -lah
integrations:
  orchestrator: false
  oracle: false
  openshift: false
check: []
YAML
        echo "  ✓ Profile EnvCtl criado"
    fi
fi

# ── Resumo ─────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════╗"
echo "║  ✅ Usuário $USER_NAME configurado"
printf  "║     Grupos: sudo, %s%s\n" "$DEV_GROUP" "$([ "$DOCKER_INSTALLED" = true ] && echo ", docker" || echo "")"
echo "║     Shell:  /usr/bin/zsh"
echo "╚══════════════════════════════════════╝"
echo ""
echo "  Para entrar: su - $USER_NAME"
echo "  Ou via EnvCtl: envctl"
echo ""
