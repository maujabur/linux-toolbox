# linux-toolbox

Scripts e configurações reutilizáveis para máquinas Linux, inicialmente Debian 13.

## Uso

```bash
git clone https://github.com/maujabur/linux-toolbox.git
cd linux-toolbox
bash bootstrap.sh
```

O menu permite instalar ferramentas, configurar aliases do Bash, o tmux e o Git, e restaurar backups, cada item separadamente. Ele volta ao menu após cada operação; `0` ou Ctrl+D encerra. Depois de cada operação o menu **pausa** (`Enter = voltar ao menu, q = sair`), para que o resultado não seja coberto pelo menu seguinte; `q` encerra o script ali mesmo. As opções de restauração ficam no submenu **8) Restaurar backups...** (bash, tmux ou Git; `0` volta).

O resultado final de cada script aparece em destaque, entre linhas de `=` (verde em sucesso, amarelo em aviso e vermelho em erro ou conflito), incluindo o **PRÓXIMO PASSO** quando houver um, como `source ~/.bashrc` depois de configurar os aliases. As cores só são usadas em terminal e podem ser desativadas com `NO_COLOR=1`.

Todos os scripts que alteram o sistema aceitam `--dry-run`, que apenas mostra o que seria feito (sem criar diretórios, arquivos, backups nem executar `sudo`/`apt-get`). `bootstrap.sh --dry-run` aplica isso a todas as opções do menu.

### Ferramentas para agentes de programação

A opção **6 — Instalar ferramentas para agentes** instala a lista `packages/agents.txt` com `ripgrep`, `fd-find`, `jq`, `yq`, `sed`, `gawk`, `patch`, `diffutils`, `findutils`, `file`, `shellcheck` e `shfmt`.

Também pode ser executada diretamente:

```bash
bash scripts/install-packages.sh agents
```

A disponibilidade desses 12 pacotes no repositório do Debian 13 foi conferida com `apt-cache policy` (sem instalar nada).

No Debian, o comando fornecido por `fd-find` se chama `fdfind`. Após instalar a lista `agents`, o instalador executa `scripts/setup-fd.sh`, que cria o link `~/.local/bin/fd` para `fdfind`, sem substituir arquivos existentes. Resultados possíveis:

- código 0: link criado agora ou já configurado;
- código 2: **conflito**, pois `~/.local/bin/fd` já existe e não é o link esperado. Nada é alterado e o `fd` não é configurado. Durante a instalação da lista isso vira apenas um aviso.

Para chamar `fd` diretamente, `~/.local/bin` precisa constar no `PATH`. Se não estiver, use `fdfind`.

O pacote `yq` do Debian 13 (versão 3.x, de kislyuk) é um wrapper em Python para o `jq` e usa a sintaxe do `jq`. Ele **não** é o `yq` em Go (mikefarah), de sintaxe diferente. A lista não instala os agentes de IA propriamente ditos.

### Instalação de pacotes

```bash
bash scripts/install-packages.sh [--dry-run] [--yes] [lista]
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

### Perfis de máquina

Um perfil **combina** componentes que já existem (listas de pacotes e scripts de configuração); não duplica nenhum script. Estão em `profiles/*.conf`:

| Perfil | Para | Requisito |
|---|---|---|
| `debian-desktop` | Debian com desktop KDE | Debian |
| `debian-server` | Debian sem interface gráfica | Debian |
| `raspberry-pi-headless` | Raspberry Pi sem desktop | Debian/Raspberry Pi OS em um Raspberry Pi (checado em `/proc/device-tree/model`) |

```bash
bash scripts/profile.sh list
bash scripts/profile.sh show debian-desktop                 # só mostra o plano
bash scripts/profile.sh run  debian-desktop                 # plano + confirmação [s/N]
bash scripts/profile.sh run  debian-desktop --with agents   # inclui opcionais
bash scripts/profile.sh run  debian-desktop --only git,tmux # só esses componentes
bash scripts/profile.sh run  debian-desktop --user-only     # nada que use sudo
bash scripts/profile.sh run  debian-desktop --dry-run
```

Também está no menu, opção **10**. O perfil mostra o plano antes (passos `[sudo]` de pacotes e passos `[usuário]` no seu `HOME`, mais o espaço livre em `/`) e só executa depois da confirmação. Os pacotes são instalados antes dos ajustes de usuário. Os passos continuam sendo os mesmos scripts, então mantêm backup, idempotência e `--dry-run`.

- **Níveis:** `obrigatorio` e `recomendado` entram por padrão; `opcional` só com `--with NOME`. `--only` executa somente os componentes indicados, de qualquer nível.
- **Falhas:** o perfil para no primeiro passo que falhar e informa o que foi concluído e o que ficou pendente. Um conflito (código 2) em um passo não impede os seguintes; no fim o perfil sai com código 2.
- **Requisitos:** um perfil não se aplica se a máquina não atender (por exemplo, o do Raspberry Pi em outro hardware). Não há opção para forçar.
- **O que não fazem:** os perfis não definem identidade do Git, não configuram SSH, serviços, rede nem boot (isso é ajuste de sistema, ver `docs/architecture.md`). Ainda não há lista de pacotes própria de servidor.

Formato de um perfil (apenas dados, nunca executado; comentários com `#`):

```ini
[perfil]
descricao = Debian com desktop KDE
requer    = debian              # debian e/ou raspberry-pi, separados por vírgula

[pacotes]                        # packages/NOME.txt, instalados com apt-get (sudo)
base        = obrigatorio
desktop     = recomendado
agents      = opcional

[usuario]                        # bash, tmux, git ou fd; só no seu HOME
bash = recomendado
```

Para criar um perfil, copie um existente em `profiles/`; `profile.sh show NOME` valida o arquivo e aponta a linha de qualquer erro.

### Atualizar este clone

Opção **9** do menu, ou:

```bash
bash scripts/update.sh [--dry-run] [--yes]
```

Atualiza o clone a partir do remoto configurado (`origin`, normalmente o GitHub) com `git fetch` e `git merge --ff-only`. O script **não reescreve nem descarta nada**:

- mostra o remoto, os commits novos e os arquivos alterados, e pede confirmação `[s/N]` (`--yes` dispensa). Leia as alterações antes de usar os scripts atualizados;
- recusa (código 2, `CONFLITO`) se houver alterações locais não commitadas ou se o histórico local e o remoto divergirem; se só houver commits locais à frente, informa que não há o que atualizar;
- `--dry-run` consulta o remoto com `git ls-remote` e não grava nada, nem dentro de `.git`;
- usa o remoto que o clone já tem configurado; o endereço não está fixo no script;
- se a pasta **não for um clone git** (por exemplo, extraída de um tarball, ou em uma máquina sem `git`), não tenta baixar nada: mostra como obter o repositório padrão, com `git clone https://github.com/maujabur/linux-toolbox.git` ou, sem `git`, com o comando `curl` do tarball e `tar xzf`;
- ao terminar, mostra a versão anterior e o comando para voltar a ela. Pelo menu, o bootstrap encerra após uma atualização e pede para ser executado de novo.

Exige rede e `git`, mas não `sudo`.

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

Para simular o sistema e o hardware (por exemplo, um Raspberry Pi), os testes usam `TOOLBOX_TEST_OS_RELEASE_FILE` e `TOOLBOX_TEST_DT_MODEL_FILE`, que fazem o `profile.sh` ler arquivos falsos. **Não são um recurso de uso:** quem as define contorna a verificação de requisitos dos perfis. Por isso, enquanto estiverem definidas, todo comando do `profile.sh` mostra o aviso `SIMULAÇÃO ATIVA`; se aparecer fora de um teste, execute `unset TOOLBOX_TEST_OS_RELEASE_FILE TOOLBOX_TEST_DT_MODEL_FILE`.

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
