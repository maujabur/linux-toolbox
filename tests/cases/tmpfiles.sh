# shellcheck shell=bash
# shellcheck disable=SC2016
# Regressão: arquivos temporários de setup-git.sh e restore.sh (e backup_copy).
# Os cenários vêm da verificação adversarial: arquivos ou links preexistentes
# em caminhos previsíveis (NOME.new.PID, NOME.restore.PID) não podem ser
# reutilizados, sobrescritos nem apagados pelos scripts. O PID é conhecido de
# antemão com "bash -c 'prepara; exec bash script'" (o exec mantém o PID).

# run_prepared 'PREPARO' SCRIPT ARGS...: roda PREPARO (que pode usar $HOME e $$)
# e então executa o script com o mesmo PID, no ambiente isolado.
run_prepared() {
  local prep="$1"
  shift
  in_env bash -c "$prep"'; exec bash "$@"' _ "$@"
}

# Os testes com chmod não valem para root (root ignora as permissões).
needs_non_root() {
  if ((EUID == 0)); then
    skip "$1 (executando como root)"
    return 1
  fi
}

test_tmp_setup_git_stale_file_is_not_merged_when_target_is_missing() {
  new_env
  local rc=0
  run_prepared 'printf "[user]\n\tname = residuo-antigo\n" >"$HOME/.gitconfig.new.$$"' \
    "$ROOT/scripts/setup-git.sh" >/dev/null 2>&1 || rc=$?
  assert_eq "setup-git conclui" "0" "$rc"
  assert_not_contains "o resíduo não contamina o .gitconfig novo" "$(cat "$HOME_DIR/.gitconfig")" "residuo-antigo"
  assert_contains "o include foi gravado" "$(cat "$HOME_DIR/.gitconfig")" "[include]"
  assert_eq "o arquivo alheio continua lá, intacto" "1" "$(grep -c residuo-antigo "$HOME_DIR"/.gitconfig.new.* | cut -d: -f2 | head -n1)"
}

test_tmp_setup_git_does_not_follow_preexisting_symlink() {
  new_env
  local rc=0 original
  printf '[user]\n\tname = X\n' >"$HOME_DIR/.gitconfig"
  original="$(cat "$HOME_DIR/.gitconfig")"
  run_prepared 'printf "dado importante da vitima\n" >"$HOME/vitima"; ln -s "$HOME/vitima" "$HOME/.gitconfig.new.$$"' \
    "$ROOT/scripts/setup-git.sh" >/dev/null 2>&1 || rc=$?
  assert_eq "setup-git conclui" "0" "$rc"
  assert_eq "o arquivo apontado pelo link não foi tocado" "dado importante da vitima" "$(cat "$HOME_DIR/vitima")"
  check "o .gitconfig continua sendo arquivo regular" test -f "$HOME_DIR/.gitconfig" -a ! -L "$HOME_DIR/.gitconfig"
  assert_contains "o original está preservado no .gitconfig" "$(cat "$HOME_DIR/.gitconfig")" "$original"
  assert_eq "o backup tem o original" "$original" "$(cat "$(find "$HOME_DIR" -maxdepth 1 -name '.gitconfig.bak.*')")"
  check "o link preexistente continua sendo link" test -L "$HOME_DIR"/.gitconfig.new.*
}

test_tmp_setup_git_symlink_with_missing_target() {
  new_env
  local rc=0
  run_prepared 'printf "dado importante da vitima\n" >"$HOME/vitima"; ln -s "$HOME/vitima" "$HOME/.gitconfig.new.$$"' \
    "$ROOT/scripts/setup-git.sh" >/dev/null 2>&1 || rc=$?
  assert_eq "setup-git conclui" "0" "$rc"
  assert_eq "o arquivo apontado pelo link não recebeu nada" "dado importante da vitima" "$(cat "$HOME_DIR/vitima")"
  assert_contains "o .gitconfig foi criado com o include" "$(cat "$HOME_DIR/.gitconfig")" "[include]"
}

test_tmp_setup_git_never_deletes_foreign_files() {
  new_env
  local rc=0
  # Arquivo alheio inválido como config: antes, o git falhava e o trap o apagava.
  run_prepared 'printf "ARQUIVO ALHEIO IMPORTANTE\n" >"$HOME/.gitconfig.new.$$"' \
    "$ROOT/scripts/setup-git.sh" >/dev/null 2>&1 || rc=$?
  assert_eq "setup-git conclui" "0" "$rc"
  assert_eq "o arquivo alheio não foi apagado nem alterado" "ARQUIVO ALHEIO IMPORTANTE" "$(cat "$HOME_DIR"/.gitconfig.new.*)"
  # Com o alvo existente, antes o arquivo alheio era sobrescrito e movido.
  new_env
  printf '[user]\n\tname = X\n' >"$HOME_DIR/.gitconfig"
  run_prepared 'printf "ARQUIVO ALHEIO IMPORTANTE\n" >"$HOME/.gitconfig.new.$$"' \
    "$ROOT/scripts/setup-git.sh" >/dev/null 2>&1
  assert_eq "alvo existente: o arquivo alheio continua intacto" "ARQUIVO ALHEIO IMPORTANTE" "$(cat "$HOME_DIR"/.gitconfig.new.*)"
  assert_not_contains "alvo existente: o alheio não virou o .gitconfig" "$(cat "$HOME_DIR/.gitconfig")" "ALHEIO"
}

test_tmp_setup_git_cleans_only_its_own_directory_on_failure() {
  needs_non_root "falha após o mktemp" || return 0
  new_env
  local rc=0
  printf '[user]\n\tname = X\n' >"$HOME_DIR/.gitconfig"
  chmod 000 "$HOME_DIR/.gitconfig"
  in_env bash "$ROOT/scripts/setup-git.sh" >/dev/null 2>&1 || rc=$?
  chmod 600 "$HOME_DIR/.gitconfig"
  check "falha quando o alvo é ilegível" test "$rc" -ne 0
  assert_eq "nenhum diretório temporário sobrou" "" "$(leftover_tmpdirs "$HOME_DIR")"
  assert_eq "o alvo não foi alterado" "$(printf '[user]\n\tname = X')" "$(cat "$HOME_DIR/.gitconfig")"
}

test_tmp_setup_git_new_file_gets_default_mode() {
  new_env
  : >"$HOME_DIR/controle"
  in_env bash "$ROOT/scripts/setup-git.sh" >/dev/null 2>&1
  assert_eq "arquivo novo tem o modo padrão (não o 0600 do mktemp)" "$(stat -c %a "$HOME_DIR/controle")" "$(stat -c %a "$HOME_DIR/.gitconfig")"
  assert_eq "nenhum diretório temporário sobrou" "" "$(leftover_tmpdirs "$HOME_DIR")"
}

test_tmp_restore_preserves_foreign_file_and_symlink() {
  new_env
  local rc=0
  printf 'bak\n' >"$HOME_DIR/.bashrc.bak.20260101_000000"
  printf 'atual\n' >"$HOME_DIR/.bashrc"
  run_prepared 'printf "ARQUIVO ALHEIO\n" >"$HOME/.bashrc.restore.$$"' \
    "$ROOT/scripts/restore.sh" bash --yes >/dev/null 2>&1 || rc=$?
  assert_eq "restore conclui" "0" "$rc"
  assert_eq "o .bashrc foi restaurado" "bak" "$(cat "$HOME_DIR/.bashrc")"
  assert_eq "o arquivo alheio continua intacto" "ARQUIVO ALHEIO" "$(cat "$HOME_DIR"/.bashrc.restore.*)"
  new_env
  printf 'bak\n' >"$HOME_DIR/.bashrc.bak.20260101_000000"
  printf 'atual\n' >"$HOME_DIR/.bashrc"
  run_prepared 'printf "vitima intacta\n" >"$HOME/vitima"; ln -s "$HOME/vitima" "$HOME/.bashrc.restore.$$"' \
    "$ROOT/scripts/restore.sh" bash --yes >/dev/null 2>&1
  assert_eq "link preexistente: o arquivo apontado não foi tocado" "vitima intacta" "$(cat "$HOME_DIR/vitima")"
  assert_eq "link preexistente: restauração concluída" "bak" "$(cat "$HOME_DIR/.bashrc")"
}

test_tmp_restore_failure_keeps_target_and_foreign_file() {
  needs_non_root "backup ilegível" || return 0
  new_env
  local rc=0
  printf 'atual\n' >"$HOME_DIR/.bashrc"
  printf 'bak\n' >"$HOME_DIR/.bashrc.bak.20260101_000000"
  chmod 000 "$HOME_DIR/.bashrc.bak.20260101_000000"
  run_prepared 'printf "ARQUIVO ALHEIO IMPORTANTE\n" >"$HOME/.bashrc.restore.$$"' \
    "$ROOT/scripts/restore.sh" bash --yes >/dev/null 2>&1 || rc=$?
  chmod 600 "$HOME_DIR/.bashrc.bak.20260101_000000"
  check "restore falha com backup ilegível" test "$rc" -ne 0
  assert_eq "o alvo continua intacto" "atual" "$(cat "$HOME_DIR/.bashrc")"
  assert_eq "o arquivo alheio não foi apagado pelo trap" "ARQUIVO ALHEIO IMPORTANTE" "$(cat "$HOME_DIR"/.bashrc.restore.*)"
  assert_eq "nenhum diretório temporário sobrou" "" "$(leftover_tmpdirs "$HOME_DIR")"
}

test_tmp_restore_restores_symlink_backup_as_symlink() {
  new_env
  mkdir -p "$HOME_DIR/.config/tmux"
  ln -s /destino/qualquer "$HOME_DIR/.config/tmux/tmux.conf.bak.20260101_000000"
  printf 'atual\n' >"$HOME_DIR/.config/tmux/tmux.conf"
  in_env bash "$ROOT/scripts/restore.sh" tmux --yes >/dev/null 2>&1
  check "o link do backup foi restaurado como link" test -L "$HOME_DIR/.config/tmux/tmux.conf"
  assert_eq "o destino do link foi preservado" "/destino/qualquer" "$(readlink "$HOME_DIR/.config/tmux/tmux.conf")"
  assert_eq "nenhum diretório temporário sobrou" "" "$(leftover_tmpdirs "$HOME_DIR")"
}

test_tmp_unwritable_directory_fails_cleanly() {
  needs_non_root "diretório sem escrita" || return 0
  new_env
  local rc=0 out
  printf 'bak\n' >"$HOME_DIR/.bashrc.bak.20260101_000000"
  printf 'atual\n' >"$HOME_DIR/.bashrc"
  chmod 555 "$HOME_DIR"
  out="$(in_env bash "$ROOT/scripts/setup-git.sh" 2>&1)" || rc=$?
  assert_eq "setup-git sem escrita sai com 1" "1" "$rc"
  assert_contains "setup-git explica o diretório temporário" "$out" "diretório temporário"
  rc=0
  out="$(in_env bash "$ROOT/scripts/restore.sh" bash --yes 2>&1)" || rc=$?
  assert_eq "restore sem escrita sai com 1" "1" "$rc"
  assert_contains "restore explica o diretório temporário" "$out" "diretório temporário"
  chmod 755 "$HOME_DIR"
  assert_eq "o .bashrc não foi alterado" "atual" "$(cat "$HOME_DIR/.bashrc")"
  check "o .gitconfig não foi criado" test ! -e "$HOME_DIR/.gitconfig"
}

test_tmp_backup_copy_skips_preexisting_symlink_name() {
  new_env
  local f="$HOME_DIR/arquivo" b
  printf 'original\n' >"$f"
  ln -s "$HOME_DIR/vitima" "$f.bak.20260101_000000"
  b="$( (
    source "$ROOT/scripts/lib.sh"
    date() { echo 20260101_000000; }
    backup_copy "$f"
  ))"
  assert_eq "pula o nome ocupado por um link (mesmo quebrado)" "$f.bak.20260101_000000.1" "$b"
  check "o arquivo apontado pelo link não foi criado" test ! -e "$HOME_DIR/vitima"
  check "o link preexistente continua intacto" test -L "$f.bak.20260101_000000"
  assert_eq "o backup tem o conteúdo" "original" "$(cat "$b")"
}
