# ⚡ EnvCtl — DevOps Environment Control

> Gerenciador visual de ambientes DevOps para WSL — TUI centralizada com gestão de usuários, histórico de operações e sincronização de kubeconfigs.

![Python](https://img.shields.io/badge/Python-3.10%2B-blue?style=flat-square&logo=python)
![Shell](https://img.shields.io/badge/Shell-Bash%2FZsh-green?style=flat-square&logo=gnubash)
![Platform](https://img.shields.io/badge/Platform-WSL2-orange?style=flat-square&logo=linux)
![License](https://img.shields.io/badge/License-MIT-purple?style=flat-square)

---

## O problema

Ambientes DevOps modernos exigem acesso a múltiplos clusters, namespaces e contextos — cada um com suas credenciais, kubeconfigs e ferramentas. Sem uma forma centralizada de gerenciar isso, o resultado é:

- Troca manual de `KUBECONFIG` e contextos `kubectl`
- Credenciais e namespaces espalhados em arquivos diferentes
- Sem histórico de quem fez o quê em cada ambiente
- Usuários WSL sem padrão de configuração

O **EnvCtl** resolve isso com uma TUI (Terminal UI) centralizada que organiza todos os ambientes, gerencia usuários WSL e mantém histórico de operações.

---

## Funcionalidades

### 🖥️ TUI Principal
- Painel com todos os ambientes DevOps
- Status do último deploy por ambiente
- Navegação por número ou atalhos de teclado
- Health check de conectividade antes de entrar

### 📁 Gerenciamento de Ambientes
- Profiles por ambiente em YAML — kubeconfig, namespace, aliases, variáveis
- Detecção automática de kubeconfigs em `~/.kube/config*`
- Sincronização automática de namespaces via `kubectl config view`
- Edição de profiles direto pelo menu

### 👥 Gerenciamento de Usuários WSL
- Criar usuário com zsh, Oh My Zsh, Powerlevel10k, kubectl, helm
- Remover usuário com limpeza automática de profiles e sudoers
- Resetar senha pelo menu
- Tabela de usuários com grupos e status de profile

### 📊 Histórico de Operações
- Registro de deploys, startups, shutdowns por ambiente
- Histórico paginado com filtro por ambiente
- Integração com orquestradores via hook

### 🔄 Sessões
- Registro de entrada/saída por ambiente
- Duração de cada sessão
- Log persistente em SQLite

---

## Pré-requisitos

- WSL2 (Ubuntu 20.04+)
- Python 3.10+
- Zsh
- `kubectl` (opcional, para health check)

---

## Instalação

```bash
# 1. Baixe e descompacte
cd /tmp && tar -xzf envctl.tar.gz

# 2. Copie para /opt
sudo cp -r /tmp/envctl/. /opt/envctl/
sudo chmod -R 755 /opt/envctl

# 3. Crie o symlink global
sudo ln -sf /opt/envctl/envctl.py /usr/local/bin/envctl

# 4. Execute o instalador
sudo bash /opt/envctl/install.sh
```

O instalador faz automaticamente:
- Detecta todos os usuários WSL em `/home/`
- Lê kubeconfigs de cada usuário e extrai namespace/cluster
- Gera profiles YAML para cada ambiente
- Configura sudoers para troca de contexto
- Instala scripts globais `create-user-wsl` e `remove-user-wsl`
- Adiciona snippet no `.zshrc` do usuário gerenciador

---

## Uso

```bash
# Abre o EnvCtl
envctl
```

### Menu Principal

```
⚡ EnvCtl  —  DevOps Environment Control

  [01]  Gerenciar ambientes
  [02]  Gerenciar usuários WSL
  [03]  Sincronizar profiles
  [q]   Sair
```

### Gerenciar Ambientes

```
  [01-N]  Entrar no ambiente
  [e]     Editar profile
  [h]     Histórico de operações
  [s]     Sessões
  [r]     Atualizar
  [q]     Sair
```

### Gerenciar Usuários

```
  [c]  Criar usuário WSL
  [r]  Remover usuário
  [p]  Resetar senha
  [q]  Voltar
```

### Scripts standalone

```bash
# Criar usuário (qualquer usuário pode chamar — eleva para root automaticamente)
create-user-wsl

# Remover usuário
remove-user-wsl
```

---

## Estrutura do Projeto

```
/opt/envctl/
├── envctl.py               # Entrypoint
├── install.sh              # Instalador
├── requirements.txt
├── profiles/               # YAML por ambiente
│   ├── netwin.yaml
│   ├── vtal.yaml
│   ├── oracle.yaml
│   └── ...
├── core/
│   ├── db.py               # SQLite — histórico + sessões
│   ├── profiles.py         # Loader de profiles + health check
│   ├── netwin_hook.py      # Hook para orquestrador Netwin
│   ├── banner.py           # Banner de sessão
│   ├── sync_profiles.py    # Sincronizador de kubeconfigs
│   └── update_profile.py   # Atualizador de profile individual
├── tui/
│   ├── menu.py             # Menu principal
│   └── app.py              # Painel de ambientes
└── scripts/
    ├── create-user-wsl.sh  # Criação de usuário
    └── remove-user-wsl.sh  # Remoção de usuário

~/.envctl/
├── manager.db              # SQLite — histórico e sessões
└── logs/
```

---

## Profiles

Cada ambiente é definido por um arquivo YAML em `/opt/envctl/profiles/`:

```yaml
name: vtal
description: "Ambiente OpenShift V.Tal — HML-DEV"
category: openshift        # kubernetes | openshift | database | cliente | generic
wsl_user: vtal
color: blue                # purple | blue | amber | teal | coral | gray | green
kubeconfig: /home/vtal/.kube/config
namespace: nossis-netwin-dev-hml
env:
  KUBECONFIG: /home/vtal/.kube/config
  KUBE_NAMESPACE: nossis-netwin-dev-hml
aliases:
  k: kubectl -n nossis-netwin-dev-hml
  kpods: kubectl get pods -n nossis-netwin-dev-hml
  klogs: kubectl logs -n nossis-netwin-dev-hml
integrations:
  orchestrator: false
  oracle: false
  openshift: true
check:
  - type: kubectl
    namespace: nossis-netwin-dev-hml
```

### Adicionar novo ambiente

Crie um arquivo YAML em `/opt/envctl/profiles/` seguindo o template acima, ou use a opção `[03] Sincronizar profiles` no menu principal.

---

## Integração com Orquestrador

Para registrar deploys automaticamente no histórico, use o hook via `.zshrc`:

```bash
# Em vez de:
python3 deploy.py

# Use:
netwin-run deploy.py
netwin-run startup.py
netwin-run shutdown.py
```

Ou chame diretamente:

```bash
python3 -m core.netwin_hook deploy.py
```

---

## Criação de Usuário WSL

O script `create-user-wsl` configura um usuário completo com:

- Zsh como shell padrão
- Oh My Zsh
- Powerlevel10k (com template global se disponível em `/opt/zsh-global/p10k.template`)
- Plugins: `zsh-autosuggestions`, `zsh-syntax-highlighting`, `fzf`
- kubectl, Helm
- Grupos: `sudo`, `dev`, `docker` (se disponível)
- Profile no EnvCtl criado automaticamente
- Sudoers atualizado

```bash
create-user-wsl
```

---

## Dependências Python

```
rich>=13.0.0
pyyaml>=6.0
```

```bash
pip install rich pyyaml
```

---

## Dados e Storage

Todos os dados de runtime ficam em `~/.envctl/` do usuário gerenciador:

| Arquivo | Conteúdo |
|---|---|
| `manager.db` | SQLite com histórico de operações e sessões |
| `logs/` | Logs de sessão |

Os profiles YAML ficam em `/opt/envctl/profiles/` — versionáveis no Git (sem secrets).

---

## Contribuindo

1. Fork o repositório
2. Crie sua branch: `git checkout -b feature/minha-feature`
3. Commit: `git commit -m 'feat: minha feature'`
4. Push: `git push origin feature/minha-feature`
5. Abra um Pull Request

---

## Licença

MIT — veja [LICENSE](LICENSE) para detalhes.

---

## Autor

**Diego Santos** — [@drmsantos](https://github.com/drmsantos)

> Desenvolvido para uso interno na OpenLabs — infraestrutura Kubernetes bare metal com RKE2, OpenShift e Oracle DB.
