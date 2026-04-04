#!/usr/bin/env bash
# remove-user-wsl.sh — Remove usuário WSL
# Pode ser chamado por qualquer usuário — eleva para root automaticamente
set -e

# ── Auto-elevação ──────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    exec sudo bash "$0" "$@"
fi

SUDOERS_ENVCTL="/etc/sudoers.d/envctl"
ENVCTL_DIR="/opt/envctl"

# ── Header ─────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════╗"
echo "║   REMOVER USUÁRIO WSL — EnvCtl       ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Lista usuários disponíveis ─────────────────────────
echo "  Usuários disponíveis:"
getent passwd \
    | awk -F: '$6 ~ /^\/home\// && $7 ~ /(bash|zsh|sh)$/ {print "    → " $1}' \
    | grep -v "devops"
echo ""

# ── Nome do usuário ────────────────────────────────────
read -rp "  Usuário para remover: " USER_NAME
USER_NAME="${USER_NAME// /}"

if [[ -z "$USER_NAME" ]]; then
    echo "  Nome inválido."
    exit 1
fi

if ! id "$USER_NAME" &>/dev/null; then
    echo "  ✗ Usuário '$USER_NAME' não existe."
    exit 1
fi

if [ "$SUDO_USER" == "$USER_NAME" ] || [ "$USER" == "$USER_NAME" ]; then
    echo "  ✗ Não é possível remover o usuário atual."
    exit 1
fi

# Proteção extra — não remover devops
if [ "$USER_NAME" == "devops" ]; then
    echo "  ✗ Não é possível remover o usuário devops."
    exit 1
fi

# ── Confirmação ────────────────────────────────────────
echo ""
echo "  ⚠ Isso irá remover:"
echo "    → Usuário: $USER_NAME"
echo "    → Home:    /home/$USER_NAME"
echo "    → Profile: $ENVCTL_DIR/profiles/$USER_NAME.yaml"
echo ""
read -rp "  Confirmar remoção de '$USER_NAME'? (s/n): " CONFIRM

if [[ "$CONFIRM" != "s" ]]; then
    echo "  Operação cancelada."
    exit 0
fi

# ── Remove processos ativos ────────────────────────────
pkill -u "$USER_NAME" &>/dev/null || true
echo "  ✓ Processos encerrados"

# ── Remove usuário ─────────────────────────────────────
deluser --remove-home "$USER_NAME" &>/dev/null || userdel -r "$USER_NAME" &>/dev/null
echo "  ✓ Usuário removido"

# ── Remove profile EnvCtl ──────────────────────────────
PROFILE="$ENVCTL_DIR/profiles/$USER_NAME.yaml"
if [ -f "$PROFILE" ]; then
    rm -f "$PROFILE"
    echo "  ✓ Profile EnvCtl removido"
fi

# ── Atualiza sudoers EnvCtl ────────────────────────────
if [ -f "$SUDOERS_ENVCTL" ]; then
    ALL_USERS=$(getent passwd \
        | awk -F: '$6 ~ /^\/home\// && $7 ~ /(bash|zsh|sh)$/ {print $1}' \
        | grep -v "^devops$" | sort | tr '\n' ',' | sed 's/,$//')
    if [ -n "$ALL_USERS" ]; then
        echo "devops ALL=($ALL_USERS) NOPASSWD: /usr/bin/zsh, /bin/zsh" > "$SUDOERS_ENVCTL"
    else
        echo "" > "$SUDOERS_ENVCTL"
    fi
    chmod 440 "$SUDOERS_ENVCTL"
    echo "  ✓ Sudoers EnvCtl atualizado"
fi

# ── Resumo ─────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════╗"
echo "║  ✅ Usuário $USER_NAME removido com sucesso"
echo "╚══════════════════════════════════════╝"
echo ""
