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
      echo "Uso: setup-bash.sh [--dry-run]"
      echo "Adiciona ao ~/.bashrc a linha que carrega configs/bash/aliases.sh."
      echo "Um backup com timestamp de ~/.bashrc é criado antes da alteração."
      echo "Com --dry-run, apenas informa o que seria feito."
      exit 0
      ;;
    *) die "Opção desconhecida: $arg" ;;
  esac
done

ALIASES="$REPO_DIR/configs/bash/aliases.sh"
BASHRC="$HOME/.bashrc"
# Formato atual (tolera a ausência do arquivo) e formato antigo, ainda reconhecido.
SOURCE_LINE="$(printf '[[ -r %q ]] && source %q' "$ALIASES" "$ALIASES")"
LEGACY_LINE="source \"$ALIASES\""

if [[ -f "$BASHRC" ]] && { grep -Fqx -- "$SOURCE_LINE" "$BASHRC" || grep -Fqx -- "$LEGACY_LINE" "$BASHRC"; }; then
  log "Já configurado: aliases carregados em $BASHRC"
  exit 0
fi

if ((DRY_RUN)); then
  if [[ -e "$BASHRC" || -L "$BASHRC" ]]; then
    log "[dry-run] Criaria um backup de $BASHRC em $BASHRC.bak.<timestamp>"
  else
    log "[dry-run] Criaria $BASHRC"
  fi
  log "[dry-run] Acrescentaria ao final de $BASHRC: $SOURCE_LINE"
  exit 0
fi

if [[ -e "$BASHRC" || -L "$BASHRC" ]]; then
  backup="$(backup_copy "$BASHRC")"
  log "Backup criado: $backup"
else
  : >"$BASHRC"
fi
printf '\n# linux-toolbox: aliases pessoais\n%s\n' "$SOURCE_LINE" >>"$BASHRC"
log "Aliases adicionados. Execute: source ~/.bashrc"
