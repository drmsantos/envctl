#!/usr/bin/env python3
"""
tui/menu.py — Menu principal do EnvCtl
"""
import os
import sys
import subprocess
from pathlib import Path

ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT))

from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.text import Text
from rich.align import Align
from rich.prompt import Prompt
from rich import box
from datetime import datetime

console = Console()


def render_header():
    console.print()
    console.print(Align.center(
        Text("⚡ EnvCtl", style="bold magenta") +
        Text("  —  DevOps Environment Control", style="dim")
    ))
    console.print(Align.center(
        Text(f"  {datetime.now().strftime('%d/%m/%Y  %H:%M')}", style="dim cyan")
    ))
    console.print()


def list_wsl_users() -> list:
    import pwd
    users = []
    for p in pwd.getpwall():
        if p.pw_dir.startswith("/home/") and p.pw_shell in ("/bin/zsh", "/usr/bin/zsh", "/bin/bash"):
            users.append(p.pw_name)
    return sorted(users)


def render_users_table() -> Table:
    import grp, pwd
    users = list_wsl_users()
    table = Table(box=box.SIMPLE, border_style="dim", header_style="bold dim", expand=True)
    table.add_column("#",          width=4,  justify="right", style="dim")
    table.add_column("Usuário",    style="bold cyan", min_width=14)
    table.add_column("Grupos",     style="dim", min_width=20)
    table.add_column("Shell",      style="dim", width=10)
    table.add_column("Profile",    width=10)

    for i, u in enumerate(users, 1):
        try:
            pw = pwd.getpwnam(u)
            groups = [g.gr_name for g in grp.getgrall() if u in g.gr_mem]
            profile_exists = (ROOT / "profiles" / f"{u}.yaml").exists()
            profile_txt = Text("✓ sim", style="green") if profile_exists else Text("✗ não", style="dim red")
            table.add_row(
                f"[{i:02d}]", u,
                ", ".join(groups[:4]) or "—",
                pw.pw_shell.split("/")[-1],
                profile_txt
            )
        except Exception:
            table.add_row(f"[{i:02d}]", u, "—", "—", "—")

    return table


def run_create_user():
    script = "/usr/local/bin/create-user-wsl"
    if not Path(script).exists():
        script = str(ROOT / "scripts" / "create-user-wsl.sh")
    console.print(f"\n[dim]  Iniciando criação de usuário...[/dim]\n")
    try:
        subprocess.run(["sudo", "bash", script])
    except Exception as e:
        console.print(f"[red]  Erro: {e}[/red]")

    console.print()
    sync = Prompt.ask("  Sincronizar profiles do EnvCtl agora?", choices=["s", "n"], default="s")
    if sync == "s":
        sync_script = ROOT / "core" / "sync_profiles.py"
        if sync_script.exists():
            subprocess.run(["sudo", "python3", str(sync_script)])
        else:
            console.print("[dim]  sync_profiles.py não encontrado.[/dim]")
    console.input("\n  Enter para voltar...")


def run_remove_user():
    script = "/usr/local/bin/remove-user-wsl"
    if not Path(script).exists():
        script = str(ROOT / "scripts" / "remove-user-wsl.sh")
    console.print(f"\n[dim]  Iniciando remoção de usuário...[/dim]\n")
    try:
        subprocess.run(["sudo", "bash", script])
    except Exception as e:
        console.print(f"[red]  Erro: {e}[/red]")
    console.input("\n  Enter para voltar...")


def run_reset_password():
    users = list_wsl_users()
    console.clear()
    render_header()
    console.print("[bold]  Usuários disponíveis:[/bold]")
    for i, u in enumerate(users, 1):
        console.print(f"  [dim][{i:02d}][/dim] {u}")
    console.print()
    user = Prompt.ask("  Usuário para resetar senha").strip()
    if user:
        subprocess.run(["sudo", "passwd", user])
    console.input("\n  Enter para voltar...")


def show_users_panel():
    while True:
        console.clear()
        render_header()
        console.print(Panel(
            render_users_table(),
            title="[bold]Usuários WSL",
            border_style="cyan dim",
        ))
        console.print()
        console.print(
            "  [dim][[bold]c[/bold]] Criar  "
            "[[bold]r[/bold]] Remover  "
            "[[bold]p[/bold]] Reset senha  "
            "[[bold]q[/bold]] Voltar[/dim]"
        )
        console.print()
        choice = Prompt.ask("  [bold cyan]>[/bold cyan]", default="q").strip().lower()

        if choice == "q":
            break
        elif choice == "c":
            run_create_user()
        elif choice == "r":
            run_remove_user()
        elif choice == "p":
            run_reset_password()


def run_sync_profiles():
    sync_script = ROOT / "core" / "sync_profiles.py"
    if sync_script.exists():
        subprocess.run(["sudo", "python3", str(sync_script)])
    else:
        console.print("[red]  sync_profiles.py não encontrado.[/red]")
    console.input("\n  Enter para voltar...")


def show_main_menu():
    while True:
        console.clear()
        render_header()

        console.print(Panel(
            "\n"
            "  [bold magenta][01][/bold magenta]  [bold]Gerenciar ambientes[/bold]\n"
            "       [dim]Acessar, monitorar e operar ambientes DevOps[/dim]\n\n"
            "  [bold cyan][02][/bold cyan]  [bold]Gerenciar usuários WSL[/bold]\n"
            "       [dim]Criar, remover, listar e resetar senha[/dim]\n\n"
            "  [bold yellow][03][/bold yellow]  [bold]Sincronizar profiles[/bold]\n"
            "       [dim]Atualiza kubeconfigs e namespaces dos profiles[/dim]\n\n"
            "  [bold dim][q][/bold dim]   Sair\n",
            title="[bold]Menu Principal",
            border_style="magenta dim",
            padding=(0, 2),
        ))

        console.print()
        choice = Prompt.ask("  [bold magenta]>[/bold magenta]", default="q").strip().lower()

        if choice == "q":
            console.print("\n[dim]Até mais, Leo.[/dim]\n")
            break
        elif choice in ("01", "1"):
            from tui.app import show_main_menu as show_env_menu
            show_env_menu()
        elif choice in ("02", "2"):
            show_users_panel()
        elif choice in ("03", "3"):
            run_sync_profiles()


def main():
    try:
        show_main_menu()
    except KeyboardInterrupt:
        console.print("\n[dim]Interrompido.[/dim]\n")


if __name__ == "__main__":
    main()
