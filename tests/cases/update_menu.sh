# shellcheck shell=bash
# Testes da opção 9 do menu (atualizar). Usam make_clone de update.sh: nunca este clone.

test_update_bootstrap_option_9() {
  make_clone
  local new out before
  before="$(snapshot "$CLONE")"
  in_env_input '9\n\n0\n' bash "$CLONE/bootstrap.sh" --dry-run >/dev/null 2>&1
  assert_eq "opção 9 em dry-run não altera o clone" "$before" "$(snapshot "$CLONE")"
  new="$(publish_new_version)"
  out="$(in_env_input '9\ns\n' bash "$CLONE/bootstrap.sh" 2>&1)"
  assert_eq "opção 9 atualiza o clone" "$new" "$(head_of "$CLONE")"
  assert_contains "pede para executar o bootstrap de novo" "$out" "Execute o bootstrap novamente"
  assert_eq "encerra sem redesenhar o menu" "1" "$(grep -c 'Configurar aliases do Bash' <<<"$out")"
  assert_not_contains "não pausa antes de encerrar após atualizar" "$out" "Enter = voltar ao menu"
}

test_update_bootstrap_option_9_when_current() {
  make_clone
  local out
  out="$(in_env_input '9\n\n0\n' bash "$CLONE/bootstrap.sh" 2>&1)"
  assert_contains "informa já atualizado" "$out" "Já atualizado"
  assert_eq "volta ao menu depois da pausa" "2" "$(grep -c 'Configurar aliases do Bash' <<<"$out")"
}
