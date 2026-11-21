# shellcheck shell=bash
# shellcheck disable=SC2016
# Verificações estáticas: sintaxe, lint, formatação, modos e referências.

shell_files() {
  (cd "$ROOT" && find . -name '*.sh' -not -path './.git/*' | sed 's|^\./||' | LC_ALL=C sort)
}

test_static_syntax() {
  local f
  while read -r f; do
    check "bash -n $f" bash -n "$ROOT/$f"
  done < <(shell_files)
}

test_static_shellcheck() {
  local files=()
  mapfile -t files < <(shell_files)
  if ! command -v shellcheck >/dev/null; then
    if [[ "${REQUIRE_LINT:-0}" == 1 ]]; then fail "shellcheck ausente"; else skip "shellcheck ausente"; fi
    return
  fi
  check "shellcheck sem avisos" bash -c 'cd "$1" && shift && shellcheck -x "$@"' _ "$ROOT" "${files[@]}"
}

test_static_shfmt() {
  local files=()
  mapfile -t files < <(shell_files)
  if ! command -v shfmt >/dev/null; then
    if [[ "${REQUIRE_LINT:-0}" == 1 ]]; then fail "shfmt ausente"; else skip "shfmt ausente"; fi
    return
  fi
  check "shfmt -i 2 -ci sem diferenças" bash -c 'cd "$1" && shift && shfmt -i 2 -ci -d "$@"' _ "$ROOT" "${files[@]}"
}

test_static_modes() {
  local f
  for f in bootstrap.sh tests/run.sh scripts/install-packages.sh scripts/setup-bash.sh \
    scripts/setup-fd.sh scripts/setup-tmux.sh scripts/setup-git.sh scripts/restore.sh scripts/update.sh scripts/profile.sh; do
    [[ -e "$ROOT/$f" ]] || continue
    check "executável: $f" test -x "$ROOT/$f"
  done
  check_not "scripts/lib.sh não é executável (apenas carregado)" test -x "$ROOT/scripts/lib.sh"
}

test_static_packages() {
  local file name dups
  for file in "$ROOT"/packages/*.txt; do
    dups="$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$file" | sort | uniq -d)"
    assert_eq "sem pacotes duplicados em $(basename "$file")" "" "$dups"
    while read -r name; do
      check "nome de pacote válido: $name" bash -c '[[ "$1" =~ ^[a-z0-9][a-z0-9+.-]+$ ]]' _ "$name"
    done < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$file")
  done
}

test_static_references() {
  local ref profile
  while read -r ref; do
    check "bootstrap referencia script existente: $ref" test -f "$ROOT/$ref"
  done < <(grep -oE 'run_script [a-z-]+\.sh|scripts/[a-z-]+\.sh' "$ROOT/bootstrap.sh" | sed -e 's|^run_script |scripts/|' | sort -u)
  check "bootstrap referencia update.sh" grep -q 'scripts/update.sh' "$ROOT/bootstrap.sh"
  while read -r profile; do
    check "perfil existe: packages/$profile.txt" test -f "$ROOT/packages/$profile.txt"
  done < <(grep -oE 'run_script install-packages\.sh [a-z]+' "$ROOT/bootstrap.sh" | awk '{print $3}' | sort -u)
}

test_static_readme_urls_match_update_script() {
  local repo tarball
  repo="$(sed -n 's/^DEFAULT_REPO_URL="\(.*\)"$/\1/p' "$ROOT/scripts/update.sh")"
  tarball="$(sed -n 's/^DEFAULT_TARBALL_URL="\(.*\)"$/\1/p' "$ROOT/scripts/update.sh")"
  check "update.sh define as URLs padrão" test -n "$repo" -a -n "$tarball"
  check "README cita a URL do clone usada pelo update.sh" grep -qF "$repo" "$ROOT/README.md"
  check "README cita a URL do tarball usada pelo update.sh" grep -qF "$tarball" "$ROOT/README.md"
  check "README cita a pasta extraída do tarball" grep -qF 'cd linux-toolbox-main' "$ROOT/README.md"
  check_not "README não recomenda executar código baixado direto da rede" \
    grep -E 'curl[^`]*\|[[:space:]]*(sudo[[:space:]]+)?(ba)?sh([[:space:]]|$)|wget[^`]*\|[[:space:]]*(sudo[[:space:]]+)?(ba)?sh([[:space:]]|$)' "$ROOT/README.md"
  check "README cobre os quatro cenários" bash -c 'for s in "### A." "### B." "### C." "### D."; do grep -qF "$s" "$1" || exit 1; done' _ "$ROOT/README.md"
}
