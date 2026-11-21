# shellcheck shell=bash
# shellcheck disable=SC2016
# Testes de scripts/profile.sh e dos arquivos em profiles/. O sistema e o
# hardware são simulados (os-release e device-tree falsos); apt-get e sudo são
# os simulados de new_env. Nada é instalado.

# new_prof_env [MODELO]: new_env + os-release Debian e modelo de hardware simulados.
new_prof_env() {
  new_env
  PROF_OS="$ENV_DIR/os-release"
  PROF_MODEL="$ENV_DIR/model"
  PROF_SCRIPT="$ROOT/scripts/profile.sh"
  printf 'ID=debian\nVERSION_ID="13"\n' >"$PROF_OS"
  printf '%s\0' "${1:-Raspberry Pi 5 Model B Rev 1.0}" >"$PROF_MODEL"
}

# prof ARGS...: executa profile.sh (stdin vazio) no ambiente simulado.
prof() {
  in_env env TOOLBOX_TEST_OS_RELEASE_FILE="$PROF_OS" TOOLBOX_TEST_DT_MODEL_FILE="$PROF_MODEL" bash "$PROF_SCRIPT" "$@"
}
# prof_input "texto" ARGS...: igual a prof, com texto no stdin.
prof_input() {
  local input="$1"
  shift
  in_env_input "$input" env TOOLBOX_TEST_OS_RELEASE_FILE="$PROF_OS" TOOLBOX_TEST_DT_MODEL_FILE="$PROF_MODEL" bash "$PROF_SCRIPT" "$@"
}

# make_tree: copia scripts/, profiles/, packages/ e configs/ para uma árvore
# temporária, para testar perfis alterados sem tocar nos reais.
make_tree() {
  TREE="$ENV_DIR/tree"
  mkdir -p "$TREE"
  cp -r "$ROOT/scripts" "$ROOT/profiles" "$ROOT/packages" "$ROOT/configs" "$TREE/"
  PROF_SCRIPT="$TREE/scripts/profile.sh"
}

test_profile_list() {
  new_prof_env
  local out
  out="$(prof list 2>/dev/null)"
  assert_contains "lista debian-desktop" "$out" "debian-desktop"
  assert_contains "lista debian-server" "$out" "debian-server"
  assert_contains "lista raspberry-pi-headless" "$out" "raspberry-pi-headless"
  assert_contains "mostra a descrição" "$out" "Debian com desktop KDE"
  assert_not_contains "no Pi simulado nada é marcado indisponível" "$out" "indisponível"
  printf 'Dell XPS\0' >"$PROF_MODEL"
  out="$(prof list 2>/dev/null)"
  assert_contains "fora de um Pi o perfil do Pi aparece como indisponível" "$out" "raspberry-pi-headless"
  assert_contains "marca como indisponível nesta máquina" "$out" "indisponível nesta máquina"
}

test_profile_show_plan_order_and_no_side_effects() {
  new_prof_env
  local before out rc=0
  before="$(snapshot "$HOME_DIR")"
  out="$(prof show debian-desktop 2>/dev/null)" || rc=$?
  assert_eq "show sai com 0" "0" "$rc"
  assert_eq "show não altera HOME" "$before" "$(snapshot "$HOME_DIR")"
  assert_eq "show não chama sudo nem apt" "" "$(cat "$CALL_LOG")"
  assert_contains "mostra passos privilegiados" "$out" "[sudo]"
  assert_contains "mostra passos de usuário" "$out" "[usuário]"
  assert_contains "informa o espaço livre" "$out" "Espaço livre em /: "
  assert_contains "informa os opcionais não incluídos" "$out" "Opcionais não incluídos: agents fd"
  assert_contains "informa que sudo é só para apt-get" "$out" "somente nos comandos apt-get"
  assert_contains "termina informando que nada foi alterado" "$out" "Somente o plano foi exibido. Nada foi alterado."
  local base_line bash_line
  base_line="$(grep -n ' base ' <<<"$out" | head -n1 | cut -d: -f1)"
  bash_line="$(grep -n ' bash ' <<<"$out" | head -n1 | cut -d: -f1)"
  check "pacotes vêm antes dos ajustes de usuário" test "$base_line" -lt "$bash_line"
}

test_profile_dry_run_has_no_side_effects() {
  new_prof_env
  local before out rc=0
  before="$(snapshot "$HOME_DIR")"
  out="$(prof run debian-desktop --with agents,fd --dry-run 2>&1)" || rc=$?
  assert_eq "dry-run sai com 0" "0" "$rc"
  assert_eq "dry-run não altera HOME" "$before" "$(snapshot "$HOME_DIR")"
  assert_eq "dry-run não chama sudo nem apt" "" "$(cat "$CALL_LOG")"
  assert_contains "repassa o dry-run aos pacotes" "$out" "apt-get install -y"
  assert_contains "repassa o dry-run ao bash" "$out" "[dry-run] Criaria"
  assert_contains "aviso final de dry-run" "$out" "[dry-run] Perfil debian-desktop: nenhuma alteração foi feita."
}

test_profile_run_applies_selected_components() {
  new_prof_env
  local out rc=0 calls
  out="$(prof run debian-desktop --yes 2>&1)" || rc=$?
  assert_eq "run --yes sai com 0" "0" "$rc"
  calls="$(cat "$CALL_LOG")"
  assert_contains "instalou base" "$calls" "apt-get install -y git curl"
  assert_contains "instalou development" "$calls" "build-essential"
  assert_contains "instalou desktop" "$calls" "apt-get install -y kate konsole"
  assert_not_contains "opcional agents não foi instalado" "$calls" "ripgrep"
  local l_base l_dev l_desk
  l_base="$(grep -n 'git curl' "$CALL_LOG" | head -n1 | cut -d: -f1)"
  l_dev="$(grep -n 'build-essential' "$CALL_LOG" | head -n1 | cut -d: -f1)"
  l_desk="$(grep -n 'kate konsole' "$CALL_LOG" | head -n1 | cut -d: -f1)"
  check "ordem dos pacotes: base, development, desktop" test "$l_base" -lt "$l_dev" -a "$l_dev" -lt "$l_desk"
  check "aliases do Bash configurados" grep -q aliases.sh "$HOME_DIR/.bashrc"
  check "link do tmux criado" test -L "$HOME_DIR/.config/tmux/tmux.conf"
  check "include do Git criado" grep -q include "$HOME_DIR/.gitconfig"
  check "link fd (opcional) não foi criado" test ! -e "$HOME_DIR/.local/bin/fd"
  assert_contains "resumo final" "$out" "Perfil debian-desktop aplicado: 6 passo(s) concluído(s)."
}

test_profile_with_includes_optional_components() {
  new_prof_env
  prof run debian-desktop --with agents,fd --yes >/dev/null 2>&1
  assert_contains "agents instalado" "$(cat "$CALL_LOG")" "ripgrep"
  assert_eq "fd configurado" "$FAKE_BIN/fdfind" "$(readlink "$HOME_DIR/.local/bin/fd")"
}

test_profile_only_runs_just_those_components() {
  new_prof_env
  local out
  out="$(prof run debian-desktop --only git,tmux --yes 2>&1)"
  assert_eq "sem sudo/apt com --only de usuário" "" "$(cat "$CALL_LOG")"
  check "tmux configurado" test -L "$HOME_DIR/.config/tmux/tmux.conf"
  check "git configurado" grep -q include "$HOME_DIR/.gitconfig"
  check "bash não foi configurado" test ! -e "$HOME_DIR/.bashrc"
  assert_contains "resumo com 2 passos" "$out" "2 passo(s)"
  # --only aceita também um opcional e um obrigatório.
  new_prof_env
  prof run debian-server --only base --yes >/dev/null 2>&1
  assert_contains "--only base instala só base" "$(cat "$CALL_LOG")" "apt-get install -y git curl"
  assert_not_contains "--only base não instala o resto" "$(cat "$CALL_LOG")" "build-essential"
}

test_profile_user_only_never_uses_sudo() {
  new_prof_env
  local out
  out="$(prof run debian-desktop --user-only --yes 2>&1)"
  assert_eq "--user-only não chama sudo/apt" "" "$(cat "$CALL_LOG")"
  assert_contains "informa o que foi ignorado" "$out" "Ignorados por --user-only (exigem sudo): base development desktop"
  check "ajustes de usuário foram aplicados" grep -q aliases.sh "$HOME_DIR/.bashrc"
}

test_profile_requires_confirmation() {
  new_prof_env
  local before rc=0
  before="$(snapshot "$HOME_DIR")"
  prof run debian-desktop >/dev/null 2>&1 || rc=$?
  assert_eq "sem entrada (EOF) cancela com 1" "1" "$rc"
  rc=0
  prof_input 'n\n' run debian-desktop >/dev/null 2>&1 || rc=$?
  assert_eq "resposta n cancela com 1" "1" "$rc"
  assert_eq "nada foi alterado ao cancelar" "$before" "$(snapshot "$HOME_DIR")"
  assert_eq "nada foi chamado ao cancelar" "" "$(cat "$CALL_LOG")"
  prof_input 's\n' run debian-desktop --user-only >/dev/null 2>&1
  check "resposta s executa" grep -q aliases.sh "$HOME_DIR/.bashrc"
}

test_profile_is_idempotent() {
  new_prof_env
  local out
  prof run debian-desktop --user-only --yes >/dev/null 2>&1
  out="$(prof run debian-desktop --user-only --yes 2>&1)"
  assert_eq "segunda execução diz já configurado 3 vezes" "3" "$(grep -c 'Já configurado' <<<"$out")"
  assert_eq "nenhum backup criado" "" "$(find "$HOME_DIR" -name '*.bak.*')"
  assert_eq "linha de aliases não duplicada" "1" "$(grep -c aliases.sh "$HOME_DIR/.bashrc")"
}

test_profile_requirements_are_enforced() {
  new_prof_env "Dell XPS"
  local out rc=0 before
  before="$(snapshot "$HOME_DIR")"
  out="$(prof run raspberry-pi-headless --yes 2>&1)" || rc=$?
  assert_eq "perfil do Pi fora de um Pi sai com 1" "1" "$rc"
  assert_contains "explica o requisito" "$out" "Raspberry Pi"
  assert_contains "informa que nada foi alterado" "$out" "Nada foi alterado."
  assert_eq "nada foi alterado" "$before" "$(snapshot "$HOME_DIR")"
  assert_eq "nada foi chamado" "" "$(cat "$CALL_LOG")"
  rc=0
  prof show raspberry-pi-headless >/dev/null 2>&1 || rc=$?
  assert_eq "show também respeita o requisito" "1" "$rc"
  # Sistema que não é Debian.
  printf 'ID=ubuntu\n' >"$PROF_OS"
  rc=0
  prof run debian-server --yes >/dev/null 2>&1 || rc=$?
  assert_eq "perfil Debian em sistema não Debian sai com 1" "1" "$rc"
  # Raspberry Pi OS antigo (raspbian) conta como Debian.
  printf 'ID=raspbian\n' >"$PROF_OS"
  printf 'Raspberry Pi 4 Model B\0' >"$PROF_MODEL"
  rc=0
  prof show raspberry-pi-headless >/dev/null 2>&1 || rc=$?
  assert_eq "raspbian em um Pi atende ao perfil" "0" "$rc"
  # Sem os arquivos de sistema, os requisitos não são atendidos.
  rm -f "$PROF_OS" "$PROF_MODEL"
  rc=0
  prof show raspberry-pi-headless >/dev/null 2>&1 || rc=$?
  assert_eq "sem os-release e device-tree falha" "1" "$rc"
}

test_profile_rejects_bad_input() {
  new_prof_env
  check_not "nome com caminho é rejeitado" prof show ../profiles/debian-desktop
  check_not "nome com maiúsculas é rejeitado" prof show Debian-Desktop
  check_not "perfil inexistente é rejeitado" prof show nao-existe
  check_not "sem nome falha" prof show
  check_not "componente inexistente em --only" prof run debian-desktop --only nada --yes
  check_not "componente inexistente em --with" prof run debian-desktop --with nada --yes
  check_not "--with e --only juntos" prof run debian-desktop --with agents --only bash --yes
  check_not "opção desconhecida" prof run debian-desktop --nada
  check_not "--with sem valor" prof run debian-desktop --with
  check_not "list com argumentos" prof list x
  check_not "comando desconhecido" prof apagar
  check_not "sem comando" prof
  assert_eq "nenhuma chamada a sudo/apt" "" "$(cat "$CALL_LOG")"
  assert_eq "HOME intacto" "" "$(find "$HOME_DIR" -mindepth 1)"
}

test_profile_malformed_files_are_rejected() {
  new_prof_env
  make_tree
  local n=0 body out rc
  local -a bodies=(
    $'[perfil]\ndescricao = x\n[segredos]\nbase = obrigatorio\n'
    $'[pacotes]\nbase = importante\n'
    $'[usuario]\nzsh = recomendado\n'
    $'[pacotes]\nbase = obrigatorio\nbase = opcional\n'
    $'base = obrigatorio\n'
    $'[pacotes]\ninexistente = opcional\n'
    $'[perfil]\nrequer = windows\n[pacotes]\nbase = obrigatorio\n'
    $'[perfil]\ndescricao = x\n'
    $'[pacotes]\nbase obrigatorio\n'
    $'[perfil]\nchave = x\n[pacotes]\nbase = obrigatorio\n'
  )
  for body in "${bodies[@]}"; do
    n=$((n + 1))
    printf '%s' "$body" >"$TREE/profiles/quebrado.conf"
    rc=0
    out="$(prof show quebrado 2>&1)" || rc=$?
    assert_eq "perfil malformado #$n é rejeitado (código 1)" "1" "$rc"
    assert_contains "perfil malformado #$n cita o arquivo" "$out" "quebrado.conf"
  done
  assert_contains "o erro indica a linha" "$(prof show quebrado 2>&1 || true)" "linha"
  # list marca o perfil quebrado como inválido sem falhar.
  printf '[pacotes]\nbase = importante\n' >"$TREE/profiles/quebrado.conf"
  out="$(prof list 2>/dev/null)"
  assert_contains "list marca perfil inválido" "$out" "INVÁLIDO"
  assert_contains "list continua listando os válidos" "$out" "debian-desktop"
  assert_eq "nada foi chamado" "" "$(cat "$CALL_LOG")"
}

test_profile_comments_and_spacing_are_tolerated() {
  new_prof_env
  make_tree
  printf '%s\n' '# comentário' '' '  [perfil]  ' 'descricao   =   Teste   # ignorado' 'requer=debian' '' \
    '[usuario]' '   bash=recomendado#sem espaço' '  tmux = opcional' >"$TREE/profiles/teste.conf"
  local out
  out="$(prof show teste 2>&1)"
  assert_contains "descrição lida sem espaços sobrando" "$out" "Descrição:  Teste"
  assert_contains "componente com comentário colado é lido" "$out" "setup-bash.sh"
  assert_contains "opcional fica de fora" "$out" "Opcionais não incluídos: tmux"
}

test_profile_stops_at_first_failure() {
  new_prof_env
  # Tanto o sudo quanto o apt-get simulados falham (vale também se o teste rodar como root).
  printf '#!/usr/bin/env bash\necho "apt-get $*" >>"$FAKE_LOG"\nexit 1\n' >"$FAKE_BIN/apt-get"
  printf '#!/usr/bin/env bash\necho "sudo $*" >>"$FAKE_LOG"\nexit 1\n' >"$FAKE_BIN/sudo"
  local out rc=0
  out="$(prof run debian-desktop --yes 2>&1)" || rc=$?
  assert_eq "falha de um passo sai com 1" "1" "$rc"
  assert_contains "informa o passo interrompido" "$out" "INTERROMPIDO no passo 1/6 (base)"
  assert_contains "lista os pendentes" "$out" "Pendentes:  development desktop bash tmux git"
  check "passos seguintes não foram executados" test ! -e "$HOME_DIR/.bashrc"
  assert_not_contains "apt install não continuou para outros perfis" "$(cat "$CALL_LOG")" "kate"
}

test_profile_conflict_does_not_stop_other_steps() {
  new_prof_env
  make_tree
  printf '%s\n' '[perfil]' 'descricao = t' '[usuario]' 'git = recomendado' 'bash = recomendado' >"$TREE/profiles/teste.conf"
  printf '[user]\n\tname = X\n' >"$ENV_DIR/real-gitconfig"
  ln -s "$ENV_DIR/real-gitconfig" "$HOME_DIR/.gitconfig"
  local out rc=0
  out="$(prof run teste --yes 2>&1)" || rc=$?
  assert_eq "conflito em um passo sai com 2" "2" "$rc"
  assert_contains "resumo destaca os conflitos" "$out" "concluído COM CONFLITOS"
  assert_contains "indica qual passo teve conflito" "$out" "Com conflito (nada foi alterado neles): git"
  check "o passo seguinte foi executado" grep -q aliases.sh "$HOME_DIR/.bashrc"
  assert_eq "arquivo real do git intacto" "$(printf '[user]\n\tname = X')" "$(cat "$ENV_DIR/real-gitconfig")"
}

test_profile_repo_profiles_are_valid_and_consistent() {
  new_prof_env
  local f name out rc
  for f in "$ROOT"/profiles/*.conf; do
    name="$(basename "$f" .conf)"
    rc=0
    out="$(prof show "$name" 2>&1)" || rc=$?
    assert_eq "perfil $name é válido (show sai com 0)" "0" "$rc"
    assert_contains "perfil $name tem descrição" "$out" "Descrição:  "
  done
  check_not "servidor não inclui desktop" grep -qE '^[[:space:]]*desktop[[:space:]]*=' "$ROOT/profiles/debian-server.conf"
  check_not "Pi headless não inclui desktop" grep -qE '^[[:space:]]*desktop[[:space:]]*=' "$ROOT/profiles/raspberry-pi-headless.conf"
  check "Pi headless exige o hardware" grep -qE '^requer.*raspberry-pi' "$ROOT/profiles/raspberry-pi-headless.conf"
  check_not "perfis não têm dados sensíveis" grep -qiE 'password|senha|token|secret|BEGIN [A-Z ]*KEY|@[a-z0-9-]+\.[a-z]' "$ROOT"/profiles/*.conf
  check "nenhum perfil é executável" bash -c '! find "$1/profiles" -type f -perm /111 | grep -q .' _ "$ROOT"
}

test_profile_simulation_is_announced_loudly() {
  new_prof_env
  local err out
  err="$(prof show debian-desktop 2>&1 >/dev/null)"
  assert_contains "aviso de simulação é exibido" "$err" "SIMULAÇÃO ATIVA"
  assert_contains "o aviso nomeia as variáveis em uso" "$err" "TOOLBOX_TEST_OS_RELEASE_FILE=$PROF_OS"
  assert_contains "o aviso diz como desativar" "$err" "unset TOOLBOX_TEST_OS_RELEASE_FILE TOOLBOX_TEST_DT_MODEL_FILE"
  assert_contains "o aviso é destacado entre linhas de =" "$err" "========================================================================
SIMULAÇÃO ATIVA"
  out="$(prof show debian-desktop 2>/dev/null)"
  assert_contains "o plano marca os requisitos como simulados" "$out" "(atendidos, SIMULADOS)"
  err="$(prof list 2>&1 >/dev/null)"
  assert_contains "list também avisa" "$err" "SIMULAÇÃO ATIVA"
  err="$(prof run debian-desktop --user-only --dry-run 2>&1 >/dev/null)"
  assert_contains "run também avisa" "$err" "SIMULAÇÃO ATIVA"
  # Só uma das variáveis definida: o aviso cita apenas a que está em uso.
  err="$(in_env env TOOLBOX_TEST_OS_RELEASE_FILE="$PROF_OS" bash "$PROF_SCRIPT" show debian-server 2>&1 >/dev/null)"
  assert_contains "uma variável basta para avisar" "$err" "TOOLBOX_TEST_OS_RELEASE_FILE=$PROF_OS"
  assert_not_contains "e a outra não é citada como em uso" "$err" "TOOLBOX_TEST_DT_MODEL_FILE="
}

test_profile_no_simulation_notice_in_normal_use() {
  new_prof_env
  local out
  # Sem as variáveis, nada de aviso nem de "SIMULADOS" (o debian-server só exige Debian).
  if ! grep -Eq '^ID="?(debian|raspbian)"?$' /etc/os-release 2>/dev/null; then
    skip "sistema real não é Debian: não dá para exercitar o uso normal"
    return 0
  fi
  out="$(in_env bash "$PROF_SCRIPT" show debian-server 2>&1)"
  assert_not_contains "uso normal não mostra aviso de simulação" "$out" "SIMULAÇÃO"
  assert_not_contains "uso normal não marca requisitos como simulados" "$out" "SIMULADOS"
  assert_contains "uso normal ainda mostra o plano" "$out" "Plano:"
}

test_profile_old_variable_names_no_longer_bypass_requirements() {
  new_prof_env
  if [[ -r /proc/device-tree/model ]] && [[ "$(tr -d '\0' </proc/device-tree/model)" == *"Raspberry Pi"* ]]; then
    skip "esta máquina é um Raspberry Pi: o requisito seria atendido de verdade"
    return 0
  fi
  local rc=0 out
  out="$(in_env env TOOLBOX_OS_RELEASE_FILE="$PROF_OS" TOOLBOX_DT_MODEL_FILE="$PROF_MODEL" \
    bash "$PROF_SCRIPT" show raspberry-pi-headless 2>&1)" || rc=$?
  assert_eq "nomes antigos não contornam o requisito de hardware" "1" "$rc"
  assert_contains "o requisito é cobrado" "$out" "não se aplica a esta máquina"
  assert_not_contains "e não há aviso de simulação (as variáveis foram ignoradas)" "$out" "SIMULAÇÃO"
}
