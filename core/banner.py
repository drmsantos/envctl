#!/usr/bin/env python3
"""
core/banner.py — exibe banner do perfil ao entrar na sessão
Chamado pelo .zshrc quando ENVCTL_PROFILE está definido
"""
import sys
from pathlib import Path

ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT))

from rich.console import Console
from rich.panel import Panel
from rich.text import Text
from datetime import datetime

from core.profiles import load_profile
from core.db import get_last_operation, init_db

COLOR_MAP = {
    "purple": "magenta", "blue": "blue", "amber": "yellow",
    "teal": "cyan", "coral": "red", "gray": "white", "green": "green",
}

CATEGORY_ICON = {
    "kubernetes": "⎈", "openshift": "🔴", "database": "🗄",
    "cliente": "🏢", "admin": "🔧",
}


def main():
    if len(sys.argv) < 2:
        return

    profile_name = sys.argv[1]
    init_db()

    profile = load_profile(profile_name)
    if not profile:
        return

    console = Console()
    color = COLOR_MAP.get(profile.color, "white")
    icon = CATEGORY_ICON.get(profile.category, "•")

    last = get_last_operation(profile.name)
    last_str = ""
    if last:
        status_icon = "✓" if last["status"] == "ok" else "✗"
        last_str = f"\n[dim]Último deploy:[/dim] {status_icon} {last['operation']}  [dim]{last['ran_at'][:16]}[/dim]"

    ns_str = f"\n[dim]Namespace:[/dim]     {profile.namespace}" if profile.namespace else ""
    kube_str = f"\n[dim]Kubeconfig:[/dim]   {profile.kubeconfig}" if profile.kubeconfig else ""

    content = (
        f"[bold {color}]{icon}  {profile.name}[/bold {color}]  [dim]—[/dim]  {profile.description}"
        f"{ns_str}{kube_str}{last_str}"
    )

    console.print()
    console.print(Panel(content, border_style=f"{color} dim", padding=(0, 2)))
    console.print()


if __name__ == "__main__":
    main()
