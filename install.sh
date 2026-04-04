#!/usr/bin/env bash
# install.sh — instala o envctl em /opt e configura o usuário devops
set -e

INSTALL_DIR="/opt/envctl"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_LINK="/usr/local/bin/envctl"
DATA_DIR="$HOME/.envctl"
MANAGER_USER="devops"

echo "⚡ Instalando EnvCtl..."

# Copia para /opt
sudo mkdir -p "$INSTALL_DIR"
if [ "$SRC_DIR" != "$INSTALL_DIR" ]; then
  sudo cp -r "$SRC_DIR/." "$INSTALL_DIR/"
else
  echo "  (já em $INSTALL_DIR, pulando cópia)"
fi
sudo chown -R root:$MANAGER_USER "$INSTALL_DIR" 2>/dev/null || sudo chown -R root:$(whoami) "$INSTALL_DIR"
sudo chmod -R 750 "$INSTALL_DIR"
sudo chmod +x "$INSTALL_DIR/envctl.py"
echo "✓ Copiado para $INSTALL_DIR"

# Symlink global
sudo rm -f "$BIN_LINK"
sudo ln -s "$INSTALL_DIR/envctl.py" "$BIN_LINK"
echo "✓ Symlink criado: $BIN_LINK"

# Cria diretório de dados do usuário
mkdir -p "$DATA_DIR/logs"
echo "✓ Diretório de dados: $DATA_DIR"

# Dependências Python
pip install -r "$INSTALL_DIR/requirements.txt" --quiet --break-system-packages 2>/dev/null \
    || pip install -r "$INSTALL_DIR/requirements.txt" --quiet
echo "✓ Dependências instaladas"

# ── Auto-detecta usuários WSL ──────────────────────────
echo ""
echo "🔍 Detectando usuários WSL..."

# Usuários com home em /home/, shell válido, excluindo o manager
WSL_USERS=$(getent passwd \
    | awk -F: '$6 ~ /^\/home\// && $7 ~ /(bash|zsh|sh)$/ {print $1}' \
    | grep -v "^$MANAGER_USER$" \
    | sort)

if [ -z "$WSL_USERS" ]; then
    echo "  Nenhum usuário encontrado em /home/"
else
    echo "  Encontrados: $(echo $WSL_USERS | tr '\n' ' ')"
fi

# ── Configura sudoers ──────────────────────────────────
echo ""
echo "🔐 Configurando sudoers..."

SUDOERS_FILE="/etc/sudoers.d/envctl"
USERS_LIST=$(echo "$WSL_USERS" | tr '\n' ',' | sed 's/,$//')

if [ -n "$USERS_LIST" ]; then
    echo "$MANAGER_USER ALL=($USERS_LIST) NOPASSWD: /usr/bin/zsh, /bin/zsh" \
        | sudo tee "$SUDOERS_FILE" > /dev/null
    sudo chmod 440 "$SUDOERS_FILE"
    echo "✓ Sudoers configurado: $SUDOERS_FILE"
    echo "  $MANAGER_USER pode entrar como: $USERS_LIST"
else
    echo "  Nenhum usuário para configurar no sudoers"
fi

# ── Gera profiles YAML para usuários sem profile ──────
echo ""
echo "📁 Verificando profiles..."

for USER in $WSL_USERS; do
    PROFILE_FILE="$INSTALL_DIR/profiles/$USER.yaml"

    # Tenta ler kubeconfig do usuário
    KUBE_FILE=""
    NAMESPACE=""
    CLUSTER=""

    # Lista todos os configs disponíveis (lê com sudo pra contornar permissões)
    KUBE_CANDIDATES=()
    for f in /home/$USER/.kube/config /home/$USER/.kube/config-*; do
        sudo test -f "$f" 2>/dev/null && KUBE_CANDIDATES+=("$f")
    done

    if [ ${#KUBE_CANDIDATES[@]} -eq 0 ]; then
        echo "  $USER → nenhum kubeconfig encontrado, pulando"
    elif [ ${#KUBE_CANDIDATES[@]} -eq 1 ]; then
        KUBE_FILE="${KUBE_CANDIDATES[0]}"
        echo "  $USER → kubeconfig: $KUBE_FILE"
    else
        echo ""
        echo "  $USER → múltiplos kubeconfigs encontrados:"
        for i in "${!KUBE_CANDIDATES[@]}"; do
            # Extrai cluster name direto do arquivo via grep
            CNAME=$(sudo grep -m1 "^- name:" "${KUBE_CANDIDATES[$i]}" 2>/dev/null | awk '{print $3}' || echo "?")
            echo "    [$i] ${KUBE_CANDIDATES[$i]}  (cluster: $CNAME)"
        done
        read -p "  Qual usar para $USER? [0-$((${#KUBE_CANDIDATES[@]}-1))] (Enter = pular): " KUBE_IDX
        if [[ "$KUBE_IDX" =~ ^[0-9]+$ ]] && [ "$KUBE_IDX" -lt "${#KUBE_CANDIDATES[@]}" ]; then
            KUBE_FILE="${KUBE_CANDIDATES[$KUBE_IDX]}"
            echo "  Selecionado: $KUBE_FILE"
        else
            echo "  Pulando kubeconfig para $USER"
        fi
    fi

    if [ -n "$KUBE_FILE" ]; then
        # Extrai namespace e cluster direto do arquivo com sudo
        NAMESPACE=$(sudo python3 -c "
import yaml, sys
data = yaml.safe_load(open('$KUBE_FILE').read())
ctx = data.get('current-context','')
for c in data.get('contexts',[]):
    if c['name'] == ctx:
        print(c.get('context',{}).get('namespace',''))
        sys.exit()
print('')
" 2>/dev/null || echo "")

        CLUSTER=$(sudo python3 -c "
import yaml, sys
data = yaml.safe_load(open('$KUBE_FILE').read())
ctx = data.get('current-context','')
for c in data.get('contexts',[]):
    if c['name'] == ctx:
        print(c.get('context',{}).get('cluster',''))
        sys.exit()
print('')
" 2>/dev/null || echo "")

        # Se namespace vazio, pergunta
        if [ -z "$NAMESPACE" ]; then
            echo "  $USER → kubeconfig sem namespace definido (cluster: ${CLUSTER:-?})"
            read -p "  Namespace para $USER? (Enter = pular): " NS_INPUT
            NAMESPACE="$NS_INPUT"
        fi

        echo "  $USER → namespace: ${NAMESPACE:-—}  cluster: ${CLUSTER:-?}"
    fi

    # Detecta categoria pelo nome do usuário
    CATEGORY="generic"
    COLOR="gray"
    case "$USER" in
        *vtal*|*openshift*) CATEGORY="openshift"; COLOR="blue" ;;
        *oracle*|*db*)      CATEGORY="database";  COLOR="amber" ;;
        *netwin*|*k8s*|*kube*) CATEGORY="kubernetes"; COLOR="purple" ;;
        *fibrasil*|*client*) CATEGORY="cliente";  COLOR="teal" ;;
    esac

    if [ ! -f "$PROFILE_FILE" ]; then
        echo "  Criando profile para: $USER"
        sudo tee "$PROFILE_FILE" > /dev/null << YAML
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
  kpods: kubectl get pods -n ${NAMESPACE}" || echo "")
integrations:
  orchestrator: false
  oracle: false
  openshift: $([ "$CATEGORY" = "openshift" ] && echo "true" || echo "false")
check: $([ -n "$NAMESPACE" ] && echo "
  - type: kubectl
    namespace: ${NAMESPACE}" || echo "[]")
YAML
    else
        # Atualiza apenas namespace e kubeconfig se estiverem vazios
        sudo python3 /opt/envctl/core/update_profile.py "$PROFILE_FILE" "$NAMESPACE" "$KUBE_FILE"
    fi
done

# ── Snippet zshrc ──────────────────────────────────────
SNIPPET='
# ── EnvCtl ────────────────────────────────────────
export ENVCTL_DIR="/opt/envctl"
export ENVCTL_DATA="$HOME/.envctl"
export ENVCTL_PROFILES="/opt/envctl/profiles"
export PATH="$HOME/.local/bin:$PATH"

alias wm="envctl"

# Banner ao entrar num ambiente via envctl (sessão filha)
if [ -n "$ENVCTL_PROFILE" ] && [ -n "$ENVCTL_CHILD" ]; then
    python3 /opt/envctl/core/banner.py "$ENVCTL_PROFILE" 2>/dev/null || true
fi

# Auto-inicia TUI apenas na sessão principal do devops
if [ "$(whoami)" = "devops" ] && [ -t 1 ] && [ -z "$ENVCTL_CHILD" ]; then
    export ENVCTL_CHILD=1
    envctl
    unset ENVCTL_PROFILE
    unset ENVCTL_SESSION
    unset ENVCTL_CHILD
fi

# Hook orquestrador Netwin
netwin-run() {
    ENVCTL_DIR=/opt/envctl python3 -m core.netwin_hook "$@"
}
# ───────────────────────────────────────────────────────
'

ZSHRC="$HOME/.zshrc"
if ! grep -q "EnvCtl" "$ZSHRC" 2>/dev/null; then
    echo "$SNIPPET" >> "$ZSHRC"
    echo "✓ Snippet adicionado ao $ZSHRC"
else
    # Substitui bloco existente
    python3 - << PYEOF
import re
with open('$ZSHRC', 'r') as f:
    content = f.read()
block = re.sub(
    r'# ── EnvCtl.*?# ───+\n',
    '',
    content,
    flags=re.DOTALL
)
snippet = '''
# ── EnvCtl ────────────────────────────────────────
export ENVCTL_DIR="/opt/envctl"
export ENVCTL_DATA="\$HOME/.envctl"
export ENVCTL_PROFILES="/opt/envctl/profiles"
export PATH="\$HOME/.local/bin:\$PATH"

alias wm="envctl"

# Banner ao entrar num ambiente via envctl (sessão filha)
if [ -n "\$ENVCTL_PROFILE" ] && [ -n "\$ENVCTL_CHILD" ]; then
    python3 /opt/envctl/core/banner.py "\$ENVCTL_PROFILE" 2>/dev/null || true
fi

# Auto-inicia TUI apenas na sessão principal do devops
if [ "\$(whoami)" = "devops" ] && [ -t 1 ] && [ -z "\$ENVCTL_CHILD" ]; then
    export ENVCTL_CHILD=1
    envctl
    unset ENVCTL_PROFILE
    unset ENVCTL_SESSION
    unset ENVCTL_CHILD
fi

# Hook orquestrador Netwin
netwin-run() {
    ENVCTL_DIR=/opt/envctl python3 -m core.netwin_hook "\$@"
}
# ───────────────────────────────────────────────────────
'''
with open('$ZSHRC', 'w') as f:
    f.write(block.rstrip() + '\n' + snippet)
print("✓ .zshrc atualizado")
PYEOF
fi

echo ""
echo "✅ EnvCtl instalado com sucesso!"
echo ""
echo "  Instalado em:  $INSTALL_DIR"
echo "  Dados em:      $DATA_DIR"
echo "  Usuários:      $(echo $WSL_USERS | tr '\n' ' ')"
echo ""
echo "  Feche e reabra o terminal do usuário devops."
echo ""
