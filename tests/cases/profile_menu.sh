# shellcheck shell=bash
# Testes da opção 10 do menu (perfis de máquina). Sistema e hardware simulados.

# menu_prof "entrada" ARGS...: bootstrap.sh no ambiente simulado, com entrada pelo stdin.
menu_prof() {
  local input="$1"
  shift
  in_env_input "$input" env TOOLBOX_OS_RELEASE_FILE="$PROF_OS" TOOLBOX_DT_MODEL_FILE="$PROF_MODEL" \
    bash "$ROOT/bootstrap.sh" "$@"
}

test_profile_menu_lists_profiles_and_goes_back() {
  new_prof_env
  local out
  out="$(menu_prof '10\n0\n0\n' 2>&1)"
  assert_contains "submenu lista os perfis" "$out" "1) debian-desktop"
  assert_contains "submenu lista o servidor" "$out" "2) debian-server"
  assert_contains "submenu lista o Pi" "$out" "3) raspberry-pi-headless"
  assert_not_contains "voltar não pausa" "$out" "Enter = voltar ao menu"
  assert_eq "nada foi alterado" "" "$(find "$HOME_DIR" -mindepth 1)"
}

test_profile_menu_dry_run_has_no_side_effects() {
  new_prof_env
  local before out
  before="$(snapshot "$HOME_DIR")"
  out="$(menu_prof '10\n1\n\n0\n' --dry-run 2>&1)"
  assert_contains "mostra o plano do perfil escolhido" "$out" "Perfil:     debian-desktop"
  assert_contains "executa em dry-run" "$out" "[dry-run] Perfil debian-desktop: nenhuma alteração foi feita."
  assert_eq "dry-run pelo menu não altera HOME" "$before" "$(snapshot "$HOME_DIR")"
  assert_eq "dry-run pelo menu não chama sudo/apt" "" "$(cat "$CALL_LOG")"
}

test_profile_menu_asks_confirmation_and_applies() {
  new_prof_env
  local before
  before="$(snapshot "$HOME_DIR")"
  menu_prof '10\n2\nn\n\n0\n' >/dev/null 2>&1
  assert_eq "recusar o plano não altera nada" "$before" "$(snapshot "$HOME_DIR")"
  assert_eq "recusar o plano não chama apt" "" "$(cat "$CALL_LOG")"
  menu_prof '10\n2\ns\n\n0\n' >/dev/null 2>&1
  assert_contains "confirmar instala a base" "$(cat "$CALL_LOG")" "apt-get install -y git curl"
  check "confirmar aplica os ajustes de usuário" grep -q aliases.sh "$HOME_DIR/.bashrc"
}

test_profile_menu_respects_requirements_and_invalid_input() {
  new_prof_env "Dell XPS"
  local out
  out="$(menu_prof '10\n3\n\n0\n' 2>&1)"
  assert_contains "perfil do Pi fora de um Pi é recusado" "$out" "não se aplica a esta máquina"
  assert_eq "nada foi chamado" "" "$(cat "$CALL_LOG")"
  out="$(menu_prof '10\n9\n\n0\n' 2>&1)"
  assert_contains "número fora da lista é inválido" "$out" "Opção inválida: 9"
  out="$(menu_prof '10\nx\n\n0\n' 2>&1)"
  assert_contains "texto é inválido" "$out" "Opção inválida: x"
}
