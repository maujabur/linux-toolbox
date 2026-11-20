# shellcheck shell=bash
# shellcheck disable=SC2016
# Testes de scripts/setup-bash.sh.

test_setup_bash_creates_and_is_idempotent() {
  new_env
  local rc=0 out count
  in_env bash "$ROOT/scripts/setup-bash.sh" >/dev/null || rc=$?
  assert_eq "setup-bash cria .bashrc ausente" "0" "$rc"
  count="$(grep -c "aliases.sh" "$HOME_DIR/.bashrc")"
  assert_eq "linha de aliases gravada uma vez" "1" "$count"
  assert_eq "sem backup quando .bashrc não existia" "" "$(find "$HOME_DIR" -name '.bashrc.bak.*')"
  out="$(in_env bash "$ROOT/scripts/setup-bash.sh")"
  assert_contains "segunda execução informa já configurado" "$out" "Já configurado"
  count="$(grep -c "aliases.sh" "$HOME_DIR/.bashrc")"
  assert_eq "segunda execução não duplica a linha" "1" "$count"
  assert_eq "segunda execução não cria backup" "" "$(find "$HOME_DIR" -name '.bashrc.bak.*')"
}

test_setup_bash_backs_up_existing() {
  new_env
  printf 'export X=1\n' >"$HOME_DIR/.bashrc"
  in_env bash "$ROOT/scripts/setup-bash.sh" >/dev/null
  local backups=()
  mapfile -t backups < <(find "$HOME_DIR" -name '.bashrc.bak.*')
  assert_eq "um backup criado" "1" "${#backups[@]}"
  assert_eq "backup tem o conteúdo original" "export X=1" "$(cat "${backups[0]}")"
  assert_contains ".bashrc mantém conteúdo anterior" "$(cat "$HOME_DIR/.bashrc")" "export X=1"
}

test_setup_bash_recognizes_legacy_line() {
  new_env
  printf 'source "%s/configs/bash/aliases.sh"\n' "$ROOT" >"$HOME_DIR/.bashrc"
  local before out
  before="$(cat "$HOME_DIR/.bashrc")"
  out="$(in_env bash "$ROOT/scripts/setup-bash.sh")"
  assert_contains "linha antiga é reconhecida" "$out" "Já configurado"
  assert_eq ".bashrc inalterado" "$before" "$(cat "$HOME_DIR/.bashrc")"
}

test_setup_bash_line_tolerates_missing_file() {
  new_env
  in_env bash "$ROOT/scripts/setup-bash.sh" >/dev/null
  local out
  out="$(env HOME="$HOME_DIR" bash --norc --noprofile -c 'source "$HOME/.bashrc"; echo carregado')"
  assert_eq ".bashrc carrega e aliases ficam disponíveis" "carregado" "$out"
}

test_setup_bash_dry_run_has_no_side_effects() {
  new_env
  local before after
  before="$(snapshot "$HOME_DIR")"
  in_env bash "$ROOT/scripts/setup-bash.sh" --dry-run >/dev/null
  assert_eq "dry-run sem .bashrc não altera HOME" "$before" "$(snapshot "$HOME_DIR")"
  printf 'export X=1\n' >"$HOME_DIR/.bashrc"
  before="$(snapshot "$HOME_DIR")"
  after="$(in_env bash "$ROOT/scripts/setup-bash.sh" --dry-run)"
  assert_eq "dry-run com .bashrc não altera HOME" "$before" "$(snapshot "$HOME_DIR")"
  assert_contains "dry-run descreve o backup" "$after" "[dry-run]"
}

test_setup_bash_rejects_unknown_option() {
  new_env
  check_not "opção desconhecida falha" in_env bash "$ROOT/scripts/setup-bash.sh" --nada
}
