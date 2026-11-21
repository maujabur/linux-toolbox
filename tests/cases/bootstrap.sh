# shellcheck shell=bash
# Testes de bootstrap.sh (menu interativo, com entrada simulada).
# Depois de cada operação o menu pausa e espera Enter: por isso há linhas
# vazias ("\n") nas entradas simuladas.

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
  out="$(in_env_input 'x\n\n0\n' bash "$ROOT/bootstrap.sh" 2>&1)" || rc=$?
  assert_eq "opção inválida não encerra o menu" "0" "$rc"
  assert_contains "mensagem de opção inválida" "$out" "Opção inválida"
  assert_contains "mensagem entre linhas de destaque" "$out" "========================================================================
Opção inválida: x"
}

test_bootstrap_dry_run_makes_no_changes() {
  new_env
  local before
  before="$(snapshot "$HOME_DIR")"
  in_env_input '1\n\n2\n\n3\n\n4\n\n5\n\n6\n\n9\n\n0\n' bash "$ROOT/bootstrap.sh" --dry-run >/dev/null 2>&1
  assert_eq "dry-run em todas as opções de configuração/instalação não altera HOME" "$before" "$(snapshot "$HOME_DIR")"
  assert_eq "dry-run em todas as opções não chama sudo/apt" "" "$(cat "$CALL_LOG")"
}

test_bootstrap_runs_selected_script() {
  new_env
  in_env_input '1\n\n0\n' bash "$ROOT/bootstrap.sh" >/dev/null 2>&1
  check "opção 1 configura o .bashrc" grep -q aliases.sh "$HOME_DIR/.bashrc"
  assert_eq "opção 1 não chama sudo" "" "$(cat "$CALL_LOG")"
}

test_bootstrap_failure_does_not_abort_menu() {
  new_env
  local out
  out="$(in_env_input '7\n\n0\n' bash "$ROOT/bootstrap.sh" 2>&1)"
  assert_contains "falha da restauração é informada" "$out" "terminou com código"
}

test_bootstrap_install_asks_confirmation() {
  new_env
  in_env_input '3\nn\n\n0\n' bash "$ROOT/bootstrap.sh" >/dev/null 2>&1
  assert_eq "recusar a confirmação não chama apt" "" "$(cat "$CALL_LOG")"
}

test_bootstrap_git_option_configures_and_restores() {
  new_env
  printf '[user]\n\tname = Fulano\n' >"$HOME_DIR/.gitconfig"
  local original
  original="$(cat "$HOME_DIR/.gitconfig")"
  in_env_input '9\n\n0\n' bash "$ROOT/bootstrap.sh" >/dev/null 2>&1
  check "opção 9 inclui a configuração" grep -q 'include' "$HOME_DIR/.gitconfig"
  assert_eq "opção 9 não chama sudo" "" "$(cat "$CALL_LOG")"
  in_env_input '10\ns\n\n0\n' bash "$ROOT/bootstrap.sh" >/dev/null 2>&1
  assert_eq "opção 10 restaura o original" "$original" "$(cat "$HOME_DIR/.gitconfig")"
}

test_bootstrap_git_dry_run_has_no_side_effects() {
  new_env
  local before
  before="$(snapshot "$HOME_DIR")"
  in_env_input '9\n\n10\n\n0\n' bash "$ROOT/bootstrap.sh" --dry-run >/dev/null 2>&1
  assert_eq "dry-run das opções 9 e 10 não altera HOME" "$before" "$(snapshot "$HOME_DIR")"
}

test_bootstrap_pauses_before_redrawing_menu() {
  new_env
  local out first_menu_end result_pos second_menu_pos
  out="$(in_env_input '1\n\n0\n' bash "$ROOT/bootstrap.sh" 2>&1)"
  assert_contains "mostra a pausa" "$out" "Pressione Enter para voltar ao menu"
  # O resultado e a pausa devem vir ANTES do segundo menu.
  result_pos="${out%%PRÓXIMO PASSO*}"
  second_menu_pos="${out%%Pressione Enter*}"
  check "o próximo passo aparece antes da pausa" test "${#result_pos}" -lt "${#second_menu_pos}"
  first_menu_end="${out#*Pressione Enter para voltar ao menu... }"
  assert_contains "o menu só reaparece depois da pausa" "$first_menu_end" "Configurar aliases do Bash"
  assert_not_contains "o resultado não vem depois da pausa" "$first_menu_end" "PRÓXIMO PASSO"
}

test_bootstrap_without_enter_does_not_loop_forever() {
  new_env
  local rc=0
  # Entrada termina logo após a operação: a pausa e o menu seguinte veem EOF.
  in_env_input '1\n' bash "$ROOT/bootstrap.sh" >/dev/null 2>&1 || rc=$?
  assert_eq "EOF após a operação encerra com 0" "0" "$rc"
}
