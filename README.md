# linux-toolbox

Scripts e configurações reutilizáveis para máquinas Linux, inicialmente Debian 13.

## Uso

```bash
git clone https://github.com/maujabur/linux-toolbox.git
cd linux-toolbox
bash bootstrap.sh
```

O menu permite instalar ferramentas, configurar aliases do Bash e configurar o tmux separadamente.

### Ferramentas para agentes de programação

A opção **6 — Instalar ferramentas para agentes** instala o perfil `packages/agents.txt` com `ripgrep`, `fd-find`, `jq`, `yq`, `sed`, `gawk`, `patch`, `diffutils`, `findutils`, `file`, `shellcheck` e `shfmt`.

Também pode ser executada diretamente:

```bash
bash scripts/install-packages.sh agents
```

No Debian, o comando fornecido por `fd-find` se chama `fdfind`. Após instalar os pacotes, o perfil executa `scripts/setup-fd.sh`, que tenta criar um link `~/.local/bin/fd` para `fdfind`, sem substituir arquivos existentes. Para chamar `fd` diretamente, `~/.local/bin` precisa constar no `PATH`. Se não estiver, use `fdfind`.

O pacote Debian `yq` pode ter sintaxe diferente de outras implementações de `yq`. O perfil não instala os agentes de IA propriamente ditos.

> Leia os scripts antes de executá-los. As operações que usam apt solicitam sudo.

## Organização

- `configs/`: configurações versionadas
- `packages/`: listas de pacotes apt
- `scripts/`: operações independentes
- `profiles/`: combinações por ambiente (futuro)

## Segurança

Não inclua senhas, chaves privadas, tokens ou arquivos pessoais com credenciais neste repositório público. O `.gitignore` é uma proteção auxiliar, não substitui a revisão de cada commit.

## Princípios

Scripts idempotentes, cópia de segurança de arquivos preexistentes e instalação seletiva.
