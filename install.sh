#!/usr/bin/env bash
# =============================================================================
# install.sh — EnvCtl installer
# Autor:   Diego Regis M. F. dos Santos
# Email:   diego-f-santos@openlabs.com.br
# Time:    OpenLabs - DevOps | Infra
# Versão:  2.0.0
#
# Uso:
#   bash install.sh                          # detecta OneDrive automaticamente
#   bash install.sh --onedrive /mnt/c/...   # path explícito do OneDrive
#   bash install.sh --manager operador       # usuário manager (padrão: operador)
# =============================================================================
set -e

# ── Cores ──────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

ok()   { echo -e "  ${GREEN}✓${RESET} $*"; }
info() { echo -e "  ${CYAN}→${RESET} $*"; }
warn() { echo -e "  ${YELLOW}⚠${RESET} $*"; }
err()  { echo -e "  ${RED}✗${RESET} $*"; exit 1; }
header() { echo -e "\n${BOLD}$*${RESET}"; }

# ── Argumentos ─────────────────────────────────────────
MANAGER_USER="operador"
ONEDRIVE_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --onedrive) ONEDRIVE_PATH="$2"; shift 2 ;;
        --manager)  MANAGER_USER="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# ── Banner ─────────────────────────────────────────────
echo ""
echo -e "${BOLD}  ⚡ EnvCtl — Installer v2.0${RESET}"
echo -e "  ${CYAN}DevOps Environment Control${RESET}"
echo ""

# ── Detecta OneDrive ───────────────────────────────────
header "📂 Detectando OneDrive..."

if [ -z "$ONEDRIVE_PATH" ]; then
    WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' || echo "")

    if [ -n "$WIN_USER" ]; then
        for candidate in \
            "/mnt/c/Users/$WIN_USER/OneDrive - OPEN LABS S.A" \
            "/mnt/c/Users/$WIN_USER/OneDrive - OpenLabs" \
            "/mnt/c/Users/$WIN_USER/OneDrive" \
            "/mnt/c/Users/322224/OneDrive - OPEN LABS S.A"
        do
            if [ -d "$candidate" ]; then
                ONEDRIVE_PATH="$candidate"
                break
            fi
        done
    fi

    # fallback: busca qualquer OneDrive no profile
    if [ -z "$ONEDRIVE_PATH" ] && [ -n "$WIN_USER" ]; then
        ONEDRIVE_PATH=$(find "/mnt/c/Users/$WIN_USER" -maxdepth 1 -name "OneDrive*" -type d 2>/dev/null | head -1)
    fi
fi

[ -z "$ONEDRIVE_PATH" ] && err "OneDrive não encontrado. Use: --onedrive /mnt/c/Users/.../OneDrive"
[ ! -d "$ONEDRIVE_PATH" ] && err "Diretório não existe: $ONEDRIVE_PATH"

ok "OneDrive: $ONEDRIVE_PATH"

# ── Paths derivados ────────────────────────────────────
ENVCTL_ONEDRIVE="$ONEDRIVE_PATH/wsl/wsl-config/scripts/envctl"
INSTALL_DIR="/opt/envctl"
BIN_LINK="/usr/local/bin/envctl"
PROFILES_ONEDRIVE="$ENVCTL_ONEDRIVE/profiles"

[ ! -d "$ENVCTL_ONEDRIVE" ] && err "envctl não encontrado em: $ENVCTL_ONEDRIVE\nRode primeiro: git clone git@github.com:drmsantos/envctl.git"

ok "Fonte: $ENVCTL_ONEDRIVE"

# ── Cria symlink /opt/envctl → OneDrive ───────────────
header "🔗 Configurando /opt/envctl..."

if [ -L "$INSTALL_DIR" ]; then
    CURRENT=$(readlink "$INSTALL_DIR")
    if [ "$CURRENT" = "$ENVCTL_ONEDRIVE" ]; then
        ok "Symlink já existe e está correto"
    else
        warn "Symlink aponta para: $CURRENT"
        info "Atualizando para: $ENVCTL_ONEDRIVE"
        sudo rm -f "$INSTALL_DIR"
        sudo ln -s "$ENVCTL_ONEDRIVE" "$INSTALL_DIR"
        ok "Symlink atualizado"
    fi
elif [ -d "$INSTALL_DIR" ]; then
    warn "/opt/envctl existe como diretório (instalação antiga)"
    info "Fazendo backup → /opt/envctl.bak"
    sudo mv "$INSTALL_DIR" "/opt/envctl.bak"
    sudo ln -s "$ENVCTL_ONEDRIVE" "$INSTALL_DIR"
    ok "Backup criado e symlink configurado"
else
    sudo ln -s "$ENVCTL_ONEDRIVE" "$INSTALL_DIR"
    ok "Symlink criado: $INSTALL_DIR → $ENVCTL_ONEDRIVE"
fi

# ── Permissões no OneDrive (NTFS — sem chmod) ─────────
sudo chmod +x "$ENVCTL_ONEDRIVE/envctl.py" 2>/dev/null || true

# ── Symlink global /usr/local/bin/envctl ──────────────
header "🔗 Configurando comando global..."

sudo rm -f "$BIN_LINK"
sudo ln -s "$INSTALL_DIR/envctl.py" "$BIN_LINK"
ok "Comando disponível: envctl"

# ── Dependências Python ───────────────────────────────
header "📦 Instalando dependências Python..."

pip install -r "$INSTALL_DIR/requirements.txt" \
    --quiet --break-system-packages 2>/dev/null \
    || pip install -r "$INSTALL_DIR/requirements.txt" --quiet

ok "rich, pyyaml instalados"

# ── Diretório de dados ────────────────────────────────
header "📁 Configurando diretório de dados..."

DATA_DIR="$HOME/.envctl"
mkdir -p "$DATA_DIR/logs"
ok "Dados em: $DATA_DIR"

# ── Detecta usuários WSL ──────────────────────────────
header "👥 Detectando usuários WSL..."

WSL_USERS=$(getent passwd \
    | awk -F: '$6 ~ /^\/home\// && $7 ~ /(bash|zsh|sh)$/ {print $1}' \
    | grep -v "^$MANAGER_USER$" \
    | sort)

if [ -z "$WSL_USERS" ]; then
    warn "Nenhum usuário encontrado em /home/"
else
    ok "Encontrados: $(echo $WSL_USERS | tr '\n' ' ')"
fi

# ── Configura sudoers ─────────────────────────────────
header "🔐 Configurando sudoers..."

SUDOERS_FILE="/etc/sudoers.d/envctl"
USERS_LIST=$(echo "$WSL_USERS" | tr '\n' ',' | sed 's/,$//')

if [ -n "$USERS_LIST" ]; then
    echo "$MANAGER_USER ALL=($USERS_LIST) NOPASSWD: /usr/bin/zsh, /bin/zsh, /usr/bin/sudo" \
        | sudo tee "$SUDOERS_FILE" > /dev/null
    sudo chmod 440 "$SUDOERS_FILE"
    ok "Sudoers: $MANAGER_USER pode entrar como: $USERS_LIST"
else
    warn "Nenhum usuário para configurar no sudoers"
fi

# ── Gera/atualiza profiles YAML ───────────────────────
header "📋 Verificando profiles..."

# Garante que a pasta de profiles existe no OneDrive
mkdir -p "$PROFILES_ONEDRIVE" 2>/dev/null || true

for USER in $WSL_USERS; do
    PROFILE_FILE="$PROFILES_ONEDRIVE/$USER.yaml"

    # Coleta kubeconfigs disponíveis
    KUBE_CANDIDATES=()
    for f in /home/$USER/.kube/config /home/$USER/.kube/config-*; do
        sudo test -f "$f" 2>/dev/null && KUBE_CANDIDATES+=("$f")
    done

    KUBE_FILE=""
    NAMESPACE=""
    CLUSTER=""

    if [ ${#KUBE_CANDIDATES[@]} -eq 0 ]; then
        info "$USER → sem kubeconfig"
    elif [ ${#KUBE_CANDIDATES[@]} -eq 1 ]; then
        KUBE_FILE="${KUBE_CANDIDATES[0]}"
        info "$USER → kubeconfig: $KUBE_FILE"
    else
        echo ""
        info "$USER → múltiplos kubeconfigs:"
        for i in "${!KUBE_CANDIDATES[@]}"; do
            CNAME=$(sudo grep -m1 "^- name:" "${KUBE_CANDIDATES[$i]}" 2>/dev/null | awk '{print $3}' || echo "?")
            echo "      [$i] ${KUBE_CANDIDATES[$i]}  (cluster: $CNAME)"
        done
        read -p "      Qual usar? [0-$((${#KUBE_CANDIDATES[@]}-1))] (Enter = pular): " KUBE_IDX
        if [[ "$KUBE_IDX" =~ ^[0-9]+$ ]] && [ "$KUBE_IDX" -lt "${#KUBE_CANDIDATES[@]}" ]; then
            KUBE_FILE="${KUBE_CANDIDATES[$KUBE_IDX]}"
        fi
    fi

    # Extrai namespace/cluster do kubeconfig
    if [ -n "$KUBE_FILE" ]; then
        NAMESPACE=$(sudo python3 -c "
import yaml, sys
try:
    data = yaml.safe_load(open('$KUBE_FILE').read())
    ctx = data.get('current-context','')
    for c in data.get('contexts',[]):
        if c['name'] == ctx:
            print(c.get('context',{}).get('namespace','') or '')
            sys.exit()
except: pass
print('')
" 2>/dev/null || echo "")

        CLUSTER=$(sudo python3 -c "
import yaml, sys
try:
    data = yaml.safe_load(open('$KUBE_FILE').read())
    ctx = data.get('current-context','')
    for c in data.get('contexts',[]):
        if c['name'] == ctx:
            print(c.get('context',{}).get('cluster','') or '')
            sys.exit()
except: pass
print('')
" 2>/dev/null || echo "")

        if [ -z "$NAMESPACE" ]; then
            read -p "      Namespace para $USER? (Enter = pular): " NS_INPUT
            NAMESPACE="$NS_INPUT"
        fi

        info "$USER → namespace: ${NAMESPACE:-—}  cluster: ${CLUSTER:-?}"
    fi

    # Detecta categoria pelo nome
    CATEGORY="generic"; COLOR="gray"
    case "$USER" in
        *vtal*|*openshift*|*ocp*)  CATEGORY="openshift";  COLOR="blue"   ;;
        *oracle*|*db*)              CATEGORY="database";   COLOR="amber"  ;;
        *netwin*|*k8s*|*kube*)      CATEGORY="kubernetes"; COLOR="purple" ;;
        *fibrasil*|*client*)        CATEGORY="cliente";    COLOR="teal"   ;;
        *devops*|*infra*)           CATEGORY="admin";      COLOR="coral"  ;;
    esac

    if [ ! -f "$PROFILE_FILE" ]; then
        info "Criando profile: $USER"
        cat > "$PROFILE_FILE" << YAML
name: $USER
description: "SEM_DESCRICAO"
category: $CATEGORY
wsl_user: $USER
color: $COLOR
kubeconfig: "${KUBE_FILE}"
namespace: "${NAMESPACE}"
env:$([ -n "$KUBE_FILE" ] && echo "
  KUBECONFIG: ${KUBE_FILE}" || echo " {}")
aliases:
  ll: ls -lah$([ -n "$NAMESPACE" ] && echo "
  k: kubectl -n ${NAMESPACE}
  kpods: kubectl get pods -n ${NAMESPACE}
  klogs: kubectl logs -n ${NAMESPACE}" || echo "")
integrations:
  orchestrator: false
  oracle: $([ "$CATEGORY" = "database" ] && echo "true" || echo "false")
  openshift: $([ "$CATEGORY" = "openshift" ] && echo "true" || echo "false")
check: $([ -n "$NAMESPACE" ] && echo "
  - type: kubectl
    namespace: ${NAMESPACE}" || echo "[]")
YAML
        ok "Profile criado: $USER"
    else
        ok "Profile já existe: $USER (mantido)"
    fi
done

# ── Snippet .zshrc ────────────────────────────────────
header "⚙️  Configurando .zshrc..."

SNIPPET="
# ── EnvCtl ────────────────────────────────────────────
export ENVCTL_DIR=\"/opt/envctl\"
export ENVCTL_DATA=\"\$HOME/.envctl\"
export ENVCTL_PROFILES=\"$PROFILES_ONEDRIVE\"
export PATH=\"\$HOME/.local/bin:\$PATH\"

alias wm=\"envctl\"

# Banner ao entrar num ambiente via envctl (sessão filha)
if [ -n \"\$ENVCTL_PROFILE\" ] && [ -n \"\$ENVCTL_CHILD\" ]; then
    python3 /opt/envctl/core/banner.py \"\$ENVCTL_PROFILE\" 2>/dev/null || true
fi

# Auto-inicia TUI na sessão principal do $MANAGER_USER
if [ \"\$(whoami)\" = \"$MANAGER_USER\" ] && [ -t 1 ] && [ -z \"\$ENVCTL_CHILD\" ]; then
    export ENVCTL_CHILD=1
    envctl
    unset ENVCTL_PROFILE ENVCTL_SESSION ENVCTL_CHILD
fi

# Hook orquestrador Netwin
netwin-run() {
    ENVCTL_DIR=/opt/envctl python3 -m core.netwin_hook \"\$@\"
}
# ──────────────────────────────────────────────────────
"

ZSHRC="$HOME/.zshrc"
if ! grep -q "EnvCtl" "$ZSHRC" 2>/dev/null; then
    echo "$SNIPPET" >> "$ZSHRC"
    ok ".zshrc atualizado"
else
    python3 - << PYEOF
import re
with open('$ZSHRC', 'r') as f:
    content = f.read()
content = re.sub(r'# ── EnvCtl.*?# ──+\n', '', content, flags=re.DOTALL)
snippet = """
# ── EnvCtl ────────────────────────────────────────────
export ENVCTL_DIR="/opt/envctl"
export ENVCTL_DATA="\$HOME/.envctl"
export ENVCTL_PROFILES="$PROFILES_ONEDRIVE"
export PATH="\$HOME/.local/bin:\$PATH"

alias wm="envctl"

if [ -n "\$ENVCTL_PROFILE" ] && [ -n "\$ENVCTL_CHILD" ]; then
    python3 /opt/envctl/core/banner.py "\$ENVCTL_PROFILE" 2>/dev/null || true
fi

if [ "\$(whoami)" = "$MANAGER_USER" ] && [ -t 1 ] && [ -z "\$ENVCTL_CHILD" ]; then
    export ENVCTL_CHILD=1
    envctl
    unset ENVCTL_PROFILE ENVCTL_SESSION ENVCTL_CHILD
fi

netwin-run() {
    ENVCTL_DIR=/opt/envctl python3 -m core.netwin_hook "\$@"
}
# ──────────────────────────────────────────────────────
"""
with open('$ZSHRC', 'w') as f:
    f.write(content.rstrip() + '\n' + snippet)
print("  \033[0;32m✓\033[0m .zshrc atualizado")
PYEOF
fi

# ── Scripts globais ───────────────────────────────────
header "🔧 Instalando scripts globais..."

for script in create-user-wsl remove-user-wsl; do
    SRC="$ENVCTL_ONEDRIVE/scripts/${script}.sh"
    DST="/usr/local/bin/$script"
    if [ -f "$SRC" ]; then
        sudo cp "$SRC" "$DST"
        sudo chmod +x "$DST"
        ok "$script instalado"
    else
        warn "$script não encontrado em scripts/"
    fi
done

# ── Resumo final ──────────────────────────────────────
echo ""
echo -e "${BOLD}  ✅ EnvCtl instalado com sucesso!${RESET}"
echo ""
echo -e "  ${CYAN}Fonte:${RESET}     $ENVCTL_ONEDRIVE"
echo -e "  ${CYAN}Symlink:${RESET}   $INSTALL_DIR → OneDrive"
echo -e "  ${CYAN}Profiles:${RESET}  $PROFILES_ONEDRIVE"
echo -e "  ${CYAN}Dados:${RESET}     $HOME/.envctl"
echo -e "  ${CYAN}Manager:${RESET}   $MANAGER_USER"
echo -e "  ${CYAN}Usuários:${RESET}  $(echo $WSL_USERS | tr '\n' ' ')"
echo ""
echo -e "  Feche e reabra o terminal, ou execute:  ${BOLD}source ~/.zshrc${RESET}"
echo -e "  Para iniciar:  ${BOLD}envctl${RESET}  ou  ${BOLD}wm${RESET}"
echo ""