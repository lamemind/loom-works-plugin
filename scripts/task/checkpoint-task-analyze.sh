#!/bin/bash

# =============================================================================
# checkpoint-task-analyze.sh - Raccoglie info per checkpoint-task
# Usage: checkpoint-task-analyze.sh
# Env:   PROJECT_ROOT (default: $PWD)
# =============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode) LOOM_PROJECT_MODE="$2"; shift 2 ;;
        --docs-root) LOOM_DOCS_ROOT="$2"; shift 2 ;;
        *) break ;;
    esac
done

PROJECT_ROOT="${PROJECT_ROOT:-$PWD}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"

SYMLINK_PATH="${PROJECT_ROOT}/$(lw_docs_root)/current-task.md"

if [[ ! -L "$SYMLINK_PATH" ]]; then
    echo "ERROR: Nessuna task attiva. Usa /loom-works:start-task prima." >&2
    exit 1
fi

TASK_FILE=$(readlink -f "$SYMLINK_PATH")

if [[ ! -f "$TASK_FILE" ]]; then
    echo "ERROR: Task file non trovato: ${TASK_FILE}" >&2
    exit 1
fi

TASK_ID=$(grep -m1 '^\- \*\*ID\*\*:' "$TASK_FILE" | sed 's/.*: //')
PROGRESS=$(grep -m1 '^\- \*\*Progress\*\*:' "$TASK_FILE" | sed 's/.*: //')
TRACKED_SHA=$(grep -m1 '^\- \*\*Last tracked commit\*\*:' "$TASK_FILE" | sed 's/.*: //')

if [[ -z "$TASK_ID" ]]; then
    echo "ERROR: Impossibile estrarre metadata dal task file" >&2
    exit 1
fi

if lw_is_repo && [[ -z "$TRACKED_SHA" ]]; then
    echo "ERROR: Last tracked commit non trovato nel task file" >&2
    echo "       Esegui /loom-works:start-task per inizializzare il tracking" >&2
    exit 1
fi

CURRENT_BRANCH=$(lw_current_branch)
CURRENT_SHA=$(lw_current_sha)

if lw_is_repo; then
    FILES_COMMITTED=$(git -C "$PROJECT_ROOT" diff --name-only "${TRACKED_SHA}" 2>/dev/null || echo "")
    FILES_UNCOMMITTED=$(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null || echo "")
    COMMITS_SINCE=$(git -C "$PROJECT_ROOT" log "${TRACKED_SHA}..HEAD" --oneline 2>/dev/null || echo "")
    DIFF_STATS=$(git -C "$PROJECT_ROOT" diff --stat "${TRACKED_SHA}" 2>/dev/null || echo "")
else
    FILES_COMMITTED=""
    FILES_UNCOMMITTED=""
    COMMITS_SINCE=""
    DIFF_STATS=""
fi

SHA_RANGE="${TRACKED_SHA:-n/a}..${CURRENT_SHA:-n/a}"
BRANCH_DISPLAY="${CURRENT_BRANCH:-n/a}"

echo "CHECKPOINT-TASK-ANALYSIS task=${TASK_ID} branch=${BRANCH_DISPLAY} progress=${PROGRESS} sha=${SHA_RANGE} mode=$(lw_project_mode)"

if [[ -n "$COMMITS_SINCE" ]]; then
    echo ""
    echo "COMMITS SINCE CHECKPOINT:"
    echo "$COMMITS_SINCE" | while read -r line; do
        echo "  $line"
    done
fi

if [[ -n "$FILES_COMMITTED" ]]; then
    echo ""
    echo "FILES MODIFIED (committed):"
    echo "$FILES_COMMITTED" | while read -r line; do
        echo "  - $line"
    done
fi

if [[ -n "$FILES_UNCOMMITTED" ]]; then
    echo ""
    echo "FILES MODIFIED (uncommitted):"
    echo "$FILES_UNCOMMITTED" | while read -r line; do
        echo "  $line"
    done
fi

if [[ -n "$DIFF_STATS" ]]; then
    echo ""
    echo "DIFF STATS:"
    echo "$DIFF_STATS" | tail -1 | sed 's/^/  /'
fi

if [[ -z "$FILES_COMMITTED" && -z "$FILES_UNCOMMITTED" && -z "$COMMITS_SINCE" ]]; then
    echo ""
    if lw_is_repo; then
        echo "  (nessuna modifica dal checkpoint)"
    else
        echo "  (no-repo mode: analisi diff non disponibile — descrivi manualmente le modifiche)"
    fi
fi

echo ""
