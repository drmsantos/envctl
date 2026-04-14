#!/usr/bin/env python3
"""
Atualiza namespace e kubeconfig num profile existente
Uso: python3 update_profile.py <profile_file> <namespace> <kubeconfig>
"""
import sys
import yaml

profile_file = sys.argv[1]
namespace = sys.argv[2] if len(sys.argv) > 2 else ""
kubeconfig = sys.argv[3] if len(sys.argv) > 3 else ""

with open(profile_file, 'r') as f:
    data = yaml.safe_load(f)

updated = False
if not data.get('namespace') and namespace:
    data['namespace'] = namespace
    updated = True
if not data.get('kubeconfig') and kubeconfig:
    data['kubeconfig'] = kubeconfig
    updated = True
if namespace and not data.get('env'):
    data['env'] = {}
if namespace:
    data.setdefault('env', {})['KUBECONFIG'] = kubeconfig
    data['env']['KUBE_NAMESPACE'] = namespace
if namespace and not data.get('aliases'):
    data['aliases'] = {}
    data['aliases']['k'] = f'kubectl -n {namespace}'
    data['aliases']['kpods'] = f'kubectl get pods -n {namespace}'
    data['aliases']['klogs'] = f'kubectl logs -n {namespace}'
if namespace and not data.get('check'):
    data['check'] = [{'type': 'kubectl', 'namespace': namespace}]

if updated:
    with open(profile_file, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
    print(f"  ✓ Atualizado: {data['name']} (namespace={data.get('namespace','')})")
else:
    print(f"  Profile já completo: {data['name']}")
