# shellcheck shell=bash
# Testes de scripts/setup-tmux.sh e scripts/setup-fd.sh.

TMUX_TARGET_REL=".config/tmux/tmux.conf"

test_setup_tmux_creates_link_idempotently() {
  new_env
  local out
  in_env bash "$ROOT/scripts/setup-tmux.sh" >/dev/null
  assert_eq "link criado" "$ROOT/configs/tmux/tmux.conf" "$(readlink "$HOME_DIR/$TMUX_TARGET_REL")"
  out="$(in_env bash "$ROOT/scripts/setup-tmux.sh")"
  assert_contains "segunda execução informa já configurado" "$out" "Já configurado"
  assert_eq "sem backups quando não havia arquivo" "" "$(find "$HOME_DIR" -name '*.bak.*')"
}

test_setup_tmux_backs_up_existing_file_and_link() {
  new_env
  mkdir -p "$HOME_DIR/.config/tmux"
  printf 'set -g mouse off\n' >"$HOME_DIR/$TMUX_TARGET_REL"
  in_env bash "$ROOT/scripts/setup-tmux.sh" >/dev/null
  local backups=()
  mapfile -t backups < <(find "$HOME_DIR/.config/tmux" -name 'tmux.conf.bak.*')
  assert_eq "um backup do arquivo" "1" "${#backups[@]}"
  assert_eq "backup preserva o conteúdo" "set -g mouse off" "$(cat "${backups[0]}")"
  # Link para outro destino também é preservado.
  rm "$HOME_DIR/$TMUX_TARGET_REL"
  ln -s /outro/destino "$HOME_DIR/$TMUX_TARGET_REL"
  in_env bash "$ROOT/scripts/setup-tmux.sh" >/dev/null
  mapfile -t backups < <(find "$HOME_DIR/.config/tmux" -name 'tmux.conf.bak.*' -type l)
  assert_eq "link anterior preservado como backup" "1" "${#backups[@]}"
  assert_eq "backup do link mantém o destino" "/outro/destino" "$(readlink "${backups[0]}")"
}

test_setup_tmux_dry_run_has_no_side_effects() {
  new_env
  local before out
  before="$(snapshot "$HOME_DIR")"
  in_env bash "$ROOT/scripts/setup-tmux.sh" --dry-run >/dev/null
  assert_eq "dry-run sem config não altera HOME" "$before" "$(snapshot "$HOME_DIR")"
  mkdir -p "$HOME_DIR/.config/tmux"
  printf 'x\n' >"$HOME_DIR/$TMUX_TARGET_REL"
  before="$(snapshot "$HOME_DIR")"
  out="$(in_env bash "$ROOT/scripts/setup-tmux.sh" --dry-run)"
  assert_eq "dry-run com config existente não altera HOME" "$before" "$(snapshot "$HOME_DIR")"
  assert_contains "dry-run menciona backup" "$out" "backup"
}

test_setup_tmux_config_is_valid() {
  if ! command -v tmux >/dev/null; then
    skip "tmux ausente: validação da configuração"
    return
  fi
  new_env
  local sock="$ENV_DIR/tmux.sock"
  # Servidor isolado (socket próprio, HOME temporário); encerrado ao final.
  check "tmux aceita configs/tmux/tmux.conf" env HOME="$HOME_DIR" TMUX_TMPDIR="$ENV_DIR" \
    tmux -S "$sock" -f "$ROOT/configs/tmux/tmux.conf" new-session -d \; show-options -g mouse
  env HOME="$HOME_DIR" tmux -S "$sock" kill-server >/dev/null 2>&1 || true
}

test_setup_fd_creates_link_idempotently() {
  new_env
  local out rc=0
  in_env bash "$ROOT/scripts/setup-fd.sh" >/dev/null
  assert_eq "link fd criado" "$FAKE_BIN/fdfind" "$(readlink "$HOME_DIR/.local/bin/fd")"
  out="$(in_env bash "$ROOT/scripts/setup-fd.sh")" || rc=$?
  assert_eq "segunda execução sai com 0" "0" "$rc"
  assert_contains "segunda execução informa já configurado" "$out" "Já configurado"
}

test_setup_fd_conflict_is_distinct_and_untouched() {
  new_env
  mkdir -p "$HOME_DIR/.local/bin"
  printf '#!/bin/sh\necho outro-fd\n' >"$HOME_DIR/.local/bin/fd"
  local before rc=0 err
  before="$(snapshot "$HOME_DIR")"
  err="$(in_env bash "$ROOT/scripts/setup-fd.sh" 2>&1 >/dev/null)" || rc=$?
  assert_eq "conflito sai com código 2" "2" "$rc"
  assert_contains "mensagem indica CONFLITO" "$err" "CONFLITO"
  assert_eq "executável existente intocado" "$before" "$(snapshot "$HOME_DIR")"
  # Link para outro destino também é conflito.
  rm "$HOME_DIR/.local/bin/fd"
  ln -s /usr/bin/true "$HOME_DIR/.local/bin/fd"
  rc=0
  in_env bash "$ROOT/scripts/setup-fd.sh" >/dev/null 2>&1 || rc=$?
  assert_eq "link para outro destino é conflito (2)" "2" "$rc"
  assert_eq "link existente não foi alterado" "/usr/bin/true" "$(readlink "$HOME_DIR/.local/bin/fd")"
}

test_setup_fd_missing_fdfind_is_error() {
  new_env
  local rc=0 minbin="$ENV_DIR/minbin"
  # PATH mínimo, sem fdfind, para o teste ser conclusivo em qualquer máquina.
  mkdir -p "$minbin"
  ln -s "$(command -v bash)" "$minbin/bash"
  ln -s "$(command -v dirname)" "$minbin/dirname"
  env HOME="$HOME_DIR" PATH="$minbin" "$minbin/bash" "$ROOT/scripts/setup-fd.sh" >/dev/null 2>&1 </dev/null || rc=$?
  assert_eq "fdfind ausente sai com 1" "1" "$rc"
  assert_eq "nada criado em HOME" "" "$(find "$HOME_DIR" -mindepth 1)"
}

test_setup_fd_dry_run_has_no_side_effects() {
  new_env
  local before out
  before="$(snapshot "$HOME_DIR")"
  out="$(in_env bash "$ROOT/scripts/setup-fd.sh" --dry-run)"
  assert_eq "dry-run não altera HOME" "$before" "$(snapshot "$HOME_DIR")"
  assert_contains "dry-run descreve o link" "$out" "[dry-run]"
}
