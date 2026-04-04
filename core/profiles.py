"""
core/profiles.py — carrega e valida profiles YAML
"""
import yaml
import os
import socket
import subprocess
from pathlib import Path
from dataclasses import dataclass, field

PROFILES_DIR = Path(os.environ.get("ENVCTL_PROFILES",
    Path(__file__).parent.parent / "profiles"))


@dataclass
class Profile:
    name: str
    description: str
    category: str
    wsl_user: str
    color: str = "gray"
    kubeconfig: str = ""
    namespace: str = ""
    env: dict = field(default_factory=dict)
    aliases: dict = field(default_factory=dict)
    integrations: dict = field(default_factory=dict)
    check: list = field(default_factory=list)


def _profile_from_dict(data: dict) -> Profile:
    return Profile(
        name=data.get("name", ""),
        description=data.get("description", ""),
        category=data.get("category", ""),
        wsl_user=data.get("wsl_user", ""),
        color=data.get("color", "gray"),
        kubeconfig=data.get("kubeconfig", ""),
        namespace=data.get("namespace", ""),
        env=data.get("env") or {},
        aliases=data.get("aliases") or {},
        integrations=data.get("integrations") or {},
        check=data.get("check") or [],
    )


def load_profiles() -> list[Profile]:
    profiles = []
    for f in sorted(PROFILES_DIR.glob("*.yaml")):
        with open(f) as fh:
            data = yaml.safe_load(fh)
        profiles.append(_profile_from_dict(data))
    return profiles


def load_profile(name: str) -> Profile | None:
    f = PROFILES_DIR / f"{name}.yaml"
    if not f.exists():
        return None
    with open(f) as fh:
        data = yaml.safe_load(fh)
    return _profile_from_dict(data)


def check_tcp(host: str, port: int, timeout: float = 2.0) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except (OSError, socket.timeout):
        return False


def check_kubectl(namespace: str, timeout: float = 3.0) -> bool:
    try:
        result = subprocess.run(
            ["kubectl", "get", "deployments", "-n", namespace],
            capture_output=True, timeout=timeout
        )
        return result.returncode == 0
    except Exception:
        return False


def health_check(profile: Profile) -> dict:
    results = {}
    for chk in profile.check:
        if chk["type"] == "tcp":
            ok = check_tcp(chk["host"], chk["port"])
            results[f"tcp:{chk['host']}:{chk['port']}"] = ok
        elif chk["type"] == "kubectl":
            ok = check_kubectl(chk.get("namespace", "default"))
            results[f"kubectl:{chk.get('namespace','default')}"] = ok
    return results
