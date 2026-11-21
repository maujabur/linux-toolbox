# shellcheck shell=bash
# Funções compartilhadas pelos scripts. Carregado com "source"; não é executável.

log() { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }

# banner TIPO LINHA...: destaca o resultado de uma operação entre linhas de "=".
# TIPO: ok (stdout, verde), warn e err (stderr, amarelo e vermelho). As cores só
# são usadas em terminal e quando NO_COLOR não está definida.
banner() {
  local kind="$1" bar color="" reset="" fd=1
  shift
  [[ "$kind" == ok ]] || fd=2
  printf -v bar '%72s' ''
  bar="${bar// /=}"
  if [[ -t "$fd" && -z "${NO_COLOR:-}" ]]; then
    case "$kind" in
      ok) color=$'\033[1;32m' ;;
      warn) color=$'\033[1;33m' ;;
      *) color=$'\033[1;31m' ;;
    esac
    reset=$'\033[0m'
  fi
  {
    printf '\n%s%s\n' "$color" "$bar"
    printf '%s\n' "$@"
    printf '%s%s\n\n' "$bar" "$reset"
  } >&"$fd"
}

die() {
  banner err "ERRO: $*"
  exit 1
}

# confirm "pergunta": retorna 0 se ASSUME_YES=1 ou se a resposta for s/sim.
# Sem resposta (EOF) ou qualquer outra entrada, retorna 1.
confirm() {
  local answer
  [[ "${ASSUME_YES:-0}" == 1 ]] && return 0
  printf '%s [s/N] ' "$1" >&2
  read -r answer || {
    echo >&2
    return 1
  }
  [[ "$answer" =~ ^([sS]|[sS][iI][mM])$ ]]
}

# git_global_config_path: arquivo onde o Git grava a configuração pessoal.
# É ~/.gitconfig, ou o arquivo do XDG quando só ele existe (como faz o Git).
git_global_config_path() {
  local xdg="${XDG_CONFIG_HOME:-$HOME/.config}/git/config"
  if [[ ! -e "$HOME/.gitconfig" && ! -L "$HOME/.gitconfig" && (-e "$xdg" || -L "$xdg") ]]; then
    printf '%s\n' "$xdg"
  else
    printf '%s\n' "$HOME/.gitconfig"
  fi
}

# backup_copy CAMINHO: copia o arquivo (ou link) para CAMINHO.bak.AAAAMMDD_HHMMSS
# e imprime o caminho criado. O nome é reservado de forma atômica (noclobber);
# se já existir, acrescenta .1, .2, ... Nunca sobrescreve um backup anterior.
backup_copy() {
  local src="$1" base candidate n=0
  base="$src.bak.$(date +%Y%m%d_%H%M%S)"
  candidate="$base"
  until (
    set -o noclobber
    : >"$candidate"
  ) 2>/dev/null; do
    n=$((n + 1))
    ((n < 1000)) || {
      warn "Não foi possível reservar um nome de backup para $src"
      return 1
    }
    candidate="$base.$n"
  done
  if ! cp -pP --remove-destination -- "$src" "$candidate"; then
    rm -f -- "$candidate"
    return 1
  fi
  printf '%s\n' "$candidate"
}
