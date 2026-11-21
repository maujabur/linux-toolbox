# shellcheck shell=bash
# Testes do destaque visual (banner) e das mensagens finais dos scripts.

BAR="========================================================================"

test_banner_format_and_streams() {
  local out err
  out="$(
    source "$ROOT/scripts/lib.sh"
    banner ok "linha 1" "linha 2" 2>/dev/null
  )"
  assert_eq "ok vai para stdout entre linhas de =" "
$BAR
linha 1
linha 2
$BAR" "$out"
  err="$(
    source "$ROOT/scripts/lib.sh"
    banner err "falhou" 2>&1 >/dev/null
  )"
  assert_contains "err vai para stderr" "$err" "falhou"
  err="$(
    source "$ROOT/scripts/lib.sh"
    banner warn "cuidado" 2>&1 >/dev/null
  )"
  assert_contains "warn vai para stderr" "$err" "cuidado"
}

test_banner_no_color_outside_terminal() {
  local out
  out="$(
    source "$ROOT/scripts/lib.sh"
    banner ok "x" 2>&1
  )"
  assert_not_contains "sem códigos ANSI quando não é terminal" "$out" $'\033'
}

test_banner_die_is_highlighted_and_exits_1() {
  local rc=0 err
  err="$(
    (
      source "$ROOT/scripts/lib.sh"
      die "algo deu errado"
    ) 2>&1
  )" || rc=$?
  assert_eq "die sai com 1" "1" "$rc"
  assert_contains "die usa o destaque" "$err" "$BAR
ERRO: algo deu errado
$BAR"
}

test_banner_setup_bash_next_step() {
  new_env
  local out
  out="$(in_env bash "$ROOT/scripts/setup-bash.sh")"
  assert_contains "próximo passo destacado após alterar o .bashrc" "$out" "$BAR
Aliases adicionados a $HOME_DIR/.bashrc.

PRÓXIMO PASSO: abra um novo terminal ou execute:
  source ~/.bashrc
$BAR"
  out="$(in_env bash "$ROOT/scripts/setup-bash.sh")"
  assert_not_contains "sem próximo passo quando nada mudou" "$out" "PRÓXIMO PASSO"
  assert_contains "já configurado também é destacado" "$out" "$BAR
Já configurado"
}

test_banner_dry_run_states_nothing_changed() {
  new_env
  local script out
  for script in setup-bash.sh setup-tmux.sh setup-git.sh setup-fd.sh "install-packages.sh agents"; do
    # shellcheck disable=SC2086
    out="$(in_env bash "$ROOT/scripts/"${script%% *} ${script#"${script%% *}"} --dry-run 2>&1)"
    assert_contains "dry-run de $script termina com aviso destacado" "$out" "$BAR
[dry-run] Nenhuma alteração foi feita."
  done
}

test_banner_tmux_git_and_install_results() {
  new_env
  local out
  out="$(in_env bash "$ROOT/scripts/setup-tmux.sh")"
  assert_contains "tmux: resultado destacado com próximo passo" "$out" "tmux source-file"
  out="$(in_env bash "$ROOT/scripts/setup-git.sh")"
  assert_contains "git: resultado destacado" "$out" "$BAR
Git configurado"
  assert_contains "git: lembra de definir identidade sem defini-la" "$out" "git config --global user.name"
  out="$(in_env bash "$ROOT/scripts/install-packages.sh" --yes desktop 2>&1)"
  assert_contains "install: conclusão destacada" "$out" "$BAR
Perfil desktop instalado (2 pacotes).
$BAR"
  out="$(in_env bash "$ROOT/scripts/install-packages.sh" desktop 2>&1)" || true
  assert_contains "install: cancelamento destacado" "$out" "$BAR
CANCELADO. Nada foi instalado.
$BAR"
}

test_banner_fd_conflict_and_path_notice() {
  new_env
  local out err
  out="$(in_env bash "$ROOT/scripts/setup-fd.sh")"
  assert_contains "fd: criado dentro do destaque" "$out" "$BAR
Criado:"
  assert_contains "fd: aviso de PATH dentro do mesmo destaque" "$out" "ATENÇÃO: $HOME_DIR/.local/bin não está no PATH"
  new_env
  mkdir -p "$HOME_DIR/.local/bin"
  printf 'x\n' >"$HOME_DIR/.local/bin/fd"
  err="$(in_env bash "$ROOT/scripts/setup-fd.sh" 2>&1 >/dev/null)" || true
  assert_contains "fd: conflito destacado em stderr" "$err" "$BAR
CONFLITO"
}

test_banner_restore_results() {
  new_env
  local out
  printf 'bak\n' >"$HOME_DIR/.bashrc.bak.20260101_000000"
  printf 'atual\n' >"$HOME_DIR/.bashrc"
  out="$(in_env_input 'n\n' bash "$ROOT/scripts/restore.sh" bash 2>&1)" || true
  assert_contains "restore: cancelamento destacado" "$out" "$BAR
CANCELADO. Nada foi alterado.
$BAR"
  out="$(in_env bash "$ROOT/scripts/restore.sh" bash --yes 2>&1)"
  assert_contains "restore: sucesso destacado" "$out" "$BAR
Restaurado: $HOME_DIR/.bashrc"
}

test_banner_lines_fit_width() {
  # Linhas sem caminhos (/tmp/...) devem caber na largura do banner (72).
  local out line n=0 too_long=0
  new_env
  mkdir -p "$HOME_DIR/.config/tmux"
  printf 'bak\n' >"$HOME_DIR/.bashrc.bak.20260101_000000"
  printf 'atual\n' >"$HOME_DIR/.bashrc"
  out="$(
    in_env bash "$ROOT/scripts/setup-bash.sh" 2>&1
    in_env bash "$ROOT/scripts/setup-tmux.sh" 2>&1
    in_env bash "$ROOT/scripts/setup-git.sh" 2>&1
    in_env bash "$ROOT/scripts/setup-fd.sh" 2>&1
    in_env bash "$ROOT/scripts/restore.sh" bash --yes 2>&1
    in_env bash "$ROOT/scripts/install-packages.sh" --yes desktop 2>&1
  )"
  while IFS= read -r line; do
    [[ "$line" == */tmp/* ]] && continue
    n=$((n + 1))
    if ((${#line} > 72)); then
      too_long=$((too_long + 1))
      printf '  linha longa (%d): %s\n' "${#line}" "$line"
    fi
  done <<<"$out"
  check "há linhas para conferir" test "$n" -gt 20
  assert_eq "nenhuma linha de banner passa de 72 colunas" "0" "$too_long"
}

test_banner_already_configured_says_nothing_to_do() {
  new_env
  local script out
  for script in setup-bash.sh setup-tmux.sh setup-git.sh setup-fd.sh; do
    in_env bash "$ROOT/scripts/$script" >/dev/null 2>&1
    out="$(in_env bash "$ROOT/scripts/$script" 2>&1)"
    assert_contains "$script: segunda execução diz que não há o que fazer" "$out" "Nada a fazer: o resultado desta opção já está em vigor."
    assert_not_contains "$script: não usa a frase ambígua" "$out" "Nada foi alterado."
  done
}
