#!/usr/bin/env python3
"""sync_profiles.py — sincroniza kubeconfigs nos profiles"""
import os, sys, yaml
from pathlib import Path

PROFILES_DIR = Path("/opt/envctl/profiles")

COLOR_MAP = {"vtal":"blue","openshift":"coral","oracle":"amber","netwin":"purple","fibrasil":"teal","operador":"blue"}
CATEGORY_MAP = {"vtal":"openshift","openshift":"openshift","oracle":"database","netwin":"kubernetes","fibrasil":"cliente"}

def parse_kubeconfig(path):
    try:
        data = yaml.safe_load(path.read_text())
        ctx = data.get("current-context","")
        ns, cl = "", ""
        for c in data.get("contexts",[]):
            if c["name"] == ctx:
                ns = c.get("context",{}).get("namespace","")
                cl = c.get("context",{}).get("cluster","")
                break
        return ns, cl, str(path)
    except Exception as e:
        print(f"    Erro: {e}")
        return "", "", str(path)

def find_kubeconfigs(user):
    kube_dir = Path(f"/home/{user}/.kube")
    if not kube_dir.exists(): return []
    return sorted([f for f in kube_dir.iterdir()
        if f.name.startswith("config") and f.is_file() and "cache" not in str(f)])

def sync_user(profile_path):
    with open(profile_path) as f:
        profile = yaml.safe_load(f)
    user = profile.get("wsl_user", profile.get("name",""))
    print(f"\n── {user} ──────────────────────────")
    configs = find_kubeconfigs(user)
    if not configs:
        print(f"  Nenhum kubeconfig encontrado")
        return
    if len(configs) == 1:
        selected = configs[0]
        print(f"  Kubeconfig: {selected.name}")
    else:
        print(f"  Kubeconfigs disponíveis:")
        for i, c in enumerate(configs):
            ns, cl, _ = parse_kubeconfig(c)
            print(f"    [{i}] {c.name}  (cluster: {cl or '?'}  ns: {ns or '—'})")
        choice = input(f"  Qual usar? [0-{len(configs)-1}] (Enter = pular): ").strip()
        if choice.isdigit() and int(choice) < len(configs):
            selected = configs[int(choice)]
        else:
            print(f"  Pulando {user}")
            return
    ns, cl, kube_path = parse_kubeconfig(selected)
    if not ns:
        ns = input(f"  Namespace para {user}? (Enter = pular): ").strip()
    print(f"  → ns: {ns or '—'}  cluster: {cl or '?'}")
    profile["kubeconfig"] = kube_path
    if ns: profile["namespace"] = ns
    profile.setdefault("env",{})["KUBECONFIG"] = kube_path
    if ns: profile["env"]["KUBE_NAMESPACE"] = ns
    if ns:
        profile.setdefault("aliases",{})
        profile["aliases"]["k"] = f"kubectl -n {ns}"
        profile["aliases"]["kpods"] = f"kubectl get pods -n {ns}"
        profile["aliases"]["klogs"] = f"kubectl logs -n {ns}"
    if ns and not profile.get("check"):
        profile["check"] = [{"type":"kubectl","namespace":ns}]
    if profile.get("category") == "generic":
        profile["category"] = CATEGORY_MAP.get(user, "generic")
        profile["color"] = COLOR_MAP.get(user, "gray")
    with open(profile_path, "w") as f:
        yaml.dump(profile, f, default_flow_style=False, allow_unicode=True)
    print(f"  ✓ Atualizado")

def main():
    if os.geteuid() != 0:
        print("Execute como root: sudo python3 sync_profiles.py")
        sys.exit(1)
    profiles = sorted(PROFILES_DIR.glob("*.yaml"))
    print(f"⚡ Sincronizando {len(profiles)} profiles...")
    for p in profiles:
        sync_user(p)
    print(f"\n✅ Concluído!")

if __name__ == "__main__":
    main()
