#!/bin/bash

# =============================================================================
# get-next-task-id.sh - Genera il prossimo ID task
# Usage: get-next-task-id.sh [--mode <repo|no-repo>] [--prefix <T|D|...>]
# Env:   PROJECT_ROOT (default: $PWD)
# Output: ID completo (es: T04, T319, D01)
#
# Il prefix determina il counter: T (code, default) e D (doc) sono counter
# indipendenti. Il max e' calcolato sull'UNIONE di due sorgenti:
#   1. i FILE in docs/tasks/ (PREFIX + numero)
#   2. le RIGHE della tabella Tasks Overview in tasks.md
# Restituisce PREFIX + (max + 1) zero-padded a 2 cifre.
#
# La sorgente 2 e' necessaria: una task Done puo' avere il file rimosso ma
# la riga ancora viva in tasks.md (orfana). Guardare solo i file riallocherebbe
# quell'ID -> collisione. L'unicita' vive in tasks.md, non nel filesystem.
# =============================================================================

PREFIX="T"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            LOOM_PROJECT_MODE="$2"
            shift 2
            ;;
        --docs-root)
            LOOM_DOCS_ROOT="$2"
            shift 2
            ;;
        --prefix)
            PREFIX="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

PROJECT_ROOT="$(lw_find_project_root)"
DOCS_ROOT="$(lw_docs_root)"
TASKS_DIR="${PROJECT_ROOT}/${DOCS_ROOT}/tasks"
TASKS_FILE="${PROJECT_ROOT}/${DOCS_ROOT}/tasks.md"

MAX_ID=0

# Sorgente 1: FILE in docs/tasks/ (PREFIX + numero + '-')
if [[ -d "$TASKS_DIR" ]]; then
    for file in "$TASKS_DIR"/*.md; do
        if [[ -f "$file" ]]; then
            FILENAME=$(basename "$file")
            if [[ "$FILENAME" =~ ^${PREFIX}([0-9]+)- ]]; then
                NUM=$((10#${BASH_REMATCH[1]}))
                (( NUM > MAX_ID )) && MAX_ID=$NUM
            fi
        fi
    done
fi

# Sorgente 2: righe della tabella in tasks.md (ID nella prima cella: '| D03 |').
# Cattura gli ID le cui righe sopravvivono al file (orfane/tombstone).
if [[ -f "$TASKS_FILE" ]]; then
    while IFS= read -r NUM; do
        NUM=$((10#$NUM))
        (( NUM > MAX_ID )) && MAX_ID=$NUM
    done < <(grep -oP "^\|\s*${PREFIX}\K[0-9]+" "$TASKS_FILE" 2>/dev/null)
fi

NEXT_ID=$((MAX_ID + 1))
printf "%s%02d\n" "$PREFIX" "$NEXT_ID"
