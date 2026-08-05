#!/usr/bin/env bash

# =============================================================================
# docs-root.sh — quale sottocartella tiene la doc di QUESTO progetto
# Usage: docs-root.sh [--abs]
# =============================================================================
#
# Wrapper CLI sottile su `lw_docs_root` (scripts/utils/lib.sh): la logica di
# precedenza sta li', qui c'e' solo il parsing degli argomenti. Serve al markdown
# delle skill, che puo' invocare un comando ma non puo' sourcare una libreria
# bash — uno script che sourca lib.sh chiama la funzione diretta, non questo.
#
# Precedenza (in lib.sh): file .claude/loom-works.json `docsRoot`
#                      -> $LOOM_DOCS_ROOT
#                      -> "docs"
#
# Perche' esiste. La docs-root e' un fatto PER-PROGETTO (loom-works usa runtime/,
# il default e' docs/) e le skill devono nominarla in path che non passano da uno
# script: `{docs_root}/tasks.md`, `{docs_root}/reference/INDEX.md`, il symlink
# current-task.md. Prima veniva interpolata da `${user_config.doc_folder_name}`,
# che e' una preferenza utente GLOBALE: su un progetto non-default risolveva al
# valore di un altro progetto e la skill operava su una dir inesistente, in
# silenzio. Un comando non ha quel difetto — legge il file del progetto in cui
# gira.
#
# Stampa una riga sola, senza newline finale superflua, cosi' e' catturabile:
#   DOCS_ROOT=$(docs-root.sh)          -> runtime
#   DOCS_ROOT=$(docs-root.sh --abs)    -> /home/…/loom-works/runtime
#
# Lo stato shell NON sopravvive fra invocazioni del tool Bash di una skill: la
# variabile va risolta una volta e poi usata come valore LETTERALE nei passi
# successivi, oppure ri-risolta inline dove serve.
#
# Env: PROJECT_ROOT (default: $PWD), LOOM_DOCS_ROOT
# Exit: 0 sempre — la docs-root ha un default, non puo' mancare
# =============================================================================

set -uo pipefail

ABS=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --abs) ABS=1; shift ;;
        -*)    echo "ERROR: argomento sconosciuto: $1" >&2; exit 1 ;;
        *)     echo "ERROR: argomento posizionale non atteso: $1" >&2; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

if [[ "$ABS" -eq 1 ]]; then
    echo "$(lw_find_project_root)/$(lw_docs_root)"
else
    lw_docs_root
fi
