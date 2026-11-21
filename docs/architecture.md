# Arquitetura do linux-toolbox

Status: diretrizes de arquitetura e registro do que já está implementado. Cada seção indica o que existe hoje e o que ainda é apenas planejado (ajustes de sistema).

## Objetivo

Separar explicitamente **configurações do usuário** de **ajustes de sistema**, mantendo scripts reutilizáveis, seletivos, auditáveis, idempotentes e reversíveis. O projeto começa com Debian 13, mas não deve pressupor que todas as máquinas tenham KDE, Wayland ou Raspberry Pi.

## Duas categorias de operação

### Configurações pessoais (escopo do usuário)

Exemplos: aliases do Bash, configuração do tmux, preferências do Git e ferramentas de desenvolvimento.

- Alteram, em princípio, apenas arquivos no `$HOME` do usuário que executa o script.
- Não exigem `sudo` como condição geral; permissões administrativas ficam restritas à instalação de pacotes quando necessária.
- Preservam arquivos preexistentes e permitem testar, inspecionar e reverter alterações.
- Podem usar arquivos em `configs/` e instaladores independentes em `scripts/`.

### Configurações de sistema (escopo da máquina)

Exemplos futuros: unidades systemd, regras udev, ajustes de boot, permissões USB e configurações de rede.

- Ficam conceitualmente separadas das preferências pessoais.
- Devem declarar requisitos, distribuição/hardware suportados, arquivos afetados, necessidade de privilégios e impacto operacional.
- Não devem alterar silenciosamente rede, SSH, boot ou serviços ativos, nem reiniciar a máquina sem consentimento específico.
- Devem oferecer simulação sem efeitos colaterais, backup, caminho de reversão e testes adequados.
- A instalação deve continuar **opt-in**, nunca ocorrer por consequência implícita de um perfil genérico.

## Perfis como composição, não duplicação

Os perfis `debian-desktop`, `debian-server` e `raspberry-pi-headless` já existem (ver "Estado da implementação dos perfis"). Um perfil deve **selecionar e combinar** listas de pacotes e tarefas reutilizáveis, não copiar a implementação dos scripts.

Diretrizes:

1. Separar tarefas obrigatórias, recomendadas e opcionais; permitir seleção explícita quando cabível.
2. Mostrar um plano antes de executar, incluindo privilégios e efeitos esperados.
3. Não instalar componentes de desktop em servidor, nem ajustes específicos de hardware fora do hardware correspondente.
4. Evitar executar tudo de uma só vez por padrão. Permitir executar componentes individualmente.
5. Perfis não devem armazenar segredos nem configurações identificáveis de uma máquina.

## Estado da implementação dos perfis

Os perfis foram implementados como arquivos de dados `profiles/NOME.conf` (seções `[perfil]`, `[pacotes]` e `[usuario]`, um componente por linha com seu nível), e não como subdiretórios. Quem os aplica é `scripts/profile.sh`, que compõe os scripts existentes, mostra o plano antes, separa passos `[sudo]` de passos `[usuário]`, aceita `--dry-run`, `--only`, `--with` e `--user-only`, e verifica o requisito de hardware/sistema (`requer = debian, raspberry-pi`), sem opção para ignorá-lo. Os arquivos `.conf` são apenas dados: são lidos linha a linha, nunca executados. Ainda não há lista de pacotes própria de servidor, e os perfis não fazem nenhum ajuste de sistema.

Para testar sem o hardware real, o `profile.sh` aceita `TOOLBOX_TEST_OS_RELEASE_FILE` e `TOOLBOX_TEST_DT_MODEL_FILE`. Essas variáveis contornam a verificação de requisitos; por isso, enquanto definidas, todo comando exibe o aviso `SIMULAÇÃO ATIVA`.

## Organização

Implementado:

```text
linux-toolbox/
├── bootstrap.sh         # menu seletivo
├── configs/             # arquivos de configuração pessoais
├── docs/                # documentação (este arquivo)
├── packages/            # listas de pacotes apt
├── profiles/            # perfis de máquina: um arquivo .conf (dados) por perfil
│   ├── debian-desktop.conf
│   ├── debian-server.conf
│   └── raspberry-pi-headless.conf
├── scripts/             # tarefas independentes, profile.sh e biblioteca mínima (lib.sh)
└── tests/               # testes em Bash puro
```

Planejado (ilustrativo, ainda não existe):

```text
linux-toolbox/
└── system/              # ajustes privilegiados por assunto
    ├── systemd/
    ├── udev/
    └── boot/
```

O desenho de `system/` é **ilustrativo**; não criar diretórios vazios ou scripts fictícios apenas para corresponder a ele. O `bootstrap.sh` continua sendo a interface seletiva.

## Regras de evolução

- Antes de criar um script, verifique se uma operação existente resolve a necessidade.
- Prefira mudanças pequenas, com testes próximos ao comportamento modificado e documentação suficiente para reprodução.
- Para configurações pessoais, considere que links simbólicos para o clone deixam de funcionar se o repositório for movido.
- Não altere `~/.gitconfig` ou identidade/autenticação Git (nome, email, credenciais, assinatura) sem escolha expressa. Em especial, não comite dados pessoais no repositório público.
- Arquivos temporários de scripts que substituem arquivos do usuário devem ser criados em um diretório privado (`mktemp -d`) no mesmo diretório do destino, para manter o `rename` atômico. Nunca use nomes previsíveis como `ARQUIVO.tmp.$$`: um arquivo ou link preexistente nesse caminho seria reutilizado, sobrescrito ou apagado. O `trap` deve remover apenas o que o próprio script criou.
- Ganchos que simulam o ambiente em testes não são um recurso de uso: use o prefixo `TOOLBOX_TEST_` e exiba um aviso destacado enquanto estiverem ativos.
- Não adote GNU Stow, novos frameworks ou outros mecanismos de perfis além de `profiles/*.conf` sem demonstrar benefício concreto.
- Acompanhe decisões futuras no próprio projeto; este documento registra **princípios**, não autoriza implementação automática.

## Etapas

Concluídas:

1. Configuração pessoal do Git (`setup-git.sh`), sem impor identidade, tokens ou política de autenticação.
2. Perfis compostos por ambiente, com execução seletiva (`profile.sh` e `profiles/*.conf`).

Em aberto:

3. Catálogo de ajustes de sistema (systemd, udev, boot), conforme casos reais.
4. Integração opcional de clipboard do tmux e avaliação futura de GNU Stow.
5. Lista de pacotes própria para servidor, quando houver itens concretos.

Revisar este documento quando uma implementação estabelecer uma decisão diferente, indicando o motivo.
