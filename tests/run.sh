#!/usr/bin/env bash
# Testes em Bash puro. Não alteram a máquina: usam HOME temporário e
# comandos simulados (sudo, apt-get, fdfind) no início do PATH.
# Uso: bash tests/run.sh [filtro]   (REQUIRE_LINT=1 exige shellcheck e shfmt)
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
FILTER="${1:-}"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TMP_ROOT"' EXIT

PASS=0
FAIL=0
SKIP=0
ENV_COUNT=0

ok() {
  PASS=$((PASS + 1))
  printf 'ok    %s\n' "$1"
}
fail() {
  FAIL=$((FAIL + 1))
  printf 'FALHA %s\n' "$1"
}
skip() {
  SKIP=$((SKIP + 1))
  printf 'pulou %s\n' "$1"
}

# check "descrição" comando...: passa se o comando retornar 0.
check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else fail "$desc"; fi
}
# check_not "descrição" comando...: passa se o comando retornar diferente de 0.
check_not() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then fail "$desc"; else ok "$desc"; fi
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then
    ok "$1"
  else
    fail "$1 (esperado: [$2] obtido: [$3])"
  fi
}
assert_contains() {
  if [[ "$2" == *"$3"* ]]; then
    ok "$1"
  else
    fail "$1 (não contém: [$3]; texto: [$2])"
  fi
}
assert_not_contains() {
  if [[ "$2" != *"$3"* ]]; then
    ok "$1"
  else
    fail "$1 (contém: [$3])"
  fi
}

# new_env: cria HOME_DIR, FAKE_BIN e CALL_LOG isolados para um teste.
# shellcheck disable=SC2016
new_env() {
  ENV_COUNT=$((ENV_COUNT + 1))
  ENV_DIR="$TMP_ROOT/env$ENV_COUNT"
  HOME_DIR="$ENV_DIR/home"
  FAKE_BIN="$ENV_DIR/bin"
  CALL_LOG="$ENV_DIR/calls.log"
  mkdir -p "$HOME_DIR" "$FAKE_BIN"
  : >"$CALL_LOG"
  # sudo e apt-get simulados: apenas registram a chamada e não executam nada.
  printf '#!/usr/bin/env bash\necho "sudo $*" >>"$FAKE_LOG"\n' >"$FAKE_BIN/sudo"
  printf '#!/usr/bin/env bash\necho "apt-get $*" >>"$FAKE_LOG"\n' >"$FAKE_BIN/apt-get"
  printf '#!/usr/bin/env bash\necho fake-fd\n' >"$FAKE_BIN/fdfind"
  chmod +x "$FAKE_BIN/sudo" "$FAKE_BIN/apt-get" "$FAKE_BIN/fdfind"
}

# in_env comando...: executa com HOME e PATH simulados e sem entrada (stdin vazio).
in_env() {
  env HOME="$HOME_DIR" PATH="$FAKE_BIN:$PATH" FAKE_LOG="$CALL_LOG" "$@" </dev/null
}
# in_env_input "texto" comando...: igual a in_env, mas com texto no stdin.
in_env_input() {
  local input="$1"
  shift
  printf '%b' "$input" | env HOME="$HOME_DIR" PATH="$FAKE_BIN:$PATH" FAKE_LOG="$CALL_LOG" "$@"
}

# snapshot DIR: lista caminho, tipo, tamanho, modo, mtime e destino de links.
snapshot() {
  find "$1" -printf '%P|%y|%s|%m|%T@|%l\n' | LC_ALL=C sort
}

for case_file in "$ROOT"/tests/cases/*.sh; do
  [[ -e "$case_file" ]] || continue
  # shellcheck source=/dev/null
  source "$case_file"
done

while read -r name; do
  [[ "$name" == test_* ]] || continue
  [[ -z "$FILTER" || "$name" == *"$FILTER"* ]] || continue
  printf '== %s\n' "$name"
  "$name"
done < <(declare -F | awk '{print $3}' | LC_ALL=C sort)

printf '\nResumo: %d passaram, %d falharam, %d puladas\n' "$PASS" "$FAIL" "$SKIP"
((FAIL == 0))
