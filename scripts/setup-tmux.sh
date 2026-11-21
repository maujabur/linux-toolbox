#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$SCRIPT_DIR/lib.sh"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
      echo "Uso: setup-tmux.sh [--dry-run]"
      echo "Cria o link ~/.config/tmux/tmux.conf para configs/tmux/tmux.conf."
      echo "Se já houver um arquivo ou link diferente, cria antes um backup com timestamp."
      echo "O link aponta para este clone: não o mova nem apague depois."
      echo "Com --dry-run, apenas informa o que seria feito."
      exit 0
      ;;
    *) die "Opção desconhecida: $arg" ;;
  esac
done

TARGET="$HOME/.config/tmux/tmux.conf"
SOURCE="$REPO_DIR/configs/tmux/tmux.conf"

[[ -f "$SOURCE" ]] || die "Configuração não encontrada: $SOURCE"

if [[ -L "$TARGET" ]] && [[ "$(readlink "$TARGET")" == "$SOURCE" ]]; then
  banner ok "Já configurado: $TARGET -> $SOURCE" \
    "Nada a fazer: o resultado desta opção já está em vigor."
  exit 0
fi

if ((DRY_RUN)); then
  [[ -d "$(dirname "$TARGET")" ]] || log "[dry-run] Criaria o diretório $(dirname "$TARGET")"
  if [[ -e "$TARGET" || -L "$TARGET" ]]; then
    log "[dry-run] Criaria um backup de $TARGET em $TARGET.bak.<timestamp>"
  fi
  log "[dry-run] Criaria o link $TARGET -> $SOURCE"
  banner ok "[dry-run] Nenhuma alteração foi feita."
  exit 0
fi

mkdir -p -- "$(dirname "$TARGET")"
if [[ -e "$TARGET" || -L "$TARGET" ]]; then
  backup="$(backup_copy "$TARGET")"
  log "Backup criado: $backup"
fi
ln -sfn -- "$SOURCE" "$TARGET"
banner ok "Configuração do tmux vinculada: $TARGET" "" \
  "PRÓXIMO PASSO: em sessões tmux já abertas, execute:" "  tmux source-file ~/.config/tmux/tmux.conf"
