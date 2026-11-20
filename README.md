# linux-toolbox

Scripts e configurações reutilizáveis para máquinas Linux, inicialmente Debian 13.

## Uso

```bash
git clone https://github.com/maujabur/linux-toolbox.git
cd linux-toolbox
bash bootstrap.sh
```

O menu permite instalar ferramentas, configurar aliases do Bash e configurar o tmux separadamente.

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
