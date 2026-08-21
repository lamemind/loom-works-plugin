#!/usr/bin/env bash

# =============================================================================
# resolve-task.sh — quale task e' attiva, senza indovinare
# Usage: resolve-task.sh [<task-id>] [--task <id>] [--docs-root <name>] [--children]
# =============================================================================
#
# Wrapper CLI sottile su `lw_resolve_task` (scripts/utils/lib.sh): la logica sta
# tutta li', qui c'e' solo il parsing degli argomenti. Serve al markdown delle
# skill, che puo' invocare un comando ma non puo' sourcare una libreria bash —
# uno script che sourca lib.sh chiama la funzione diretta, non questo.
#
# Cascata: arg esplicito -> $LOOM_TASK -> symlink {docs_root}/current-task.md
#
# Stampa tre righe, valori shell-quotati (eval-abili anche con spazi nel path):
#   TASK_ID=T48
#   TASK_FILE=/abs/path/runtime/tasks/T48-slug.md
#   TASK_SRC=arg|env|symlink
#
# Con --children aggiunge il conteggio e una riga per figlia (NON %q-quotate,
# sono per un lettore, non per `eval`):
#   TASK_CHILDREN_COUNT=3
#   TASK_CHILD=T76 /abs/path/runtime/tasks/T76-slug.md
#
# Env: PROJECT_ROOT, LOOM_TASK, LOOM_DOCS_ROOT
# Exit: 0 = risolta · 1 = nessuna fonte · 2 = id noto ma task file assente
# =============================================================================

set -uo pipefail

TASK_ARG=""
WANT_CHILDREN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --task)      TASK_ARG="${2:?--task requires a value}"; shift 2 ;;
        --docs-root) LOOM_DOCS_ROOT="${2:?--docs-root requires a value}"; export LOOM_DOCS_ROOT; shift 2 ;;
        --children)  WANT_CHILDREN=1; shift ;;
        -*)          echo "ERROR: argomento sconosciuto: $1" >&2; exit 1 ;;
        *)           TASK_ARG="$1"; shift ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"

RESOLVED="$(lw_resolve_task "$TASK_ARG")" || exit $?
printf '%s\n' "$RESOLVED"

[[ "$WANT_CHILDREN" -eq 1 ]] || exit 0

eval "$RESOLVED"
CHILDREN="$(lw_task_children "$TASK_ID")" || exit 1
if [[ -z "$CHILDREN" ]]; then
    echo "TASK_CHILDREN_COUNT=0"
else
    printf 'TASK_CHILDREN_COUNT=%s\n%s\n' "$(printf '%s\n' "$CHILDREN" | wc -l)" "$CHILDREN"
fi
