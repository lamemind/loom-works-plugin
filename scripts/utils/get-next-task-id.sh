#!/bin/bash

# =============================================================================
# get-next-task-id.sh - Genera il prossimo ID task
# Usage: get-next-task-id.sh [--mode <repo|no-repo>] [--prefix <T|D|...>]
# Env:   PROJECT_ROOT (default: $PWD)
# Output: ID completo (es: T04, T319, D01)
#
# Il prefix determina il counter: T (code, default) e D (doc) sono counter
# indipendenti. Lo script scansiona docs/tasks/ filtrando per prefix e
# restituisce PREFIX + (max + 1) zero-padded a 2 cifre.
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
TASKS_DIR="${PROJECT_ROOT}/$(lw_docs_root)/tasks"

MAX_ID=0

if [[ -d "$TASKS_DIR" ]]; then
    for file in "$TASKS_DIR"/*.md; do
        if [[ -f "$file" ]]; then
            FILENAME=$(basename "$file")
            if [[ "$FILENAME" =~ ^${PREFIX}([0-9]+)- ]]; then
                NUM="${BASH_REMATCH[1]}"
                NUM=$((10#$NUM))
                if [[ $NUM -gt $MAX_ID ]]; then
                    MAX_ID=$NUM
                fi
            fi
        fi
    done
fi

NEXT_ID=$((MAX_ID + 1))
printf "%s%02d\n" "$PREFIX" "$NEXT_ID"
