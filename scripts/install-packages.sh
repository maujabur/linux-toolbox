#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$SCRIPT_DIR/lib.sh"

usage() {
  echo "Uso: install-packages.sh [--dry-run] [--yes] [perfil]"
  echo "Instala com apt-get os pacotes de packages/<perfil>.txt (padrão: base)."
  echo "  --dry-run  mostra o que seria feito, sem executar apt-get nem sudo"
  echo "  -y, --yes  não pede confirmação (execução não interativa)"
  echo "Usa sudo apenas nos comandos apt-get, e somente se o usuário não for root."
}

DRY_RUN=0
ASSUME_YES=0
PROFILE=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -y | --yes) ASSUME_YES=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*) die "Opção desconhecida: $arg" ;;
    *)
      [[ -z "$PROFILE" ]] || die "Informe apenas um perfil."
      PROFILE="$arg"
      ;;
  esac
done
PROFILE="${PROFILE:-base}"

PACKAGE_FILE="$REPO_DIR/packages/$PROFILE.txt"
if [[ ! "$PROFILE" =~ ^[a-z][a-z0-9_-]*$ ]] || [[ ! -f "$PACKAGE_FILE" ]]; then
  die "Perfil inválido: $PROFILE"
fi
command -v apt-get >/dev/null || die "Este script exige Debian/Ubuntu com apt-get."

mapfile -t PACKAGES < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$PACKAGE_FILE")
if (("${#PACKAGES[@]}" == 0)); then
  banner ok "Nenhum pacote listado em $PACKAGE_FILE" "Nada foi feito."
  exit 0
fi

log "Perfil: $PROFILE (${#PACKAGES[@]} pacotes)"
log "Pacotes: ${PACKAGES[*]}"
log_free_space

if ((DRY_RUN)); then
  if ((EUID == 0)); then SUDO_TEXT=""; else SUDO_TEXT="sudo "; fi
  log "[dry-run] ${SUDO_TEXT}apt-get update"
  log "[dry-run] ${SUDO_TEXT}apt-get install -y ${PACKAGES[*]}"
  [[ "$PROFILE" != "agents" ]] || log "[dry-run] Em seguida executaria scripts/setup-fd.sh"
  banner ok "[dry-run] Nenhuma alteração foi feita."
  exit 0
fi

SUDO=()
if ((EUID != 0)); then
  command -v sudo >/dev/null || die "sudo não encontrado e o usuário não é root."
  SUDO=(sudo)
fi

confirm "Instalar esses pacotes com apt-get (exige privilégios)?" || {
  banner warn "CANCELADO. Nada foi instalado."
  exit 1
}

"${SUDO[@]}" apt-get update
"${SUDO[@]}" apt-get install -y "${PACKAGES[@]}"

# Ajuste opcional e não destrutivo do nome fd após instalar o perfil agents.
# Um conflito (código 2) não invalida a instalação dos pacotes: apenas avisa.
if [[ "$PROFILE" == "agents" ]]; then
  rc=0
  bash "$SCRIPT_DIR/setup-fd.sh" || rc=$?
  case "$rc" in
    0) ;;
    2) FD_WARNING=1 ;;
    *) exit "$rc" ;;
  esac
fi

if ((${FD_WARNING:-0})); then
  banner warn "AVISO: pacotes instalados, mas o link fd NÃO foi configurado." \
    "Veja o CONFLITO acima; os pacotes foram instalados normalmente."
else
  banner ok "Perfil $PROFILE instalado (${#PACKAGES[@]} pacotes)."
fi
