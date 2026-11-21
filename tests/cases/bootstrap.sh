# shellcheck shell=bash
# Testes de bootstrap.sh (menu interativo, com entrada simulada).
# Depois de cada operação o menu pausa (Enter volta, q sai): por isso há linhas
# vazias ("\n") nas entradas simuladas. A opção 9 (atualizar) só é testada em
# clones temporários (ver tests/cases/update.sh), nunca neste repositório.

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
  in_env_input '1\n\n2\n\n3\n\n4\n\n5\n\n6\n\n7\n\n0\n' bash "$ROOT/bootstrap.sh" --dry-run >/dev/null 2>&1
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
  out="$(in_env_input '8\n1\n\n0\n' bash "$ROOT/bootstrap.sh" 2>&1)"
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
  in_env_input '7\n\n0\n' bash "$ROOT/bootstrap.sh" >/dev/null 2>&1
  check "opção 7 inclui a configuração" grep -q 'include' "$HOME_DIR/.gitconfig"
  assert_eq "opção 7 não chama sudo" "" "$(cat "$CALL_LOG")"
  in_env_input '8\n3\ns\n\n0\n' bash "$ROOT/bootstrap.sh" >/dev/null 2>&1
  assert_eq "submenu 8 > 3 restaura o original" "$original" "$(cat "$HOME_DIR/.gitconfig")"
}

test_bootstrap_git_dry_run_has_no_side_effects() {
  new_env
  local before
  before="$(snapshot "$HOME_DIR")"
  in_env_input '7\n\n8\n3\n\n0\n' bash "$ROOT/bootstrap.sh" --dry-run >/dev/null 2>&1
  assert_eq "dry-run de configurar/restaurar Git não altera HOME" "$before" "$(snapshot "$HOME_DIR")"
}

test_bootstrap_pauses_before_redrawing_menu() {
  new_env
  local out after_pause before_pause
  out="$(in_env_input '1\n\n0\n' bash "$ROOT/bootstrap.sh" 2>&1)"
  assert_contains "mostra a pausa" "$out" "Enter = voltar ao menu, q = sair"
  before_pause="${out%%Enter = voltar*}"
  after_pause="${out#*Enter = voltar ao menu, q = sair: }"
  assert_contains "o próximo passo vem antes da pausa" "$before_pause" "PRÓXIMO PASSO"
  assert_contains "o menu só reaparece depois da pausa" "$after_pause" "Configurar aliases do Bash"
  assert_not_contains "o resultado não vem depois da pausa" "$after_pause" "PRÓXIMO PASSO"
}

test_bootstrap_pause_allows_quitting() {
  new_env
  local answer out rc
  for answer in q Q 0; do
    rc=0
    out="$(in_env_input "1\n$answer\n" bash "$ROOT/bootstrap.sh" 2>&1)" || rc=$?
    assert_eq "'$answer' na pausa sai com 0" "0" "$rc"
    assert_contains "'$answer' na pausa despede-se" "$out" "Até logo."
    assert_eq "'$answer' na pausa não redesenha o menu" "1" "$(grep -c 'Configurar aliases do Bash' <<<"$out")"
  done
  # A operação já foi executada antes de sair.
  check "a operação selecionada foi concluída" grep -q aliases.sh "$HOME_DIR/.bashrc"
}

test_bootstrap_pause_enter_continues_and_eof_exits() {
  new_env
  local out rc=0
  out="$(in_env_input '1\n\n0\n' bash "$ROOT/bootstrap.sh" 2>&1)"
  assert_eq "Enter redesenha o menu" "2" "$(grep -c 'Configurar aliases do Bash' <<<"$out")"
  in_env_input '1\n' bash "$ROOT/bootstrap.sh" >/dev/null 2>&1 || rc=$?
  assert_eq "EOF após a operação encerra com 0" "0" "$rc"
}

test_bootstrap_restore_submenu() {
  new_env
  local out
  printf 'bak\n' >"$HOME_DIR/.bashrc.bak.20260101_000000"
  printf 'atual\n' >"$HOME_DIR/.bashrc"
  out="$(in_env_input '8\n1\ns\n\n0\n' bash "$ROOT/bootstrap.sh" 2>&1)"
  assert_contains "submenu lista os alvos" "$out" "Restaurar backup de:"
  assert_eq "submenu 1 restaura o .bashrc" "bak" "$(cat "$HOME_DIR/.bashrc")"
  mkdir -p "$HOME_DIR/.config/tmux"
  printf 'tmux-bak\n' >"$HOME_DIR/.config/tmux/tmux.conf.bak.20260101_000000"
  printf 'tmux-atual\n' >"$HOME_DIR/.config/tmux/tmux.conf"
  in_env_input '8\n2\ns\n\n0\n' bash "$ROOT/bootstrap.sh" >/dev/null 2>&1
  assert_eq "submenu 2 restaura o tmux" "tmux-bak" "$(cat "$HOME_DIR/.config/tmux/tmux.conf")"
}

test_bootstrap_restore_submenu_back_and_invalid() {
  new_env
  local out
  out="$(in_env_input '8\n0\n0\n' bash "$ROOT/bootstrap.sh" 2>&1)"
  assert_not_contains "voltar não pausa" "$out" "Enter = voltar ao menu"
  assert_eq "voltar redesenha o menu principal" "2" "$(grep -c 'Configurar aliases do Bash' <<<"$out")"
  out="$(in_env_input '8\nx\n\n0\n' bash "$ROOT/bootstrap.sh" 2>&1)"
  assert_contains "opção inválida no submenu é informada" "$out" "Opção inválida: x"
  assert_eq "submenu não existe no menu principal como itens soltos" "" "$(in_env_input '0\n' bash "$ROOT/bootstrap.sh" 2>&1 | grep -E 'Restaurar backup d' || true)"
}
