# shellcheck shell=bash
# Testes de scripts/setup-git.sh e de configs/git/gitconfig.

GIT_SRC_REL="configs/git/gitconfig"

# git_home ARGS...: executa git com o HOME temporário e sem configuração do sistema.
git_home() {
  env "${CLEAN_ENV[@]}" HOME="$HOME_DIR" git "$@"
}

test_setup_git_config_has_no_personal_data() {
  local keys
  keys="$(git config --file "$ROOT/$GIT_SRC_REL" --list | cut -d= -f1)"
  assert_eq "o arquivo versionado é válido" "0" "$(git config --file "$ROOT/$GIT_SRC_REL" --list >/dev/null 2>&1 && echo 0 || echo 1)"
  check_not "sem identidade, credenciais, assinatura ou tokens" grep -E -i \
    '^(user\.|credential\.|gpg\.|http\.|url\.|sendemail\.|github\.)|signingkey|gpgsign|token|password|secret' <<<"$keys"
  check_not "sem helper nem opções de autocorreção" grep -E -i '^(help\.autocorrect|core\.sshcommand|core\.editor)' <<<"$keys"
  check_not "sem e-mail ou chaves no texto" grep -E -i '@[a-z0-9-]+\.[a-z]|BEGIN [A-Z ]*KEY|ghp_' "$ROOT/$GIT_SRC_REL"
}

test_setup_git_creates_and_is_idempotent() {
  new_env
  local rc=0 out before
  in_env bash "$ROOT/scripts/setup-git.sh" >/dev/null || rc=$?
  assert_eq "setup-git cria ~/.gitconfig" "0" "$rc"
  assert_eq "include aponta para o clone" "$ROOT/$GIT_SRC_REL" "$(git_home config --file "$HOME_DIR/.gitconfig" --get-all include.path)"
  assert_eq "sem backup quando não havia arquivo" "" "$(find "$HOME_DIR" -name '*.bak.*')"
  before="$(snapshot "$HOME_DIR")"
  out="$(in_env bash "$ROOT/scripts/setup-git.sh")"
  assert_contains "segunda execução informa já configurado" "$out" "Já configurado"
  assert_eq "segunda execução não altera nada" "$before" "$(snapshot "$HOME_DIR")"
}

test_setup_git_aliases_work_with_real_git() {
  new_env
  in_env bash "$ROOT/scripts/setup-git.sh" >/dev/null
  assert_eq "alias st" "status -sb" "$(git_home config --includes --global --get alias.st)"
  assert_eq "alias co" "checkout" "$(git_home config --includes --global --get alias.co)"
  assert_eq "alias br" "branch" "$(git_home config --includes --global --get alias.br)"
  assert_eq "alias lg" "log --graph --oneline --decorate" "$(git_home config --includes --global --get alias.lg)"
  assert_eq "pull.ff only" "only" "$(git_home config --includes --global --get pull.ff)"
  assert_eq "identidade não definida" "" "$(git_home config --includes --global --get user.name || true)"
  assert_eq "e-mail não definido" "" "$(git_home config --includes --global --get user.email || true)"
  # O alias funciona de fato em um repositório temporário.
  git_home init -q "$ENV_DIR/repo"
  check "git st executa" git_home -C "$ENV_DIR/repo" st
}

test_setup_git_preserves_existing_config() {
  new_env
  local original backups=()
  printf '[user]\n\tname = Fulano\n\temail = fulano@example.invalid\n[alias]\n\tst = status\n[pull]\n\tff = true\n' >"$HOME_DIR/.gitconfig"
  original="$(cat "$HOME_DIR/.gitconfig")"
  chmod 600 "$HOME_DIR/.gitconfig"
  in_env bash "$ROOT/scripts/setup-git.sh" >/dev/null
  mapfile -t backups < <(find "$HOME_DIR" -name '.gitconfig.bak.*')
  assert_eq "um backup criado" "1" "${#backups[@]}"
  assert_eq "backup idêntico ao original" "$original" "$(cat "${backups[0]}")"
  assert_contains "original preservado ao final do arquivo" "$(cat "$HOME_DIR/.gitconfig")" "$original"
  assert_eq "include fica no topo (primeira seção)" "[include]" "$(grep -m1 '^\[' "$HOME_DIR/.gitconfig")"
  assert_eq "nome do usuário preservado" "Fulano" "$(git_home config --includes --global --get user.name)"
  assert_eq "alias do usuário vence o do repositório" "status" "$(git_home config --includes --global --get alias.st)"
  assert_eq "pull.ff do usuário vence" "true" "$(git_home config --includes --global --get pull.ff)"
  assert_eq "demais aliases vêm do repositório" "checkout" "$(git_home config --includes --global --get alias.co)"
  assert_eq "permissões preservadas" "600" "$(stat -c %a "$HOME_DIR/.gitconfig")"
  assert_eq "sem arquivos temporários" "" "$(find "$HOME_DIR" -name '*.new.*')"
}

test_setup_git_dry_run_has_no_side_effects() {
  new_env
  local before out
  before="$(snapshot "$HOME_DIR")"
  in_env bash "$ROOT/scripts/setup-git.sh" --dry-run >/dev/null
  assert_eq "dry-run sem ~/.gitconfig não altera HOME" "$before" "$(snapshot "$HOME_DIR")"
  printf '[user]\n\tname = X\n' >"$HOME_DIR/.gitconfig"
  before="$(snapshot "$HOME_DIR")"
  out="$(in_env bash "$ROOT/scripts/setup-git.sh" --dry-run)"
  assert_eq "dry-run com ~/.gitconfig não altera HOME" "$before" "$(snapshot "$HOME_DIR")"
  assert_contains "dry-run menciona o backup" "$out" "backup"
  assert_eq "dry-run não chama sudo/apt" "" "$(cat "$CALL_LOG")"
}

test_setup_git_symlink_is_conflict() {
  new_env
  printf '[user]\n\tname = X\n' >"$ENV_DIR/real"
  ln -s "$ENV_DIR/real" "$HOME_DIR/.gitconfig"
  local before rc=0 err
  before="$(snapshot "$HOME_DIR")"
  err="$(in_env bash "$ROOT/scripts/setup-git.sh" 2>&1 >/dev/null)" || rc=$?
  assert_eq "link simbólico sai com 2" "2" "$rc"
  assert_contains "mensagem indica CONFLITO" "$err" "CONFLITO"
  assert_eq "nada alterado" "$before" "$(snapshot "$HOME_DIR")"
  assert_eq "arquivo real intacto" "$(printf '[user]\n\tname = X')" "$(cat "$ENV_DIR/real")"
}

test_setup_git_invalid_existing_config_is_untouched() {
  new_env
  printf '[user\n\tname = quebrado\n' >"$HOME_DIR/.gitconfig"
  local before rc=0
  before="$(snapshot "$HOME_DIR")"
  in_env bash "$ROOT/scripts/setup-git.sh" >/dev/null 2>&1 || rc=$?
  check "arquivo inválido faz o script falhar" test "$rc" -ne 0
  assert_eq "arquivo e diretório inalterados (sem backup nem temporário)" "$before" "$(snapshot "$HOME_DIR")"
}

test_setup_git_uses_xdg_config_when_only_it_exists() {
  new_env
  mkdir -p "$HOME_DIR/.config/git"
  printf '[user]\n\tname = Xdg\n' >"$HOME_DIR/.config/git/config"
  in_env bash "$ROOT/scripts/setup-git.sh" >/dev/null
  check "não cria ~/.gitconfig" test ! -e "$HOME_DIR/.gitconfig"
  assert_eq "include no arquivo XDG" "$ROOT/$GIT_SRC_REL" "$(git_home config --file "$HOME_DIR/.config/git/config" --get-all include.path)"
  assert_eq "usuário do XDG preservado" "Xdg" "$(git_home config --includes --global --get user.name)"
  assert_eq "backup ao lado do arquivo XDG" "1" "$(find "$HOME_DIR/.config/git" -name 'config.bak.*' | wc -l)"
  # XDG_CONFIG_HOME personalizado também é respeitado.
  new_env
  mkdir -p "$ENV_DIR/xdg/git"
  printf '[user]\n\tname = Custom\n' >"$ENV_DIR/xdg/git/config"
  in_env env XDG_CONFIG_HOME="$ENV_DIR/xdg" bash "$ROOT/scripts/setup-git.sh" >/dev/null
  assert_eq "include no XDG_CONFIG_HOME personalizado" "$ROOT/$GIT_SRC_REL" "$(git_home config --file "$ENV_DIR/xdg/git/config" --get-all include.path)"
  check "não cria ~/.gitconfig com XDG_CONFIG_HOME" test ! -e "$HOME_DIR/.gitconfig"
}

test_setup_git_missing_git_is_error() {
  new_env
  local rc=0 minbin="$ENV_DIR/minbin"
  mkdir -p "$minbin"
  ln -s "$(command -v bash)" "$minbin/bash"
  ln -s "$(command -v dirname)" "$minbin/dirname"
  env HOME="$HOME_DIR" PATH="$minbin" "$minbin/bash" "$ROOT/scripts/setup-git.sh" >/dev/null 2>&1 </dev/null || rc=$?
  assert_eq "git ausente sai com 1" "1" "$rc"
  assert_eq "nada criado em HOME" "" "$(find "$HOME_DIR" -mindepth 1)"
}

test_setup_git_rejects_unknown_option() {
  new_env
  check_not "opção desconhecida falha" in_env bash "$ROOT/scripts/setup-git.sh" --nada
}
