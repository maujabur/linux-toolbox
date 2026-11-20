# shellcheck shell=bash
# Funções compartilhadas pelos scripts. Carregado com "source"; não é executável.

log() { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
die() {
  warn "Erro: $*"
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
