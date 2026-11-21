# AGENTS.md — linux-toolbox

## Objetivo

Este repositório contém configurações pessoais e scripts reutilizáveis para Linux, inicialmente Debian 13 (incluindo desktop KDE e instalações sem interface gráfica). Priorize soluções simples, auditáveis e fáceis de manter. Ele é público: não introduza informações sensíveis.

## Estrutura

- `configs/`: arquivos de configuração versionados, sem dados privados.
- `scripts/`: instaladores e ajustes independentes.
- `packages/`: listas de pacotes APT, um pacote por linha.
- `scripts/lib.sh`: funções compartilhadas (`log`, `die`, `confirm`, `backup_copy`); carregado com `source`, não é executável. Mantenha-o pequeno.
- `tests/`: testes em Bash puro (`bash tests/run.sh`); novos casos vão em `tests/cases/*.sh` como funções `test_*`.
- `bootstrap.sh`: menu de entrada; não deve fazer alterações sem a seleção do usuário.
- `profiles/`: perfis de máquina (`debian-desktop`, `debian-server`, `raspberry-pi-headless`) em arquivos `.conf` de dados, aplicados por `scripts/profile.sh`. Um perfil só combina componentes existentes (listas em `packages/` e scripts em `scripts/`); não copie lógica para ele nem inclua ajustes de sistema (systemd, udev, boot, SSH) sem um caso concreto.

Antes de editar, leia os arquivos relacionados e preserve as convenções existentes.

## Ferramentas de trabalho dos agentes

- A lista `packages/agents.txt` instala utilitários de pesquisa e validação; não instala runtimes, Docker ou agentes de IA.
- Prefira `rg` para localizar textos e referências e `fd` para localizar arquivos, quando disponíveis. Use `grep` e `find` como alternativas portáveis.
- No Debian, o pacote `fd-find` fornece `fdfind`; o instalador da lista tenta criar `~/.local/bin/fd` sem sobrescrever nada.
- Use `jq` para JSON e `yq` para YAML, conferindo a sintaxe da implementação instalada. Não trate os dois comandos como equivalentes.
- Prefira edições pequenas e contextualizadas: antes de editar, localize o trecho e verifique o resultado com `git diff`. Não use substituições globais com `sed` sem validar o escopo.
- Para scripts Bash, execute `bash -n`, `shellcheck` e, se houver reformatação, confira o resultado do `shfmt`.
- Não presuma que essas ferramentas estejam disponíveis em todo sistema; degrade de forma graciosa ou documente a dependência.

## Regras para scripts

1. Use Bash nos scripts existentes, com `#!/usr/bin/env bash` e `set -euo pipefail`.
2. Use caminhos relativos à localização do script, não ao diretório atual do terminal. Coloque aspas nas expansões de variáveis que representem caminhos.
3. Torne as operações idempotentes: execuções repetidas não devem duplicar linhas, links ou recursos.
4. Antes de alterar arquivos existentes do usuário, preserve uma cópia com timestamp `YYYYMMDD_HHMMSS`. Não substitua arquivos silenciosamente nem apague backups.
5. Não use `sudo` para executar o script inteiro; eleve privilégios apenas nos comandos que precisarem deles.
6. Não execute alterações destrutivas, reinicializações, mudanças de rede/SSH, nem instalação em massa sem solicitação explícita. Prefira etapas seletivas e explique efeitos colaterais.
7. Não use `curl | bash`, `wget | sh` ou execução de código remoto sem revisão explícita. Evite dependências desnecessárias.
8. Para ajustes específicos de distribuição ou hardware, detecte e documente os requisitos; não suponha que todo Linux seja Debian, Raspberry Pi ou Wayland.
9. Mantenha comentários e documentação em português claro. Use nomes de arquivos, opções e comandos que sigam as convenções do ecossistema.

## Segurança e privacidade

- Nunca adicione senhas, tokens, chaves privadas, certificados pessoais, arquivos `.env` reais, IDs internos, endereços privados de infraestrutura ou dados de usuários.
- Não considere o `.gitignore` garantia de sigilo: revise o conteúdo antes de cada commit.
- Não incorpore conteúdo sensível mesmo em exemplos, comentários, histórico de commits ou testes.
- Não defina nome, e-mail, credenciais, assinatura de commits ou tokens do Git em `configs/git/`; esses dados ficam no `~/.gitconfig` do usuário.
- Não altere a visibilidade do repositório nem publique informações fornecidas apenas para diagnóstico.

## Alterações e validação

- Prefira alterações pequenas, isoladas e fáceis de reverter. Não reformate arquivos que não sejam relacionados à tarefa.
- Ao adicionar uma função, atualize o README e o menu `bootstrap.sh` somente quando fizer sentido disponibilizá-la ali.
- Valide a sintaxe com `bash -n` para cada script Bash alterado e, quando disponível, use `shellcheck`.
- Scripts que alteram o sistema devem aceitar `--dry-run` sem nenhum efeito colateral (sem criar diretórios, arquivos ou backups, nem chamar `sudo`) e usar `backup_copy` de `scripts/lib.sh` para backups. Execute `bash tests/run.sh` antes de commitar; o estilo é `shfmt -i 2 -ci`.
- Em testes, use diretórios temporários e evite modificar a máquina do operador. Não declare que testou no Debian, no KDE ou em hardware se não testou.
- Descreva o que foi alterado, como testar, quais permissões são necessárias e como reverter.
- Nunca faça push, merge, force-push ou outras alterações remotas sem autorização correspondente ao pedido do usuário.

## Convenções de Git

- Commits descritivos e pequenos, preferencialmente no padrão `feat:`, `fix:`, `docs:`, `chore:`.
- Se houver arquivos de revisão ou backup incluídos deliberadamente no trabalho, use timestamp em vez de sufixos ambíguos como `final` ou `revisado`.
- Mantenha compatibilidade com a estrutura já existente, salvo solicitação para refatorar.

## Prioridades

Segurança e preservação dos dados > previsibilidade e reversibilidade > simplicidade > conveniência. Na dúvida sobre uma mudança com impacto no sistema, não a execute automaticamente: apresente o efeito e solicite decisão.
