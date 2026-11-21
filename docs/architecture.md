# Arquitetura do linux-toolbox

Status: diretrizes de arquitetura e proposta de evolução, não especificação de funcionalidades já implementadas.

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

Perfis futuros incluem `debian-desktop`, `debian-server` e `raspberry-pi`. Um perfil deve **selecionar e combinar** listas de pacotes e tarefas reutilizáveis, não copiar a implementação dos scripts.

Diretrizes:

1. Separar tarefas obrigatórias, recomendadas e opcionais; permitir seleção explícita quando cabível.
2. Mostrar um plano antes de executar, incluindo privilégios e efeitos esperados.
3. Não instalar componentes de desktop em servidor, nem ajustes específicos de hardware fora do hardware correspondente.
4. Evitar executar tudo de uma só vez por padrão. Permitir executar componentes individualmente.
5. Perfis não devem armazenar segredos nem configurações identificáveis de uma máquina.

## Estado da implementação dos perfis

Os perfis foram implementados como arquivos de dados `profiles/NOME.conf` (seções `[perfil]`, `[pacotes]` e `[usuario]`, um componente por linha com seu nível), e não como subdiretórios. Quem os aplica é `scripts/profile.sh`, que compõe os scripts existentes, mostra o plano antes, separa passos `[sudo]` de passos `[usuário]`, aceita `--dry-run`, `--only`, `--with` e `--user-only`, e verifica o requisito de hardware/sistema. A árvore abaixo continua sendo ilustrativa para `system/`, que ainda não existe.

## Organização sugerida (futura)

```text
linux-toolbox/
├── configs/             # arquivos de configuração pessoais
├── packages/            # conjuntos reutilizáveis de pacotes
├── scripts/             # tarefas independentes e biblioteca mínima
├── profiles/            # composições declarativas por ambiente (futuro)
│   ├── debian-desktop/
│   ├── debian-server/
│   └── raspberry-pi/
└── system/              # ajustes privilegiados por assunto (futuro)
    ├── systemd/
    ├── udev/
    └── boot/
```

A árvore acima é **ilustrativa**; não criar diretórios vazios ou scripts fictícios apenas para corresponder ao desenho. O `bootstrap.sh` continua sendo a interface seletiva existente.

## Regras de evolução

- Antes de criar um script, verifique se uma operação existente resolve a necessidade.
- Prefira mudanças pequenas, com testes próximos ao comportamento modificado e documentação suficiente para reprodução.
- Para configurações pessoais, considere que links simbólicos para o clone deixam de funcionar se o repositório for movido.
- Não altere `~/.gitconfig` ou identidade/autenticação Git (nome, email, credenciais, assinatura) sem escolha expressa. Em especial, não comite dados pessoais no repositório público.
- Não adote GNU Stow, novos frameworks ou mecanismos de perfis sem demonstrar benefício concreto.
- Acompanhe decisões futuras no próprio projeto; este documento registra **princípios**, não autoriza implementação automática.

## Próximas etapas discutidas

1. Configuração pessoal do Git, sem impor identidade, tokens ou política de autenticação.
2. Perfis compostos por ambiente, com execução seletiva.
3. Catálogo de ajustes de sistema (systemd, udev, boot), conforme casos reais.
4. Integração opcional de clipboard do tmux e avaliação futura de GNU Stow.

Revisar este documento quando uma implementação estabelecer uma decisão diferente, indicando o motivo.
