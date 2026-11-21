# linux-toolbox

Scripts e configurações reutilizáveis para máquinas Linux, inicialmente Debian 13.

## Uso

```bash
git clone https://github.com/maujabur/linux-toolbox.git
cd linux-toolbox
bash bootstrap.sh
```

O menu permite instalar ferramentas, configurar aliases do Bash, o tmux e o Git, e restaurar backups, cada item separadamente. Ele volta ao menu após cada operação; `0` ou Ctrl+D encerra. Depois de cada operação o menu **pausa** (`Pressione Enter para voltar ao menu...`), para que o resultado não seja coberto pelo menu seguinte.

O resultado final de cada script aparece em destaque, entre linhas de `=` (verde em sucesso, amarelo em aviso e vermelho em erro ou conflito), incluindo o **PRÓXIMO PASSO** quando houver um, como `source ~/.bashrc` depois de configurar os aliases. As cores só são usadas em terminal e podem ser desativadas com `NO_COLOR=1`.

Todos os scripts que alteram o sistema aceitam `--dry-run`, que apenas mostra o que seria feito (sem criar diretórios, arquivos, backups nem executar `sudo`/`apt-get`). `bootstrap.sh --dry-run` aplica isso a todas as opções do menu.

### Ferramentas para agentes de programação

A opção **6 — Instalar ferramentas para agentes** instala o perfil `packages/agents.txt` com `ripgrep`, `fd-find`, `jq`, `yq`, `sed`, `gawk`, `patch`, `diffutils`, `findutils`, `file`, `shellcheck` e `shfmt`.

Também pode ser executada diretamente:

```bash
bash scripts/install-packages.sh agents
```

A disponibilidade desses 12 pacotes no repositório do Debian 13 foi conferida com `apt-cache policy` (sem instalar nada).

No Debian, o comando fornecido por `fd-find` se chama `fdfind`. Após instalar os pacotes, o perfil executa `scripts/setup-fd.sh`, que cria o link `~/.local/bin/fd` para `fdfind`, sem substituir arquivos existentes. Resultados possíveis:

- código 0: link criado agora ou já configurado;
- código 2: **conflito**, pois `~/.local/bin/fd` já existe e não é o link esperado. Nada é alterado e o `fd` não é configurado. Durante a instalação do perfil isso vira apenas um aviso.

Para chamar `fd` diretamente, `~/.local/bin` precisa constar no `PATH`. Se não estiver, use `fdfind`.

O pacote `yq` do Debian 13 (versão 3.x, de kislyuk) é um wrapper em Python para o `jq` e usa a sintaxe do `jq`. Ele **não** é o `yq` em Go (mikefarah), de sintaxe diferente. O perfil não instala os agentes de IA propriamente ditos.

### Instalação de pacotes

```bash
bash scripts/install-packages.sh [--dry-run] [--yes] [perfil]
```

O script lista os pacotes e pede confirmação `[s/N]` antes de rodar `apt-get`. `--yes` dispensa a pergunta (uso não interativo). `sudo` é usado apenas nos comandos `apt-get`, e somente se o usuário não for root.

> Leia os scripts antes de executá-los.

### Configuração do Git

```bash
bash scripts/setup-git.sh [--dry-run]
```

Adiciona ao **topo** de `~/.gitconfig` (ou de `~/.config/git/config`, se for o único existente) um bloco `[include]` apontando para `configs/git/gitconfig`. Como no Git o que vem depois prevalece, as suas configurações existentes têm prioridade sobre as do repositório. Um backup com timestamp é criado antes, e o arquivo novo só substitui o original (por `rename`) depois de validado.

O que o arquivo inclui:

- aliases `st` (`status -sb`), `co`, `br`, `lg` (histórico compacto em grafo), `last` e `unstage`;
- `init.defaultBranch = main`;
- `pull.ff = only`: o `git pull` recusa um histórico divergido em vez de criar merge ou rebase sem perguntar;
- `commit.verbose = true` e `branch.sort = -committerdate` (apenas exibição).

**Não** define nome, e-mail, credenciais, assinatura de commits nem tokens: configure-os você mesmo em `~/.gitconfig`. Também não ativa `help.autocorrect`, `fetch.prune`, `rebase.autoStash` ou qualquer opção que altere silenciosamente operações destrutivas.

Se o arquivo de configuração for um link simbólico, o script **não altera nada** (código de saída 2, `CONFLITO`) e mostra o comando manual. O include aponta para este clone; se movê-lo, refaça a configuração. Para reverter, use `restore.sh git`. Se o `~/.gitconfig` não existia antes, não há backup para restaurar: remova o arquivo.

### Backups e restauração

Antes de alterar `~/.bashrc` ou `~/.config/tmux/tmux.conf`, os scripts criam `ARQUIVO.bak.AAAAMMDD_HHMMSS` (com sufixo `.1`, `.2`, ... se o nome já existir). Backups nunca são sobrescritos nem apagados.

Para restaurar:

```bash
bash scripts/restore.sh bash   # ou: tmux, git
bash scripts/restore.sh bash --backup ~/.bashrc.bak.20260101_120000
bash scripts/restore.sh bash --dry-run
```

O script informa o backup selecionado (o mais recente, por padrão), pede confirmação `[s/N]` (ou `--yes`) e guarda o estado atual em um novo backup antes de substituí-lo. A troca usa `rename` atômico: se algo falhar antes dela, o arquivo original continua intacto.

O link do tmux aponta para este clone; se mover ou apagar o clone, refaça a configuração ou restaure um backup.

## Testes

```bash
bash tests/run.sh [filtro]
```

Os testes são em Bash puro e não alteram a máquina: usam `HOME` temporário e simulam `sudo`, `apt-get` e `fdfind`. Verificam sintaxe, `shellcheck` e `shfmt -i 2 -ci` (quando instalados; `REQUIRE_LINT=1` os torna obrigatórios), permissões, idempotência, backups, `--dry-run` sem efeitos colaterais e a segurança da restauração. O workflow `.github/workflows/tests.yml` executa a suíte em pushes e pull requests.

## Arquitetura

A separação entre configurações pessoais, ajustes de sistema e perfis futuros está documentada em [docs/architecture.md](docs/architecture.md). Esse documento estabelece diretrizes, não funcionalidades já implementadas.

## Organização

- `configs/`: configurações versionadas
- `packages/`: listas de pacotes apt
- `scripts/`: operações independentes (`lib.sh` reúne as funções compartilhadas)
- `tests/`: testes automatizados
- `profiles/`: combinações por ambiente (futuro)

## Segurança

Não inclua senhas, chaves privadas, tokens ou arquivos pessoais com credenciais neste repositório público. O `.gitignore` é uma proteção auxiliar, não substitui a revisão de cada commit.

## Princípios

Scripts idempotentes, cópia de segurança de arquivos preexistentes e instalação seletiva.
