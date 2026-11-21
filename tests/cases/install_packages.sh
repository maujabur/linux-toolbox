# shellcheck shell=bash
# Testes de scripts/install-packages.sh (apt-get e sudo são simulados).

test_install_dry_run_has_no_side_effects() {
  new_env
  local before out
  before="$(snapshot "$HOME_DIR")"
  out="$(in_env bash "$ROOT/scripts/install-packages.sh" --dry-run agents)"
  assert_eq "dry-run não executa sudo nem apt-get" "" "$(cat "$CALL_LOG")"
  assert_eq "dry-run não altera HOME" "$before" "$(snapshot "$HOME_DIR")"
  assert_contains "dry-run lista os pacotes" "$out" "ripgrep"
  assert_contains "dry-run descreve o install" "$out" "[dry-run]"
  assert_contains "dry-run do perfil agents menciona setup-fd" "$out" "setup-fd.sh"
  assert_eq "dry-run não cria ~/.local" "" "$(find "$HOME_DIR" -mindepth 1)"
}

test_install_requires_confirmation() {
  new_env
  local rc=0
  in_env bash "$ROOT/scripts/install-packages.sh" base >/dev/null 2>&1 || rc=$?
  assert_eq "sem entrada (EOF) cancela com código 1" "1" "$rc"
  assert_eq "nada foi executado sem confirmação" "" "$(cat "$CALL_LOG")"
  rc=0
  in_env_input 'n\n' bash "$ROOT/scripts/install-packages.sh" base >/dev/null 2>&1 || rc=$?
  assert_eq "resposta n cancela com código 1" "1" "$rc"
  assert_eq "nada foi executado após recusar" "" "$(cat "$CALL_LOG")"
  rc=0
  in_env_input '\n' bash "$ROOT/scripts/install-packages.sh" base >/dev/null 2>&1 || rc=$?
  assert_eq "Enter vazio (padrão N) cancela" "1" "$rc"
}

test_install_confirmed_runs_apt() {
  new_env
  local rc=0
  in_env_input 's\n' bash "$ROOT/scripts/install-packages.sh" desktop >/dev/null 2>&1 || rc=$?
  assert_eq "resposta s instala" "0" "$rc"
  assert_contains "apt-get update chamado" "$(cat "$CALL_LOG")" "apt-get update"
  assert_contains "apt-get install chamado com os pacotes" "$(cat "$CALL_LOG")" "apt-get install -y kate konsole"
}

test_install_yes_is_non_interactive() {
  new_env
  local rc=0
  in_env bash "$ROOT/scripts/install-packages.sh" --yes desktop >/dev/null 2>&1 || rc=$?
  assert_eq "--yes instala sem entrada" "0" "$rc"
  assert_contains "install chamado" "$(cat "$CALL_LOG")" "apt-get install -y kate konsole"
}

test_install_agents_runs_fd_setup() {
  new_env
  in_env bash "$ROOT/scripts/install-packages.sh" -y agents >/dev/null 2>&1
  assert_eq "perfil agents cria o link fd" "$FAKE_BIN/fdfind" "$(readlink "$HOME_DIR/.local/bin/fd")"
}

test_install_agents_fd_conflict_is_warning() {
  new_env
  mkdir -p "$HOME_DIR/.local/bin"
  printf 'meu\n' >"$HOME_DIR/.local/bin/fd"
  local rc=0 err
  err="$(in_env bash "$ROOT/scripts/install-packages.sh" -y agents 2>&1 >/dev/null)" || rc=$?
  assert_eq "conflito do fd não falha a instalação" "0" "$rc"
  assert_contains "aviso explícito sobre o fd" "$err" "NÃO foi configurado"
  assert_eq "arquivo fd existente intocado" "meu" "$(cat "$HOME_DIR/.local/bin/fd")"
}

test_install_rejects_bad_input() {
  new_env
  check_not "perfil com caminho é rejeitado" in_env bash "$ROOT/scripts/install-packages.sh" -y ../packages/base
  check_not "perfil inexistente é rejeitado" in_env bash "$ROOT/scripts/install-packages.sh" -y inexistente
  check_not "opção desconhecida é rejeitada" in_env bash "$ROOT/scripts/install-packages.sh" --nada
  check_not "dois perfis são rejeitados" in_env bash "$ROOT/scripts/install-packages.sh" -y base agents
  assert_eq "nenhuma chamada a apt/sudo" "" "$(cat "$CALL_LOG")"
}

test_install_shows_free_space() {
  new_env
  local out
  out="$(in_env bash "$ROOT/scripts/install-packages.sh" --dry-run desktop)"
  assert_contains "mostra o espaço livre antes de instalar" "$out" "Espaço livre em /: "
  assert_eq "o espaço livre não gera chamadas a sudo/apt" "" "$(cat "$CALL_LOG")"
  out="$(in_env_input 'n\n' bash "$ROOT/scripts/install-packages.sh" desktop 2>&1)" || true
  assert_contains "aparece também antes da confirmação" "$out" "Espaço livre em /: "
}
