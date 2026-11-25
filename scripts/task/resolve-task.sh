#!/usr/bin/env bash

# =============================================================================
# resolve-task.sh — quale task e' attiva, senza indovinare
# Usage: resolve-task.sh [<task-id>] [--task <id>] [--docs-root <name>] [--children] [--members]
# =============================================================================
#
# Wrapper CLI sottile su `lw_resolve_task` (scripts/utils/lib.sh): la logica sta
# tutta li', qui c'e' solo il parsing degli argomenti. Serve al markdown delle
# skill, che puo' invocare un comando ma non puo' sourcare una libreria bash —
# uno script che sourca lib.sh chiama la funzione diretta, non questo.
#
# Cascata: arg esplicito -> $LOOM_TASK. Nessun altro gradino: senza i due, exit 1.
#
# Stampa tre righe, valori shell-quotati (eval-abili anche con spazi nel path):
#   TASK_ID=T48
#   TASK_FILE=/abs/path/runtime/tasks/T48-slug.md
#   TASK_SRC=arg|env
#
# Con --children aggiunge il conteggio e una riga per figlia (NON %q-quotate,
# sono per un lettore, non per `eval`):
#   TASK_CHILDREN_COUNT=3
#   TASK_CHILD=T76 /abs/path/runtime/tasks/T76-slug.md
#
# Con --members aggiunge i membri del perimetro orchestrabile, epica o lista
# custom — lettore unico `lw_task_members`, contratto in docs/perimeter-format.md.
# Stessa forma, non %q-quotata:
#   TASK_MEMBERS_SRC=list|parent
#   TASK_MEMBERS_COUNT=2
#   TASK_MEMBER=T52 /abs/path/runtime/tasks/T52-slug.md
#   TASK_MEMBER_MISSING=T58
# --children resta com'era, anche su una lista custom: le figlie da `Parent Task`.
#
# Env: PROJECT_ROOT, LOOM_TASK, LOOM_DOCS_ROOT
# Exit: 0 = risolta · 1 = nessuna fonte · 2 = id noto ma task file assente
# =============================================================================

set -uo pipefail

TASK_ARG=""
WANT_CHILDREN=0
WANT_MEMBERS=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --task)      TASK_ARG="${2:?--task requires a value}"; shift 2 ;;
        --docs-root) LOOM_DOCS_ROOT="${2:?--docs-root requires a value}"; export LOOM_DOCS_ROOT; shift 2 ;;
        --children)  WANT_CHILDREN=1; shift ;;
        --members)   WANT_MEMBERS=1; shift ;;
        -*)          echo "ERROR: argomento sconosciuto: $1" >&2; exit 1 ;;
        *)           TASK_ARG="$1"; shift ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"

RESOLVED="$(lw_resolve_task "$TASK_ARG")" || exit $?
printf '%s\n' "$RESOLVED"

[[ "$WANT_CHILDREN" -eq 1 || "$WANT_MEMBERS" -eq 1 ]] || exit 0

eval "$RESOLVED"

if [[ "$WANT_CHILDREN" -eq 1 ]]; then
    CHILDREN="$(lw_task_children "$TASK_ID")" || exit 1
    if [[ -z "$CHILDREN" ]]; then
        echo "TASK_CHILDREN_COUNT=0"
    else
        printf 'TASK_CHILDREN_COUNT=%s\n%s\n' "$(printf '%s\n' "$CHILDREN" | wc -l)" "$CHILDREN"
    fi
fi

if [[ "$WANT_MEMBERS" -eq 1 ]]; then
    lw_task_members "$TASK_ID" || exit $?
fi
