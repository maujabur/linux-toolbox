# shellcheck shell=bash
# Testes de scripts/lib.sh (backup_copy e confirm).

test_lib_backup_never_overwrites() {
  new_env
  local f="$HOME_DIR/arquivo" b1 b2 b3
  printf 'original\n' >"$f"
  # Força o mesmo timestamp para provocar colisões de nome.
  b1="$( (
    source "$ROOT/scripts/lib.sh"
    date() { echo 20260101_000000; }
    backup_copy "$f"
  ))"
  printf 'segundo\n' >"$f"
  b2="$( (
    source "$ROOT/scripts/lib.sh"
    date() { echo 20260101_000000; }
    backup_copy "$f"
  ))"
  b3="$( (
    source "$ROOT/scripts/lib.sh"
    date() { echo 20260101_000000; }
    backup_copy "$f"
  ))"
  assert_eq "primeiro backup usa o timestamp" "$f.bak.20260101_000000" "$b1"
  assert_eq "segundo backup recebe sufixo .1" "$f.bak.20260101_000000.1" "$b2"
  assert_eq "terceiro backup recebe sufixo .2" "$f.bak.20260101_000000.2" "$b3"
  assert_eq "primeiro backup mantém o conteúdo" "original" "$(cat "$b1")"
  assert_eq "segundo backup tem o conteúdo da época" "segundo" "$(cat "$b2")"
}

test_lib_backup_preserves_symlink_and_mode() {
  new_env
  local link="$HOME_DIR/link" file="$HOME_DIR/f" b
  ln -s /alvo/qualquer "$link"
  b="$( (
    source "$ROOT/scripts/lib.sh"
    backup_copy "$link"
  ))"
  check "backup de link continua sendo link" test -L "$b"
  assert_eq "backup de link aponta para o mesmo destino" "/alvo/qualquer" "$(readlink "$b")"
  printf 'x' >"$file"
  chmod 600 "$file"
  b="$( (
    source "$ROOT/scripts/lib.sh"
    backup_copy "$file"
  ))"
  assert_eq "backup preserva permissões" "600" "$(stat -c %a "$b")"
}

test_lib_backup_failure_leaves_no_reservation() {
  new_env
  local d="$HOME_DIR/dir" rc=0
  mkdir "$d"
  (
    source "$ROOT/scripts/lib.sh"
    backup_copy "$d"
  ) >/dev/null 2>&1 || rc=$?
  check "backup de diretório falha" test "$rc" -ne 0
  assert_eq "nenhum arquivo de backup residual" "" "$(find "$HOME_DIR" -maxdepth 1 -name 'dir.bak.*')"
}

# shellcheck disable=SC2031
test_lib_confirm() {
  local answer rc
  for answer in 's\n' 'S\n' 'sim\n' 'SIM\n'; do
    rc=0
    printf '%b' "$answer" | (
      source "$ROOT/scripts/lib.sh"
      confirm "ok?"
    ) >/dev/null 2>&1 || rc=$?
    assert_eq "confirm aceita ${answer%\\n}" "0" "$rc"
  done
  for answer in 'n\n' '\n' 'y\n' 'talvez\n' ''; do
    rc=0
    printf '%b' "$answer" | (
      source "$ROOT/scripts/lib.sh"
      confirm "ok?"
    ) >/dev/null 2>&1 || rc=$?
    assert_eq "confirm recusa [${answer%\\n}]" "1" "$rc"
  done
  rc=0
  (
    source "$ROOT/scripts/lib.sh"
    ASSUME_YES=1 confirm "ok?"
  ) </dev/null >/dev/null 2>&1 || rc=$?
  assert_eq "confirm com ASSUME_YES=1 aceita sem entrada" "0" "$rc"
}
