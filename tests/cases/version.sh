# shellcheck shell=bash
# shellcheck disable=SC2016
# Testes do cabeçalho de versão do bootstrap.sh (revisão, data e estado locais).
# Usam make_clone (tests/cases/update.sh): clones temporários, nunca este repositório.

# header_of "entrada" ARGS...: saída (stdout+stderr) do bootstrap com o stdin dado.
header_of() {
  local input="$1"
  shift
  in_env_input "$input" "$@" 2>&1
}

# line_value "texto" "Rótulo:": valor da primeira linha que começa com o rótulo.
line_value() {
  grep -m1 "^$2" <<<"$1" | sed "s/^$2[[:space:]]*//"
}

# install_git_shim: git simulado que registra as chamadas e delega ao git real.
install_git_shim() {
  local real
  real="$(command -v git)"
  printf '#!/usr/bin/env bash\necho "git $*" >>"$FAKE_LOG"\nexec %q "$@"\n' "$real" >"$FAKE_BIN/git"
  chmod +x "$FAKE_BIN/git"
}

test_version_header_in_a_clean_clone() {
  make_clone
  local out expected_rev expected_date
  expected_rev="$(git_t -C "$CLONE" rev-parse --short HEAD)"
  expected_date="$(git_t -C "$CLONE" log -1 --format=%cs)"
  out="$(header_of '0\n' bash "$CLONE/bootstrap.sh")"
  assert_eq "revisão abreviada do commit atual" "$expected_rev" "$(line_value "$out" 'Revisão:')"
  assert_eq "data do commit" "$expected_date" "$(line_value "$out" 'Data:')"
  assert_eq "estado limpo" "Limpo" "$(line_value "$out" 'Estado:')"
  check "a data está no formato AAAA-MM-DD" bash -c '[[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]' _ "$expected_date"
  assert_contains "o cabeçalho vem logo abaixo do título" "$out" "linux-toolbox
Revisão: $expected_rev
Data:    $expected_date
Estado:  Limpo
1) Configurar aliases do Bash"
}

test_version_header_reports_local_changes() {
  make_clone
  local out rev
  rev="$(git_t -C "$CLONE" rev-parse --short HEAD)"
  printf '# alteração local\n' >>"$CLONE/README.md"
  out="$(header_of '0\n' bash "$CLONE/bootstrap.sh")"
  assert_eq "arquivo rastreado modificado" "Com alterações locais" "$(line_value "$out" 'Estado:')"
  assert_eq "a revisão continua a do commit" "$rev" "$(line_value "$out" 'Revisão:')"
  git_t -C "$CLONE" checkout -q -- README.md
  git_t -C "$CLONE" mv README.md LEIAME.md
  out="$(header_of '0\n' bash "$CLONE/bootstrap.sh")"
  assert_eq "alteração já no índice (staged)" "Com alterações locais" "$(line_value "$out" 'Estado:')"
  git_t -C "$CLONE" reset -q --hard
  assert_eq "de volta ao estado limpo" "Limpo" "$(line_value "$(header_of '0\n' bash "$CLONE/bootstrap.sh")" 'Estado:')"
  printf 'novo\n' >"$CLONE/arquivo-novo.txt"
  out="$(header_of '0\n' bash "$CLONE/bootstrap.sh")"
  assert_eq "arquivo novo não rastreado" "Com alterações locais" "$(line_value "$out" 'Estado:')"
}

test_version_header_without_dot_git() {
  new_env
  local out rc=0
  mkdir -p "$ENV_DIR/plain"
  (cd "$ROOT" && git ls-files -co --exclude-standard -z | xargs -0 cp -p --parents -t "$ENV_DIR/plain")
  out="$(header_of '0\n' bash "$ENV_DIR/plain/bootstrap.sh")" || rc=$?
  assert_eq "o menu funciona sem .git" "0" "$rc"
  assert_eq "revisão indisponível" "indisponível (cópia sem .git)" "$(line_value "$out" 'Revisão:')"
  assert_eq "data indisponível" "indisponível" "$(line_value "$out" 'Data:')"
  assert_eq "estado indisponível" "indisponível" "$(line_value "$out" 'Estado:')"
  assert_contains "o menu continua completo" "$out" "1) Configurar aliases do Bash"
}

test_version_header_copy_inside_another_repository_does_not_borrow_its_revision() {
  make_clone
  local out
  mkdir -p "$CLONE/sub"
  (cd "$ROOT" && git ls-files -co --exclude-standard -z | xargs -0 cp -p --parents -t "$CLONE/sub")
  out="$(header_of '0\n' bash "$CLONE/sub/bootstrap.sh")"
  assert_eq "cópia sem .git dentro de outro repositório" "indisponível (cópia sem .git)" "$(line_value "$out" 'Revisão:')"
}

test_version_header_without_git_command() {
  make_clone
  local out rc=0 minbin="$ENV_DIR/minbin"
  mkdir -p "$minbin"
  ln -s "$(command -v bash)" "$minbin/bash"
  ln -s "$(command -v dirname)" "$minbin/dirname"
  out="$(printf '0\n' | env HOME="$HOME_DIR" PATH="$minbin" "$minbin/bash" "$CLONE/bootstrap.sh" 2>&1)" || rc=$?
  assert_eq "o menu funciona sem o comando git" "0" "$rc"
  assert_eq "revisão indisponível, com o motivo" "indisponível (git não instalado)" "$(line_value "$out" 'Revisão:')"
  assert_eq "estado indisponível" "indisponível" "$(line_value "$out" 'Estado:')"
  assert_contains "o menu continua completo" "$out" "1) Configurar aliases do Bash"
}

test_version_header_with_unreadable_repository() {
  new_env
  local out rc=0
  mkdir -p "$ENV_DIR/quebrado/.git"
  (cd "$ROOT" && git ls-files -co --exclude-standard -z | xargs -0 cp -p --parents -t "$ENV_DIR/quebrado")
  out="$(header_of '0\n' bash "$ENV_DIR/quebrado/bootstrap.sh")" || rc=$?
  assert_eq "o menu funciona com .git inválido" "0" "$rc"
  assert_eq "revisão indisponível, com o motivo" "indisponível (não foi possível ler o repositório git)" "$(line_value "$out" 'Revisão:')"
}

test_version_header_with_dry_run() {
  make_clone
  local out rev
  rev="$(git_t -C "$CLONE" rev-parse --short HEAD)"
  out="$(header_of '0\n' bash "$CLONE/bootstrap.sh" --dry-run)"
  assert_contains "o título indica dry-run e o cabeçalho segue" "$out" "linux-toolbox (dry-run)
Revisão: $rev"
  assert_eq "estado limpo também em dry-run" "Limpo" "$(line_value "$out" 'Estado:')"
  assert_contains "o menu não mudou" "$out" "10) Aplicar perfil de máquina..."
}

test_version_header_has_no_side_effects_even_inside_git() {
  make_clone
  local before after
  # Torna o índice "velho" (mtime novo, conteúdo igual): um git status comum
  # reescreveria .git/index; com --no-optional-locks isso não pode acontecer.
  sleep 1
  touch "$CLONE/README.md" "$CLONE/scripts/lib.sh"
  before="$(snapshot "$CLONE")"
  header_of 'x\n\n0\n' bash "$CLONE/bootstrap.sh" --dry-run >/dev/null
  after="$(snapshot "$CLONE")"
  assert_eq "nenhum arquivo do clone nem de .git foi alterado" "$before" "$after"
  check "o índice continua o mesmo arquivo (sem lock residual)" test ! -e "$CLONE/.git/index.lock"
  assert_eq "o HOME de teste não foi tocado" "" "$(find "$HOME_DIR" -mindepth 1)"
}

test_version_header_does_not_use_the_network_and_calls_git_once() {
  make_clone
  install_git_shim
  : >"$CALL_LOG"
  # Duas exibições do menu (opção inválida e depois sair): o git é consultado uma vez.
  header_of 'x\n\n0\n' bash "$CLONE/bootstrap.sh" >/dev/null
  assert_eq "duas chamadas ao git: log e status" "2" "$(grep -c '^git ' "$CALL_LOG")"
  assert_contains "usa git log" "$(cat "$CALL_LOG")" "log -1"
  assert_contains "usa git status" "$(cat "$CALL_LOG")" "status --porcelain"
  assert_eq "ambas sem travar o índice" "2" "$(grep -c -- '--no-optional-locks' "$CALL_LOG")"
  # Chamadas têm a forma: git --no-optional-locks -C CAMINHO SUBCOMANDO ...
  assert_eq "os únicos subcomandos usados são log e status (nada de rede ou escrita)" "log
status" "$(awk '/^git /{print $5}' "$CALL_LOG" | sort -u)"
}

test_version_header_is_shown_on_every_menu_draw() {
  make_clone
  local out
  out="$(header_of 'x\n\n0\n' bash "$CLONE/bootstrap.sh")"
  assert_eq "o cabeçalho aparece a cada exibição do menu" "2" "$(grep -c '^Revisão: ' <<<"$out")"
}
