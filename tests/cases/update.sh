# shellcheck shell=bash
# shellcheck disable=SC2016
# Testes de scripts/update.sh. Usam um remoto local temporário (repositório
# bare) com uma cópia do projeto: não acessam a rede nem alteram este clone.

# git_t ARGS...: git com HOME temporário e identidade fictícia (só para os commits de teste).
git_t() {
  env "${CLEAN_ENV[@]}" HOME="$HOME_DIR" GIT_AUTHOR_NAME=teste GIT_AUTHOR_EMAIL=teste@example.invalid \
    GIT_COMMITTER_NAME=teste GIT_COMMITTER_EMAIL=teste@example.invalid git "$@"
}

# make_clone: cria ORIGIN (bare), SEED (para publicar versões) e CLONE (cópia do projeto).
make_clone() {
  new_env
  ORIGIN="$ENV_DIR/origin.git"
  SEED="$ENV_DIR/seed"
  CLONE="$ENV_DIR/clone"
  mkdir -p "$SEED"
  (cd "$ROOT" && git ls-files -co --exclude-standard -z | xargs -0 cp -p --parents -t "$SEED")
  git_t init -q --bare -b main "$ORIGIN"
  git_t -C "$SEED" init -q -b main
  git_t -C "$SEED" add -A
  git_t -C "$SEED" commit -q -m semente
  git_t -C "$SEED" remote add origin "$ORIGIN"
  git_t -C "$SEED" push -q -u origin main
  git_t clone -q "$ORIGIN" "$CLONE"
}

# publish_new_version: publica um commit novo no remoto e imprime o hash.
publish_new_version() {
  printf 'novo\n' >"$SEED/novo.txt"
  git_t -C "$SEED" add novo.txt
  git_t -C "$SEED" commit -q -m "versão nova"
  git_t -C "$SEED" push -q origin main
  git_t -C "$SEED" rev-parse HEAD
}

head_of() { git_t -C "$1" rev-parse HEAD; }

test_update_already_up_to_date() {
  make_clone
  local out rc=0
  out="$(in_env bash "$CLONE/scripts/update.sh" 2>&1)" || rc=$?
  assert_eq "sai com 0" "0" "$rc"
  assert_contains "informa já atualizado" "$out" "Já atualizado"
  assert_contains "explica que não há o que fazer" "$out" "Nada a fazer: o clone já está na versão mais recente."
}

test_update_applies_with_yes() {
  make_clone
  local new out rc=0
  new="$(publish_new_version)"
  out="$(in_env bash "$CLONE/scripts/update.sh" --yes 2>&1)" || rc=$?
  assert_eq "sai com 0" "0" "$rc"
  assert_eq "HEAD avançou para o commit remoto" "$new" "$(head_of "$CLONE")"
  check "arquivo novo chegou" test -f "$CLONE/novo.txt"
  assert_contains "mostra os commits novos" "$out" "versão nova"
  assert_contains "mostra os arquivos alterados" "$out" "novo.txt"
  assert_contains "resultado destacado" "$out" "Atualizado: "
  assert_contains "sugere executar o bootstrap de novo" "$out" "PRÓXIMO PASSO: execute o bootstrap novamente"
  assert_contains "informa como voltar à versão anterior" "$out" "reset --hard"
  assert_eq "árvore limpa" "" "$(git_t -C "$CLONE" status --porcelain)"
}

test_update_requires_confirmation() {
  make_clone
  local before rc=0
  publish_new_version >/dev/null
  before="$(head_of "$CLONE")"
  in_env bash "$CLONE/scripts/update.sh" >/dev/null 2>&1 || rc=$?
  assert_eq "sem entrada (EOF) cancela com 1" "1" "$rc"
  assert_eq "HEAD inalterado sem confirmação" "$before" "$(head_of "$CLONE")"
  rc=0
  in_env_input 'n\n' bash "$CLONE/scripts/update.sh" >/dev/null 2>&1 || rc=$?
  assert_eq "resposta n cancela" "1" "$rc"
  assert_eq "HEAD inalterado após recusar" "$before" "$(head_of "$CLONE")"
  in_env_input 's\n' bash "$CLONE/scripts/update.sh" >/dev/null 2>&1
  check "resposta s atualiza" test -f "$CLONE/novo.txt"
}

test_update_dry_run_has_no_side_effects() {
  make_clone
  local before out
  before="$(snapshot "$CLONE")"
  out="$(in_env bash "$CLONE/scripts/update.sh" --dry-run 2>&1)"
  assert_eq "dry-run (remoto igual) não altera o clone" "$before" "$(snapshot "$CLONE")"
  assert_contains "informa mesma versão" "$out" "mesma versão"
  publish_new_version >/dev/null
  before="$(snapshot "$CLONE")"
  out="$(in_env bash "$CLONE/scripts/update.sh" --dry-run 2>&1)"
  assert_eq "dry-run (remoto à frente) não altera o clone, nem .git" "$before" "$(snapshot "$CLONE")"
  assert_contains "informa que o remoto difere" "$out" "diferente da sua versão"
  assert_contains "termina com aviso destacado" "$out" "[dry-run] Nenhuma alteração foi feita."
  check_not "arquivo novo não chegou" test -f "$CLONE/novo.txt"
}

test_update_refuses_local_changes() {
  make_clone
  publish_new_version >/dev/null
  printf '# alteração local\n' >>"$CLONE/README.md"
  local before rc=0 err
  before="$(snapshot "$CLONE")"
  err="$(in_env bash "$CLONE/scripts/update.sh" --yes 2>&1)" || rc=$?
  assert_eq "alterações locais saem com 2" "2" "$rc"
  assert_contains "mensagem indica CONFLITO" "$err" "CONFLITO"
  assert_eq "nada foi alterado" "$before" "$(snapshot "$CLONE")"
}

test_update_ahead_and_diverged() {
  make_clone
  local before rc=0 out
  printf 'local\n' >"$CLONE/local.txt"
  git_t -C "$CLONE" add local.txt
  git_t -C "$CLONE" commit -q -m local
  before="$(head_of "$CLONE")"
  out="$(in_env bash "$CLONE/scripts/update.sh" --yes 2>&1)" || rc=$?
  assert_eq "commits locais à frente: sai com 0" "0" "$rc"
  assert_contains "informa que não há o que atualizar" "$out" "Nada a atualizar"
  assert_contains "explica que não há versão nova" "$out" "Nada a fazer: não há versão nova a aplicar."
  assert_eq "HEAD inalterado" "$before" "$(head_of "$CLONE")"
  publish_new_version >/dev/null
  rc=0
  out="$(in_env bash "$CLONE/scripts/update.sh" --yes 2>&1)" || rc=$?
  assert_eq "histórico divergente sai com 2" "2" "$rc"
  assert_contains "informa a divergência" "$out" "divergiram"
  assert_eq "HEAD inalterado após divergência" "$before" "$(head_of "$CLONE")"
  check "commit local preservado" test -f "$CLONE/local.txt"
}

test_update_requires_git_clone_and_upstream() {
  new_env
  local rc=0 out
  mkdir -p "$ENV_DIR/plain"
  cp -r "$ROOT/scripts" "$ENV_DIR/plain/scripts"
  printf '#!/usr/bin/env bash\necho "curl $*" >>"$FAKE_LOG"\n' >"$FAKE_BIN/curl"
  printf '#!/usr/bin/env bash\necho "wget $*" >>"$FAKE_LOG"\n' >"$FAKE_BIN/wget"
  chmod +x "$FAKE_BIN/curl" "$FAKE_BIN/wget"
  out="$(in_env bash "$ENV_DIR/plain/scripts/update.sh" 2>&1)" || rc=$?
  assert_eq "fora de um clone git sai com 1" "1" "$rc"
  assert_contains "explica que não é um clone" "$out" "não é um clone git"
  assert_contains "sugere clonar o repositório padrão" "$out" "git clone https://github.com/maujabur/linux-toolbox.git"
  assert_contains "sugere o tarball sem git" "$out" "https://github.com/maujabur/linux-toolbox/archive/refs/heads/main.tar.gz"
  assert_contains "sugere instalar o git" "$out" "sudo apt-get install -y git"
  assert_eq "não baixa nem executa nada sozinho (curl/wget simulados não foram chamados)" "" "$(cat "$CALL_LOG")"
  assert_eq "não cria nada na pasta" "" "$(find "$ENV_DIR/plain" -mindepth 1 -maxdepth 1 ! -name scripts)"
  make_clone
  git_t -C "$CLONE" branch --unset-upstream
  rc=0
  out="$(in_env bash "$CLONE/scripts/update.sh" 2>&1)" || rc=$?
  assert_eq "sem upstream sai com 1" "1" "$rc"
  assert_contains "explica a falta de upstream" "$out" "não tem upstream"
}

test_update_missing_git_and_bad_option() {
  new_env
  local rc=0 minbin="$ENV_DIR/minbin"
  mkdir -p "$minbin"
  ln -s "$(command -v bash)" "$minbin/bash"
  ln -s "$(command -v dirname)" "$minbin/dirname"
  env HOME="$HOME_DIR" PATH="$minbin" "$minbin/bash" "$ROOT/scripts/update.sh" >/dev/null 2>&1 </dev/null || rc=$?
  assert_eq "git ausente sai com 1" "1" "$rc"
  check_not "opção desconhecida falha" in_env bash "$ROOT/scripts/update.sh" --nada
}

test_update_tarball_without_git_suggests_default_repo() {
  # Cenário do Raspberry Pi sem git: pasta extraída de um tarball, PATH mínimo.
  new_env
  local rc=0 out minbin="$ENV_DIR/minbin"
  mkdir -p "$ENV_DIR/plain" "$minbin"
  cp -r "$ROOT/scripts" "$ENV_DIR/plain/scripts"
  ln -s "$(command -v bash)" "$minbin/bash"
  ln -s "$(command -v dirname)" "$minbin/dirname"
  out="$(env HOME="$HOME_DIR" PATH="$minbin" "$minbin/bash" "$ENV_DIR/plain/scripts/update.sh" 2>&1 </dev/null)" || rc=$?
  assert_eq "sem git e sem clone sai com 1" "1" "$rc"
  assert_contains "orienta com o repositório padrão, não só 'git não encontrado'" "$out" "git clone https://github.com/maujabur/linux-toolbox.git"
  assert_contains "mostra o comando do tarball" "$out" "curl -fsSL https://github.com/maujabur/linux-toolbox/archive/refs/heads/main.tar.gz"
  assert_eq "HOME intacto" "" "$(find "$HOME_DIR" -mindepth 1)"
}

test_update_missing_git_in_a_clone_says_how_to_install() {
  new_env
  local rc=0 out minbin="$ENV_DIR/minbin"
  mkdir -p "$minbin"
  ln -s "$(command -v bash)" "$minbin/bash"
  ln -s "$(command -v dirname)" "$minbin/dirname"
  out="$(env HOME="$HOME_DIR" PATH="$minbin" "$minbin/bash" "$ROOT/scripts/update.sh" 2>&1 </dev/null)" || rc=$?
  assert_eq "clone sem git instalado sai com 1" "1" "$rc"
  assert_contains "diz como instalar o git" "$out" "sudo apt-get install -y git"
}

test_update_bootstrap_option_9_in_tarball_folder() {
  new_env
  local out
  mkdir -p "$ENV_DIR/plain"
  (cd "$ROOT" && git ls-files -co --exclude-standard -z | xargs -0 cp -p --parents -t "$ENV_DIR/plain")
  out="$(in_env_input '9\n\n0\n' bash "$ENV_DIR/plain/bootstrap.sh" 2>&1)"
  assert_contains "o menu mostra a orientação" "$out" "git clone https://github.com/maujabur/linux-toolbox.git"
  assert_eq "o menu continua funcionando depois" "2" "$(grep -c 'Configurar aliases do Bash' <<<"$out")"
}
