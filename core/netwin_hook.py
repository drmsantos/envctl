"""
core/netwin_hook.py — integração com o orquestrador Netwin
Registra deploys/operações automaticamente no histórico do envctl
"""
import os
import sys
import json
import subprocess
from pathlib import Path
from datetime import datetime, timezone

# Adiciona o envctl ao path para importar db
ENVCTL_DIR = Path(__file__).parent.parent
sys.path.insert(0, str(ENVCTL_DIR))

from core.db import log_operation, init_db


OPERATION_MAP = {
    "deploy.py":    "deploy",
    "startup.py":   "startup",
    "shutdown.py":  "shutdown",
    "rollout.py":   "rollout",
    "migrate.py":   "migrate",
    "rollback.py":  "rollback",
}


def get_current_profile() -> str:
    """Detecta o perfil ativo via variável de ambiente setada pelo envctl."""
    return os.environ.get("ENVCTL_PROFILE", "unknown")


def run_netwin_operation(script: str, args: list[str]) -> int:
    """
    Wrapper que executa um script do orquestrador e loga o resultado.
    Uso: python3 -m core.netwin_hook deploy.py --env hml
    """
    init_db()
    profile = get_current_profile()
    operation = OPERATION_MAP.get(script, script)
    detail = " ".join(args) if args else ""

    print(f"[envctl] Registrando operação: {operation} | perfil: {profile}")

    netwin_dir = Path(os.environ.get("NETWIN_DIR", Path.home() / "netwin"))
    script_path = netwin_dir / script

    try:
        result = subprocess.run(
            [sys.executable, str(script_path)] + args,
            cwd=str(netwin_dir)
        )
        status = "ok" if result.returncode == 0 else "error"
    except Exception as e:
        print(f"[envctl] Erro ao executar {script}: {e}")
        status = "error"
        detail += f" | erro: {e}"

    log_operation(profile, operation, detail, status)
    print(f"[envctl] Operação registrada: {operation} → {status}")

    return result.returncode if "result" in dir() else 1


def log_manual(profile: str, operation: str, detail: str = "", status: str = "ok"):
    """Loga uma operação manual no histórico."""
    init_db()
    log_operation(profile, operation, detail, status)


if __name__ == "__main__":
    # python3 -m core.netwin_hook <script.py> [args...]
    if len(sys.argv) < 2:
        print("Uso: python3 -m core.netwin_hook <script.py> [args...]")
        sys.exit(1)
    script = sys.argv[1]
    args = sys.argv[2:]
    sys.exit(run_netwin_operation(script, args))
