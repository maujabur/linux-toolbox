# shellcheck shell=bash
# Testes de scripts/restore.sh.

test_restore_latest_backup_and_preserves_current() {
  new_env
  local b="$HOME_DIR/.bashrc" out
  printf 'antigo\n' >"$b.bak.20260101_000000"
  printf 'recente\n' >"$b.bak.20260102_000000"
  printf 'atual\n' >"$b"
  out="$(in_env bash "$ROOT/scripts/restore.sh" bash --yes)"
  assert_eq "restaura o backup mais recente" "recente" "$(cat "$b")"
  assert_contains "informa o backup selecionado" "$out" "$b.bak.20260102_000000"
  assert_eq "backups anteriores intocados" "antigo" "$(cat "$b.bak.20260101_000000")"
  local preserved
  preserved="$(grep -l '^atual$' "$HOME_DIR"/.bashrc.bak.* | head -n 1)"
  check "estado atual preservado em novo backup" test -n "$preserved"
  assert_eq "sem arquivos temporários residuais" "" "$(find "$HOME_DIR" -name '*.restore.*')"
}

test_restore_orders_suffixes_numerically() {
  new_env
  local b="$HOME_DIR/.bashrc"
  printf 'a\n' >"$b.bak.20260101_000000"
  printf 'b\n' >"$b.bak.20260101_000000.2"
  printf 'c\n' >"$b.bak.20260101_000000.10"
  in_env bash "$ROOT/scripts/restore.sh" bash --yes >/dev/null
  assert_eq ".10 é mais recente que .2" "c" "$(cat "$b")"
}

test_restore_explicit_backup() {
  new_env
  local b="$HOME_DIR/.bashrc"
  printf 'antigo\n' >"$b.bak.20260101_000000"
  printf 'recente\n' >"$b.bak.20260102_000000"
  in_env bash "$ROOT/scripts/restore.sh" bash --yes --backup "$b.bak.20260101_000000" >/dev/null
  assert_eq "restaura o backup indicado" "antigo" "$(cat "$b")"
  assert_eq "alvo ausente não gera backup do estado atual" "2" "$(find "$HOME_DIR" -name '.bashrc.bak.*' | wc -l)"
}

test_restore_requires_confirmation() {
  new_env
  local b="$HOME_DIR/.bashrc" rc=0
  printf 'bak\n' >"$b.bak.20260101_000000"
  printf 'atual\n' >"$b"
  in_env bash "$ROOT/scripts/restore.sh" bash >/dev/null 2>&1 || rc=$?
  assert_eq "sem entrada cancela (código 1)" "1" "$rc"
  assert_eq "alvo intacto sem confirmação" "atual" "$(cat "$b")"
  rc=0
  in_env_input 'n\n' bash "$ROOT/scripts/restore.sh" bash >/dev/null 2>&1 || rc=$?
  assert_eq "resposta n cancela" "1" "$rc"
  assert_eq "alvo intacto após recusar" "atual" "$(cat "$b")"
  in_env_input 's\n' bash "$ROOT/scripts/restore.sh" bash >/dev/null 2>&1
  assert_eq "resposta s restaura" "bak" "$(cat "$b")"
}

test_restore_dry_run_has_no_side_effects() {
  new_env
  local b="$HOME_DIR/.bashrc" before out
  printf 'bak\n' >"$b.bak.20260101_000000"
  printf 'atual\n' >"$b"
  before="$(snapshot "$HOME_DIR")"
  out="$(in_env bash "$ROOT/scripts/restore.sh" bash --dry-run)"
  assert_eq "dry-run não altera HOME" "$before" "$(snapshot "$HOME_DIR")"
  assert_contains "dry-run informa o backup" "$out" "$b.bak.20260101_000000"
}

test_restore_failure_keeps_original() {
  new_env
  local b="$HOME_DIR/.bashrc" rc=0
  printf 'atual\n' >"$b"
  # Um diretório com nome de backup não pode ser copiado como arquivo.
  mkdir "$b.bak.20260101_000000"
  in_env bash "$ROOT/scripts/restore.sh" bash --yes --backup "$b.bak.20260101_000000" >/dev/null 2>&1 || rc=$?
  assert_eq "backup inválido falha" "1" "$rc"
  assert_eq "original intacto após falha" "atual" "$(cat "$b")"
  assert_eq "sem temporários após falha" "" "$(find "$HOME_DIR" -name '*.restore.*')"
  # Backup ilegível (arquivo apontando para nada) também não destrói o original.
  rmdir "$b.bak.20260101_000000"
  ln -s /nao/existe "$b.bak.20260101_000000"
  rc=0
  in_env bash "$ROOT/scripts/restore.sh" bash --yes --backup "$b.bak.20260101_000000" >/dev/null 2>&1 || rc=$?
  assert_eq "backup que é link é restaurado como link" "0" "$rc"
  check "alvo agora é o link restaurado" test -L "$b"
  assert_eq "estado anterior sempre recuperável" "1" "$(grep -l '^atual$' "$HOME_DIR"/.bashrc* 2>/dev/null | wc -l)"
}

test_restore_rejects_foreign_backup_and_missing() {
  new_env
  local b="$HOME_DIR/.bashrc" rc=0
  printf 'atual\n' >"$b"
  printf 'x\n' >"$HOME_DIR/outro"
  in_env bash "$ROOT/scripts/restore.sh" bash --yes --backup "$HOME_DIR/outro" >/dev/null 2>&1 || rc=$?
  assert_eq "backup fora do padrão é rejeitado" "1" "$rc"
  rc=0
  in_env bash "$ROOT/scripts/restore.sh" bash --yes >/dev/null 2>&1 || rc=$?
  assert_eq "sem backups disponíveis falha" "1" "$rc"
  assert_eq "original intacto" "atual" "$(cat "$b")"
  check_not "alvo desconhecido falha" in_env bash "$ROOT/scripts/restore.sh" zsh --yes
}

test_restore_tmux_replaces_symlink_safely() {
  new_env
  local t="$HOME_DIR/.config/tmux/tmux.conf"
  in_env bash "$ROOT/scripts/setup-tmux.sh" >/dev/null
  rm "$t"
  printf 'original\n' >"$t"
  in_env bash "$ROOT/scripts/setup-tmux.sh" >/dev/null # cria backup do original e o link
  check "tmux.conf agora é link" test -L "$t"
  in_env bash "$ROOT/scripts/restore.sh" tmux --yes >/dev/null
  check "após restaurar não é mais link" test ! -L "$t"
  assert_eq "conteúdo original restaurado" "original" "$(cat "$t")"
  local links
  links="$(find "$HOME_DIR/.config/tmux" -name 'tmux.conf.bak.*' -type l | wc -l)"
  assert_eq "link anterior preservado como backup" "1" "$links"
}
