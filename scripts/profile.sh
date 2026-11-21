#!/usr/bin/env bash
# Aplica perfis de máquina (profiles/*.conf) compondo scripts que já existem.
# Os arquivos .conf são só dados: são lidos linha a linha, nunca executados.
#
# Códigos de saída:
#   0  plano exibido/aplicado com sucesso (ou --dry-run concluído)
#   1  erro: perfil inválido, requisito não atendido, cancelado ou passo falhou
#   2  concluído, mas algum passo terminou em conflito (nada foi alterado nele)
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$SCRIPT_DIR/lib.sh"

PROFILES_DIR="$REPO_DIR/profiles"
# Somente para testes: simulam o sistema e o hardware. Não são um recurso de
# uso: quem as define contorna a verificação de requisitos. Por isso, enquanto
# estiverem definidas, todo comando exibe um aviso destacado de simulação.
OS_RELEASE_FILE="${TOOLBOX_TEST_OS_RELEASE_FILE:-/etc/os-release}"
MODEL_FILE="${TOOLBOX_TEST_DT_MODEL_FILE:-/proc/device-tree/model}"
SIMULATED=()
[[ -z "${TOOLBOX_TEST_OS_RELEASE_FILE:-}" ]] || SIMULATED+=("TOOLBOX_TEST_OS_RELEASE_FILE=$TOOLBOX_TEST_OS_RELEASE_FILE")
[[ -z "${TOOLBOX_TEST_DT_MODEL_FILE:-}" ]] || SIMULATED+=("TOOLBOX_TEST_DT_MODEL_FILE=$TOOLBOX_TEST_DT_MODEL_FILE")

# announce_simulation: aviso destacado (stderr) quando os requisitos são simulados.
announce_simulation() {
  ((${#SIMULATED[@]} > 0)) || return 0
  banner warn "SIMULAÇÃO ATIVA: os requisitos de sistema e hardware NÃO" \
    "estão sendo lidos desta máquina. Variáveis em uso:" \
    "${SIMULATED[@]/#/  }" \
    "Se isto não é um teste, execute: unset TOOLBOX_TEST_OS_RELEASE_FILE TOOLBOX_TEST_DT_MODEL_FILE"
}

usage() {
  echo "Uso:"
  echo "  profile.sh list"
  echo "  profile.sh show PERFIL [--with A,B | --only A,B] [--user-only]"
  echo "  profile.sh run  PERFIL [--with A,B | --only A,B] [--user-only] [--dry-run] [--yes]"
  echo
  echo "  list         lista os perfis e se servem para esta máquina"
  echo "  show         mostra o plano, sem executar nada"
  echo "  run          mostra o plano, pede confirmação [s/N] e executa"
  echo "  --with       inclui também os componentes opcionais indicados"
  echo "  --only       executa somente os componentes indicados (qualquer nível)"
  echo "  --user-only  ignora os passos que usam sudo (pacotes)"
  echo "  --dry-run    repassa --dry-run a cada passo; não pergunta nem altera nada"
  echo "  -y, --yes    não pede confirmação do plano"
}

# ---------------------------------------------------------------- leitura

# Estado do perfil carregado.
PROFILE=""
DESC=""
REQS=()
PKG_NAMES=()
USR_NAMES=()
declare -A LEVEL=()

# component_script TIPO NOME: script que executa o componente (vazio se não existir).
component_script() {
  case "$1:$2" in
    pacotes:*) echo "install-packages.sh" ;;
    usuario:bash) echo "setup-bash.sh" ;;
    usuario:tmux) echo "setup-tmux.sh" ;;
    usuario:git) echo "setup-git.sh" ;;
    usuario:fd) echo "setup-fd.sh" ;;
  esac
}

# load_profile NOME: lê e valida profiles/NOME.conf; encerra com erro se inválido.
load_profile() {
  local name="$1" file line section="" key val n=0 req parts
  [[ "$name" =~ ^[a-z][a-z0-9-]*$ ]] || die "Nome de perfil inválido: $name"
  file="$PROFILES_DIR/$name.conf"
  [[ -f "$file" ]] || die "Perfil inexistente: $name (veja: profile.sh list)"
  PROFILE="$name"
  DESC=""
  REQS=()
  PKG_NAMES=()
  USR_NAMES=()
  LEVEL=()
  bad() { die "profiles/$name.conf, linha $n: $*"; }

  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] || continue
    if [[ "$line" =~ ^\[([a-z]+)\]$ ]]; then
      section="${BASH_REMATCH[1]}"
      case "$section" in
        perfil | pacotes | usuario) ;;
        *) bad "seção desconhecida [$section]" ;;
      esac
      continue
    fi
    [[ "$line" =~ ^([a-z][a-z0-9_-]*)[[:space:]]*=[[:space:]]*(.+)$ ]] || bad "linha inválida: $line"
    key="${BASH_REMATCH[1]}"
    val="${BASH_REMATCH[2]}"
    case "$section" in
      "") bad "item fora de uma seção" ;;
      perfil)
        case "$key" in
          descricao) DESC="$val" ;;
          requer)
            IFS=',' read -ra parts <<<"$val"
            for req in "${parts[@]}"; do
              req="${req//[[:space:]]/}"
              case "$req" in
                debian | raspberry-pi) REQS+=("$req") ;;
                *) bad "requisito desconhecido: $req" ;;
              esac
            done
            ;;
          *) bad "chave desconhecida em [perfil]: $key" ;;
        esac
        ;;
      pacotes | usuario)
        case "$val" in
          obrigatorio | recomendado | opcional) ;;
          *) bad "nível inválido para $key: $val (use obrigatorio, recomendado ou opcional)" ;;
        esac
        [[ -z "${LEVEL[$key]+x}" ]] || bad "componente repetido: $key"
        if [[ "$section" == pacotes ]]; then
          [[ -f "$REPO_DIR/packages/$key.txt" ]] || bad "lista de pacotes inexistente: packages/$key.txt"
          PKG_NAMES+=("$key")
        else
          [[ -n "$(component_script usuario "$key")" ]] || bad "componente de usuário desconhecido: $key"
          USR_NAMES+=("$key")
        fi
        LEVEL[$key]="$val"
        ;;
    esac
  done <"$file"

  ((${#PKG_NAMES[@]} + ${#USR_NAMES[@]} > 0)) || die "profiles/$name.conf: nenhum componente definido."
}

# ------------------------------------------------------------- requisitos

# requirement_ok REQ: 0 se esta máquina atende ao requisito.
requirement_ok() {
  local model
  case "$1" in
    debian)
      [[ -r "$OS_RELEASE_FILE" ]] && grep -Eq '^ID="?(debian|raspbian)"?$' "$OS_RELEASE_FILE"
      ;;
    raspberry-pi)
      [[ -r "$MODEL_FILE" ]] || return 1
      model="$(tr -d '\0' <"$MODEL_FILE")"
      [[ "$model" == *"Raspberry Pi"* ]]
      ;;
  esac
}

requirement_text() {
  case "$1" in
    debian) echo "Debian (ID=debian ou raspbian em os-release)" ;;
    raspberry-pi) echo "Raspberry Pi (conforme /proc/device-tree/model)" ;;
  esac
}

# unmet_requirements: imprime os requisitos não atendidos, um por linha.
unmet_requirements() {
  local req
  for req in "${REQS[@]}"; do
    requirement_ok "$req" || requirement_text "$req"
  done
}

# ------------------------------------------------------------------ plano

# in_list ITEM LISTA...: 0 se ITEM está na lista.
in_list() {
  local item="$1" x
  shift
  for x in "$@"; do [[ "$x" == "$item" ]] && return 0; done
  return 1
}

STEPS=()     # "pacotes:NOME" e "usuario:NOME", na ordem de execução
SKIP_OPT=()  # opcionais não selecionados
SKIP_SUDO=() # pacotes ignorados por --user-only
WITH_LIST=() # --with
ONLY_LIST=() # --only
USER_ONLY=0

# build_steps: aplica --with, --only e --user-only. Pacotes vêm antes dos ajustes
# de usuário (ex.: o git precisa estar instalado antes de configurá-lo).
build_steps() {
  local name item
  STEPS=()
  SKIP_OPT=()
  SKIP_SUDO=()
  for item in "${WITH_LIST[@]}" "${ONLY_LIST[@]}"; do
    [[ -n "${LEVEL[$item]+x}" ]] || die "Componente '$item' não existe no perfil $PROFILE."
  done
  local kind include
  for kind in pacotes usuario; do
    local names=()
    if [[ "$kind" == pacotes ]]; then names=("${PKG_NAMES[@]}"); else names=("${USR_NAMES[@]}"); fi
    for name in "${names[@]}"; do
      if ((${#ONLY_LIST[@]} > 0)); then
        in_list "$name" "${ONLY_LIST[@]}" && include=1 || include=0
      elif [[ "${LEVEL[$name]}" != opcional ]] || { ((${#WITH_LIST[@]} > 0)) && in_list "$name" "${WITH_LIST[@]}"; }; then
        include=1
      else
        include=0
        SKIP_OPT+=("$name")
        continue
      fi
      ((include)) || continue
      if [[ "$kind" == pacotes ]] && ((USER_ONLY)); then
        SKIP_SUDO+=("$name")
        continue
      fi
      STEPS+=("$kind:$name")
    done
  done
}

# print_plan: mostra o plano de execução.
print_plan() {
  local i=0 step kind name tag cmd reqs_text
  log "Perfil:     $PROFILE"
  [[ -z "$DESC" ]] || log "Descrição:  $DESC"
  if ((${#REQS[@]} > 0)); then
    reqs_text="${REQS[*]}"
    log "Requisitos: ${reqs_text// /, } (atendidos${SIMULATED[0]:+, SIMULADOS})"
  fi
  for step in "${STEPS[@]}"; do
    [[ "$step" == pacotes:* ]] && {
      log_free_space
      break
    }
  done
  log
  if ((${#STEPS[@]} == 0)); then
    log "Plano: nenhum passo selecionado."
  else
    log "Plano:"
    for step in "${STEPS[@]}"; do
      i=$((i + 1))
      kind="${step%%:*}"
      name="${step#*:}"
      if [[ "$kind" == pacotes ]]; then
        tag="[sudo]   "
        cmd="$(component_script "$kind" "$name") $name"
      else
        tag="[usuário]"
        cmd="$(component_script "$kind" "$name")"
      fi
      printf '  %d. %s %-12s %-14s -> %s\n' "$i" "$tag" "$name" "(${LEVEL[$name]})" "$cmd"
    done
  fi
  if ((${#SKIP_OPT[@]} > 0)); then
    log
    log "Opcionais não incluídos: ${SKIP_OPT[*]}  (use --with NOME para incluir)"
  fi
  if ((${#SKIP_SUDO[@]} > 0)); then
    log
    log "Ignorados por --user-only (exigem sudo): ${SKIP_SUDO[*]}"
  fi
  if [[ " ${STEPS[*]:-} " == *" pacotes:"* ]]; then
    log
    log "Os passos [sudo] usam sudo somente nos comandos apt-get."
  fi
}

# ------------------------------------------------------------- execução

# run_step PASSO DRY: executa o script do componente e devolve o código de saída.
run_step() {
  local kind="${1%%:*}" name="${1#*:}" script args=()
  script="$SCRIPT_DIR/$(component_script "$kind" "$name")"
  [[ "$kind" == pacotes ]] && args+=("$name" --yes)
  ((DRY_RUN)) && args+=(--dry-run)
  bash "$script" "${args[@]}"
}

do_run() {
  local total="${#STEPS[@]}" i=0 step rc done_steps=() conflicts=() pending=()
  if ((total == 0)); then
    banner ok "Nenhum passo a executar no perfil $PROFILE." "Nada foi feito."
    exit 0
  fi
  if ((!DRY_RUN)); then
    confirm "Executar este plano?" || {
      banner warn "CANCELADO. Nada foi alterado."
      exit 1
    }
  fi
  for step in "${STEPS[@]}"; do
    i=$((i + 1))
    log
    log "######## Passo $i/$total: ${step#*:} ########"
    rc=0
    run_step "$step" || rc=$?
    case "$rc" in
      0) done_steps+=("${step#*:}") ;;
      2) conflicts+=("${step#*:}") ;;
      *)
        pending=("${STEPS[@]:$i}")
        banner err "Perfil $PROFILE INTERROMPIDO no passo $i/$total (${step#*:}), código $rc." \
          "Concluídos: ${done_steps[*]:-nenhum}" \
          "Com conflito: ${conflicts[*]:-nenhum}" \
          "Pendentes:  ${pending[*]#*:}"
        exit 1
        ;;
    esac
  done
  if ((DRY_RUN)); then
    banner ok "[dry-run] Perfil $PROFILE: nenhuma alteração foi feita."
  elif ((${#conflicts[@]} > 0)); then
    banner warn "Perfil $PROFILE concluído COM CONFLITOS." \
      "Concluídos: ${done_steps[*]:-nenhum}" \
      "Com conflito (nada foi alterado neles): ${conflicts[*]}" \
      "Veja as mensagens de CONFLITO acima."
    exit 2
  else
    banner ok "Perfil $PROFILE aplicado: ${#done_steps[@]} passo(s) concluído(s)." \
      "Concluídos: ${done_steps[*]}"
  fi
}

# ------------------------------------------------------------------ main

do_list() {
  local f name line unmet
  shopt -s nullglob
  for f in "$PROFILES_DIR"/*.conf; do
    name="$(basename "$f" .conf)"
    if line="$(
      load_profile "$name" 2>/dev/null
      unmet="$(unmet_requirements)"
      printf '%s|%s' "$DESC" "${unmet:+indisponível nesta máquina}"
    )"; then
      printf '%-24s %s%s\n' "$name" "${line%%|*}" "$([[ -n "${line#*|}" ]] && echo "  [${line#*|}]")"
    else
      printf '%-24s %s\n' "$name" "[INVÁLIDO: veja profile.sh show $name]"
    fi
  done
}

(($# > 0)) || {
  usage >&2
  exit 1
}
CMD="$1"
shift
case "$CMD" in
  -h | --help)
    usage
    exit 0
    ;;
  list)
    (($# == 0)) || die "list não aceita argumentos."
    announce_simulation
    do_list
    exit 0
    ;;
  show | run) ;;
  *)
    usage >&2
    exit 1
    ;;
esac

(($# > 0)) || die "Informe o nome do perfil (veja: profile.sh list)."
NAME="$1"
shift
DRY_RUN=0
ASSUME_YES=0
split_csv() {
  local -n out="$1"
  local item parts
  IFS=',' read -ra parts <<<"$2"
  for item in "${parts[@]}"; do
    item="${item//[[:space:]]/}"
    [[ -z "$item" ]] || out+=("$item")
  done
}
while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -y | --yes) ASSUME_YES=1 ;;
    --user-only) USER_ONLY=1 ;;
    --with | --only)
      (($# >= 2)) || die "$1 exige uma lista separada por vírgulas."
      if [[ "$1" == --with ]]; then split_csv WITH_LIST "$2"; else split_csv ONLY_LIST "$2"; fi
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "Opção desconhecida: $1" ;;
  esac
  shift
done
((${#WITH_LIST[@]} == 0 || ${#ONLY_LIST[@]} == 0)) || die "Use --with ou --only, não os dois."

announce_simulation
load_profile "$NAME"
UNMET="$(unmet_requirements)"
if [[ -n "$UNMET" ]]; then
  mapfile -t UNMET_LINES <<<"$UNMET"
  banner err "O perfil $PROFILE não se aplica a esta máquina." \
    "Requisito não atendido:" "${UNMET_LINES[@]/#/  - }" \
    "Nada foi alterado."
  exit 1
fi
build_steps
print_plan
if [[ "$CMD" == show ]]; then
  banner ok "Somente o plano foi exibido. Nada foi alterado."
  exit 0
fi
do_run
