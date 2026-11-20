# shellcheck shell=bash
# Testes de bootstrap.sh (menu interativo, com entrada simulada).

test_bootstrap_exit_and_eof() {
  new_env
  local rc=0
  in_env_input '0\n' bash "$ROOT/bootstrap.sh" >/dev/null 2>&1 || rc=$?
  assert_eq "opção 0 sai com 0" "0" "$rc"
  rc=0
  in_env bash "$ROOT/bootstrap.sh" >/dev/null 2>&1 || rc=$?
  assert_eq "EOF encerra com 0" "0" "$rc"
  assert_eq "nada foi chamado" "" "$(cat "$CALL_LOG")"
  assert_eq "HOME vazio" "" "$(find "$HOME_DIR" -mindepth 1)"
}

test_bootstrap_invalid_option_returns_to_menu() {
  new_env
  local out rc=0
  out="$(in_env_input 'x\n0\n' bash "$ROOT/bootstrap.sh" 2>&1)" || rc=$?
  assert_eq "opção inválida não encerra o menu" "0" "$rc"
  assert_contains "mensagem de opção inválida" "$out" "Opção inválida"
}

test_bootstrap_dry_run_makes_no_changes() {
  new_env
  local before
  before="$(snapshot "$HOME_DIR")"
  in_env_input '1\n2\n3\n4\n5\n6\n9\n0\n' bash "$ROOT/bootstrap.sh" --dry-run >/dev/null 2>&1
  assert_eq "dry-run em todas as opções de configuração/instalação não altera HOME" "$before" "$(snapshot "$HOME_DIR")"
  assert_eq "dry-run em todas as opções não chama sudo/apt" "" "$(cat "$CALL_LOG")"
}

test_bootstrap_runs_selected_script() {
  new_env
  in_env_input '1\n0\n' bash "$ROOT/bootstrap.sh" >/dev/null 2>&1
  check "opção 1 configura o .bashrc" grep -q aliases.sh "$HOME_DIR/.bashrc"
  assert_eq "opção 1 não chama sudo" "" "$(cat "$CALL_LOG")"
}

test_bootstrap_failure_does_not_abort_menu() {
  new_env
  local out
  out="$(in_env_input '7\n0\n' bash "$ROOT/bootstrap.sh" 2>&1)"
  assert_contains "falha da restauração é informada" "$out" "terminou com código"
}

test_bootstrap_install_asks_confirmation() {
  new_env
  in_env_input '3\nn\n0\n' bash "$ROOT/bootstrap.sh" >/dev/null 2>&1
  assert_eq "recusar a confirmação não chama apt" "" "$(cat "$CALL_LOG")"
}

test_bootstrap_git_option_configures_and_restores() {
  new_env
  printf '[user]\n\tname = Fulano\n' >"$HOME_DIR/.gitconfig"
  local original
  original="$(cat "$HOME_DIR/.gitconfig")"
  in_env_input '9\n0\n' bash "$ROOT/bootstrap.sh" >/dev/null 2>&1
  check "opção 9 inclui a configuração" grep -q 'include' "$HOME_DIR/.gitconfig"
  assert_eq "opção 9 não chama sudo" "" "$(cat "$CALL_LOG")"
  in_env_input '10\ns\n0\n' bash "$ROOT/bootstrap.sh" >/dev/null 2>&1
  assert_eq "opção 10 restaura o original" "$original" "$(cat "$HOME_DIR/.gitconfig")"
}

test_bootstrap_git_dry_run_has_no_side_effects() {
  new_env
  local before
  before="$(snapshot "$HOME_DIR")"
  in_env_input '9\n10\n0\n' bash "$ROOT/bootstrap.sh" --dry-run >/dev/null 2>&1
  assert_eq "dry-run das opções 9 e 10 não altera HOME" "$before" "$(snapshot "$HOME_DIR")"
}
