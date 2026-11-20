#!/usr/bin/env bash
# Restaura ~/.bashrc ou a configuração do tmux a partir de um backup .bak.*
# criado pelos scripts de configuração. O estado atual é preservado antes.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$SCRIPT_DIR/lib.sh"

usage() {
  echo "Uso: restore.sh bash|tmux|git [--backup ARQUIVO] [--dry-run] [--yes]"
  echo "  bash   restaura ~/.bashrc"
  echo "  tmux   restaura ~/.config/tmux/tmux.conf"
  echo "  git    restaura ~/.gitconfig (ou o config do XDG, se for o usado)"
  echo "Sem --backup, usa o backup mais recente (ALVO.bak.AAAAMMDD_HHMMSS[.N])."
  echo "O estado atual é copiado para um novo backup antes da restauração."
  echo "  --dry-run  apenas informa o que seria feito"
  echo "  -y, --yes  não pede confirmação"
}

DRY_RUN=0
ASSUME_YES=0
WHAT=""
BACKUP=""
while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -y | --yes) ASSUME_YES=1 ;;
    --backup)
      (($# >= 2)) || die "--backup exige um caminho."
      BACKUP="$2"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*) die "Opção desconhecida: $1" ;;
    *)
      [[ -z "$WHAT" ]] || die "Informe apenas um alvo (bash, tmux ou git)."
      WHAT="$1"
      ;;
  esac
  shift
done

case "$WHAT" in
  bash) TARGET="$HOME/.bashrc" ;;
  tmux) TARGET="$HOME/.config/tmux/tmux.conf" ;;
  git) TARGET="$(git_global_config_path)" ;;
  *)
    usage >&2
    exit 1
    ;;
esac

if [[ -z "$BACKUP" ]]; then
  shopt -s nullglob
  candidates=("$TARGET".bak.*)
  shopt -u nullglob
  ((${#candidates[@]} > 0)) || die "Nenhum backup encontrado para $TARGET."
  BACKUP="$(printf '%s\n' "${candidates[@]}" | sort -V | tail -n 1)"
fi
[[ "$BACKUP" == "$TARGET".bak.* ]] || die "O backup deve ser do tipo $TARGET.bak.*: $BACKUP"
[[ -f "$BACKUP" || -L "$BACKUP" ]] || die "Backup inexistente ou não é arquivo/link: $BACKUP"

log "Alvo:    $TARGET"
log "Backup:  $BACKUP"
if [[ -e "$TARGET" || -L "$TARGET" ]]; then
  log "O estado atual será preservado em $TARGET.bak.<timestamp>"
fi

if ((DRY_RUN)); then
  log "[dry-run] Restauraria $BACKUP em $TARGET"
  exit 0
fi

confirm "Restaurar esse backup?" || {
  warn "Cancelado. Nada foi alterado."
  exit 1
}

# Sequência segura: o alvo só é substituído por rename atômico, depois que a
# cópia temporária e o backup do estado atual existirem. Se algo falhar antes,
# o alvo continua intacto.
TMP="$TARGET.restore.$$"
cleanup() { rm -f -- "$TMP"; }
trap cleanup EXIT
mkdir -p -- "$(dirname "$TARGET")"
cp -pP --remove-destination -- "$BACKUP" "$TMP" || die "Falha ao copiar o backup. O alvo não foi alterado."
if [[ -e "$TARGET" || -L "$TARGET" ]]; then
  saved="$(backup_copy "$TARGET")" || die "Falha ao preservar o estado atual. O alvo não foi alterado."
  log "Estado atual preservado em: $saved"
fi
mv -fT -- "$TMP" "$TARGET" || die "Falha ao substituir o alvo. Estado anterior preservado em ${saved:-<não havia>}."
log "Restaurado: $TARGET"
