#!/usr/bin/env python3
"""
tui/app.py — EnvCtl TUI
Painel visual com Rich: lista de ambientes, histórico de deploys, status
"""
import os
import sys
import subprocess
from pathlib import Path
from datetime import datetime, timezone

# Path setup
ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT))

from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.columns import Columns
from rich.text import Text
from rich.prompt import Prompt
from rich.layout import Layout
from rich.live import Live
from rich import box
from rich.rule import Rule
from rich.align import Align

from core.profiles import load_profiles, load_profile, health_check, Profile
from core.db import init_db, get_last_operation, get_history, get_sessions, log_session_start, log_session_end

console = Console()

COLOR_MAP = {
    "purple": "magenta",
    "blue":   "blue",
    "amber":  "yellow",
    "teal":   "cyan",
    "coral":  "red",
    "gray":   "white",
    "green":  "green",
}

CATEGORY_ICON = {
    "kubernetes": "⎈",
    "openshift":  "🔴",
    "database":   "🗄",
    "cliente":    "🏢",
    "admin":      "🔧",
}


def fmt_color(profile: Profile) -> str:
    return COLOR_MAP.get(profile.color, "white")


def fmt_ago(iso: str) -> str:
    if not iso:
        return "—"
    try:
        dt = datetime.fromisoformat(iso)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        diff = datetime.now(timezone.utc) - dt
        s = int(diff.total_seconds())
        if s < 60: return f"{s}s atrás"
        if s < 3600: return f"{s//60}m atrás"
        if s < 86400: return f"{s//3600}h atrás"
        return f"{s//86400}d atrás"
    except Exception:
        return iso[:16]


def fmt_duration(seconds: int | None) -> str:
    if not seconds:
        return "—"
    if seconds < 60: return f"{seconds}s"
    if seconds < 3600: return f"{seconds//60}m {seconds%60}s"
    return f"{seconds//3600}h {(seconds%3600)//60}m"


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


def render_profiles_table(profiles: list[Profile]) -> Table:
    table = Table(
        box=box.ROUNDED,
        border_style="dim",
        header_style="bold dim",
        show_lines=False,
        expand=True,
    )
    table.add_column("#",         style="dim",    width=4,  justify="right")
    table.add_column("Ambiente",  style="bold",   min_width=14)
    table.add_column("Categoria", style="dim",    width=12)
    table.add_column("Usuário",   style="cyan",   width=14)
    table.add_column("Namespace", style="dim",    min_width=20)
    table.add_column("Último deploy",             min_width=20)
    table.add_column("Quando",    style="dim",    width=12)

    for i, p in enumerate(profiles, 1):
        color = fmt_color(p)
        icon = CATEGORY_ICON.get(p.category, "•")
        last = get_last_operation(p.name)

        if last:
            op_text = Text(f"{last['operation']}", style=color)
            if last["status"] == "error":
                op_text = Text(f"✗ {last['operation']}", style="red")
            elif last["status"] == "ok":
                op_text = Text(f"✓ {last['operation']}", style="green")
            quando = fmt_ago(last["ran_at"])
        else:
            op_text = Text("—", style="dim")
            quando = "—"

        table.add_row(
            f"[{i:02d}]",
            Text(f"{icon} {p.name}", style=f"bold {color}"),
            Text(p.category or "—", style="dim"),
            str(p.wsl_user or "—"),
            str(p.namespace or "—"),
            op_text,
            str(quando),
        )

    return table


def render_history_table(profile_name: str = None, limit: int = 15) -> Table:
    history = get_history(profile_name, limit)

    table = Table(
        box=box.SIMPLE,
        border_style="dim",
        header_style="bold dim",
        expand=True,
    )
    table.add_column("Quando",    width=14, style="dim")
    table.add_column("Ambiente",  width=12)
    table.add_column("Operação",  width=12)
    table.add_column("Detalhe",   min_width=20, style="dim")
    table.add_column("Status",    width=8)

    if not history:
        table.add_row("—", "—", "—", "Nenhuma operação registrada ainda", "—")
        return table

    for h in history:
        status_text = Text("✓ ok", style="green") if h["status"] == "ok" else Text("✗ erro", style="red")
        profile = load_profile(h["profile"])
        color = fmt_color(profile) if profile else "white"

        table.add_row(
            fmt_ago(h["ran_at"]),
            Text(h["profile"], style=f"bold {color}"),
            Text(h["operation"], style="bold"),
            h.get("detail") or "—",
            status_text,
        )

    return table


def render_sessions_table(limit: int = 8) -> Table:
    sessions = get_sessions(limit=limit)

    table = Table(
        box=box.SIMPLE,
        border_style="dim",
        header_style="bold dim",
        expand=True,
    )
    table.add_column("Ambiente",  width=12)
    table.add_column("Início",    width=16, style="dim")
    table.add_column("Duração",   width=10)
    table.add_column("Status",    width=10)

    if not sessions:
        table.add_row("—", "—", "—", "Sem sessões")
        return table

    for s in sessions:
        profile = load_profile(s["profile"])
        color = fmt_color(profile) if profile else "white"
        status = Text("ativa", style="green bold") if not s["ended_at"] else Text("encerrada", style="dim")
        table.add_row(
            Text(s["profile"], style=f"bold {color}"),
            fmt_ago(s["started_at"]),
            fmt_duration(s.get("duration_s")),
            status,
        )

    return table


def show_main_menu():
    init_db()
    profiles = load_profiles()

    while True:
        console.clear()
        render_header()

        console.print(Panel(
            render_profiles_table(profiles),
            title="[bold]Ambientes",
            border_style="magenta dim",
        ))

        console.print()
        console.print(Panel(
            render_history_table(limit=8),
            title="[bold]Histórico recente de operações",
            border_style="cyan dim",
        ))

        console.print()
        console.print(
            "  [dim][[bold]01-10[/bold]] Entrar  "
            "[[bold]e[/bold]] Editar profile  "
            "[[bold]h[/bold]] Histórico  "
            "[[bold]s[/bold]] Sessões  "
            "[[bold]r[/bold]] Atualizar  "
            "[[bold]q[/bold]] Sair[/dim]"
        )
        console.print()

        choice = Prompt.ask("  [bold magenta]>[/bold magenta]", default="q").strip().lower()

        if choice == "q":
            console.print("\n[dim]Até mais, Leo.[/dim]\n")
            break

        elif choice == "r":
            continue

        elif choice == "h":
            show_history_menu(profiles)

        elif choice == "s":
            show_sessions()

        elif choice == "e":
            edit_profile_menu(profiles)

        elif choice.isdigit() or (len(choice) == 2 and choice.isdigit()):
            idx = int(choice) - 1
            if 0 <= idx < len(profiles):
                enter_profile(profiles[idx])
            else:
                console.print(f"[red]  Opção inválida: {choice}[/red]")
                console.input("  [dim]Enter para continuar...[/dim]")


def show_history_menu(profiles: list[Profile]):
    PAGE_SIZE = 15
    page = 0

    options = ["Todos os ambientes"] + [p.name for p in profiles]
    console.clear()
    render_header()
    for i, opt in enumerate(options):
        console.print(f"  [dim][{i:02d}][/dim] {opt}")
    console.print()
    choice = Prompt.ask("  Filtrar por ambiente", default="0").strip()

    profile_filter = None
    if choice.isdigit():
        idx = int(choice)
        if 1 <= idx < len(options):
            profile_filter = options[idx]

    while True:
        from core.db import get_history
        history = get_history(profile_filter, limit=PAGE_SIZE * 10)
        total = len(history)
        paged = history[page * PAGE_SIZE:(page + 1) * PAGE_SIZE]

        console.clear()
        render_header()
        title = f"Histórico — {profile_filter or 'todos'}  [página {page+1}/{max(1,(total+PAGE_SIZE-1)//PAGE_SIZE)}]"

        from rich.table import Table
        from rich import box as rbox
        table = Table(box=rbox.SIMPLE, border_style="dim", header_style="bold dim", expand=True)
        table.add_column("Quando",   width=14, style="dim")
        table.add_column("Ambiente", width=12)
        table.add_column("Operação", width=12)
        table.add_column("Detalhe",  min_width=20, style="dim")
        table.add_column("Status",   width=8)

        if not paged:
            table.add_row("—","—","—","Nenhuma operação registrada","—")
        for h in paged:
            status_text = Text("✓ ok", style="green") if h["status"] == "ok" else Text("✗ erro", style="red")
            p = load_profile(h["profile"])
            color = fmt_color(p) if p else "white"
            table.add_row(
                fmt_ago(h["ran_at"]),
                Text(h["profile"], style=f"bold {color}"),
                Text(h["operation"], style="bold"),
                h.get("detail") or "—",
                status_text,
            )

        console.print(Panel(table, title=f"[bold]{title}", border_style="cyan dim"))
        console.print("  [dim][[bold]n[/bold]] próxima  [[bold]p[/bold]] anterior  [[bold]q[/bold]] voltar[/dim]")
        nav = Prompt.ask("  ", default="q").strip().lower()
        if nav == "q":
            break
        elif nav == "n" and (page + 1) * PAGE_SIZE < total:
            page += 1
        elif nav == "p" and page > 0:
            page -= 1


def show_sessions():
    console.clear()
    render_header()
    console.print(Panel(
        render_sessions_table(limit=20),
        title="[bold]Sessões",
        border_style="dim",
    ))
    console.input("\n  [dim]Enter para voltar...[/dim]")


def enter_profile(profile: Profile):
    console.clear()
    render_header()

    color = fmt_color(profile)
    icon = CATEGORY_ICON.get(profile.category, "•")

    console.print(Panel(
        f"[bold {color}]{icon}  {profile.name}[/bold {color}]\n"
        f"[dim]{profile.description}[/dim]\n\n"
        f"[dim]Usuário WSL:[/dim]  [bold]{profile.wsl_user}[/bold]\n"
        f"[dim]Categoria:[/dim]    {profile.category}\n"
        f"[dim]Namespace:[/dim]    {profile.namespace or '—'}\n"
        f"[dim]Kubeconfig:[/dim]   {profile.kubeconfig or '—'}",
        title=f"[bold]Entrando em: {profile.name}",
        border_style=f"{color} dim",
    ))

    # Health check
    if profile.check:
        console.print("\n[dim]Verificando conectividade...[/dim]")
        results = health_check(profile)
        for check, ok in results.items():
            status = "[green]✓ ok[/green]" if ok else "[red]✗ falhou[/red]"
            console.print(f"  {check}  {status}")

    console.print()

    # Último deploy
    last = get_last_operation(profile.name)
    if last:
        status_color = "green" if last["status"] == "ok" else "red"
        console.print(
            f"[dim]Último deploy:[/dim]  "
            f"[{status_color}]{last['operation']}[/{status_color}]  "
            f"[dim]{fmt_ago(last['ran_at'])}[/dim]"
        )
        console.print()

    console.print("[dim]Aliases disponíveis:[/dim]")
    for alias, cmd in profile.aliases.items():
        console.print(f"  [cyan]{alias}[/cyan]  →  [dim]{cmd}[/dim]")

    console.print()
    confirm = Prompt.ask(
        f"  Entrar como [bold {color}]{profile.wsl_user}[/bold {color}]?",
        choices=["s", "n"], default="s"
    )

    if confirm == "s":
        session_id = log_session_start(profile.name, profile.wsl_user)

        # Monta exports inline para passar ao usuário destino
        env_exports = (
            f"export ENVCTL_PROFILE={profile.name}; "
            f"export ENVCTL_SESSION={session_id}; "
            f"export ENVCTL_CHILD=1;"
        )
        for k, v in profile.env.items():
            val = str(v).replace("~", f"/home/{profile.wsl_user}")
            env_exports += f" export {k}={val};"

        zsh_cmd = f"{env_exports} exec zsh -l"

        console.print(f"\n[dim]Iniciando sessão {profile.wsl_user}...[/dim]\n")

        try:
            subprocess.run(["sudo", "-u", profile.wsl_user, "-H", "zsh", "-i", "-l", "-c", zsh_cmd])
        except Exception as e:
            console.print(f"[red]Erro ao entrar como {profile.wsl_user}: {e}[/red]")
        finally:
            log_session_end(session_id)
            console.print(f"\n[dim]Sessão encerrada — {profile.name}[/dim]")


def main():
    try:
        show_main_menu()
    except KeyboardInterrupt:
        console.print("\n[dim]Interrompido.[/dim]\n")


if __name__ == "__main__":
    main()


def edit_profile_menu(profiles: list):
    """Edita campos básicos de um profile direto pelo menu."""
    console.clear()
    render_header()

    for i, p in enumerate(profiles, 1):
        console.print(f"  [dim][{i:02d}][/dim] {p.name}  [dim]{p.description or '—'}[/dim]")

    console.print()
    choice = Prompt.ask("  Qual profile editar? (número ou Enter para voltar)").strip()

    if not choice.isdigit():
        return

    idx = int(choice) - 1
    if not (0 <= idx < len(profiles)):
        return

    profile = profiles[idx]
    profile_path = Path(os.environ.get("ENVCTL_PROFILES", Path(__file__).parent.parent / "profiles")) / f"{profile.name}.yaml"

    console.clear()
    render_header()
    console.print(f"[bold]Editando: {profile.name}[/bold]\n")
    console.print("[dim]Deixe em branco para manter o valor atual[/dim]\n")

    import yaml

    with open(profile_path) as f:
        data = yaml.safe_load(f)

    desc = Prompt.ask(f"  Descrição [{data.get('description','—')}]", default="").strip()
    ns   = Prompt.ask(f"  Namespace  [{data.get('namespace','—')}]", default="").strip()
    cat  = Prompt.ask(f"  Categoria  [{data.get('category','—')}]", default="").strip()
    col  = Prompt.ask(f"  Cor        [{data.get('color','gray')}]", default="").strip()

    if desc: data['description'] = desc
    if ns:   data['namespace'] = ns
    if cat:  data['category'] = cat
    if col:  data['color'] = col

    with open(profile_path, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True)

    console.print(f"\n[green]  ✓ Profile '{profile.name}' atualizado.[/green]")
    console.input("\n  Enter para voltar...")
