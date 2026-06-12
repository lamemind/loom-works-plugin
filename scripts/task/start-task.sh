#!/bin/bash

# =============================================================================
# start-task.sh - Attiva una task per checkpoint tracking
# Usage: start-task.sh [--mode <repo|no-repo>] [--detach] <task-id>
# Env:   PROJECT_ROOT (default: $PWD)
# =============================================================================

DETACH=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode) LOOM_PROJECT_MODE="$2"; shift 2 ;;
        --docs-root) LOOM_DOCS_ROOT="$2"; shift 2 ;;
        --detach) DETACH=1; shift ;;
        *) break ;;
    esac
done

TASK_ID="${1:?Usage: start-task.sh [--mode <repo|no-repo>] [--detach] <task-id>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"

PROJECT_ROOT="$(lw_find_project_root)"
TASKS_DIR="${PROJECT_ROOT}/$(lw_docs_root)/tasks"
TASKS_FILE="${PROJECT_ROOT}/$(lw_docs_root)/tasks.md"
SYMLINK_PATH="${PROJECT_ROOT}/$(lw_docs_root)/current-task.md"

# -----------------------------------------------------------------------------
# Trova il file task
# -----------------------------------------------------------------------------

TASK_FILE=$(find "$TASKS_DIR" -maxdepth 1 -name "${TASK_ID}-*.md" 2>/dev/null | head -1)

if [[ -z "$TASK_FILE" || ! -f "$TASK_FILE" ]]; then
    echo "ERROR: Task file non trovato per ${TASK_ID} in ${TASKS_DIR}" >&2
    exit 1
fi

TASK_FILENAME=$(basename "$TASK_FILE")

# -----------------------------------------------------------------------------
# Ottieni SHA corrente (vuoto in no-repo)
# -----------------------------------------------------------------------------

SHA=$(lw_current_sha)
SHA_DISPLAY="${SHA:-n/a}"

if lw_is_repo && [[ -z "$SHA" ]]; then
    echo "ERROR: Impossibile ottenere SHA corrente" >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# Aggiorna file task: Progress e Last tracked commit
# -----------------------------------------------------------------------------

sed -i 's/^\(- \*\*Progress\*\*:\).*/\1 🟡 0%/' "$TASK_FILE"

if grep -q '^\- \*\*Last tracked commit\*\*:' "$TASK_FILE"; then
    sed -i "s|^\(- \*\*Last tracked commit\*\*:\).*|\1 ${SHA_DISPLAY}|" "$TASK_FILE"
else
    sed -i "/^\- \*\*Priority\*\*:/a - **Last tracked commit**: ${SHA_DISPLAY}" "$TASK_FILE"
fi

echo "-> Task file aggiornato: Progress 🟡 0%, SHA ${SHA_DISPLAY}"

# -----------------------------------------------------------------------------
# Aggiorna tasks.md: Progress nella tabella e grafo lane
# -----------------------------------------------------------------------------

if [[ -f "$TASKS_FILE" ]]; then
    sed -i "s/^\(| ${TASK_ID} |[^|]*| \)🔵[^|]*\( |.*\)$/\1🟡 \2/" "$TASKS_FILE"
    sed -i "s/^\(| ${TASK_ID} |[^|]*| \)✔️[^|]*\( |.*\)$/\1🟡 \2/" "$TASKS_FILE"

    perl -i -pe "s/→ ${TASK_ID}(?![0-9])/→ 🟡${TASK_ID}/ if /^Lane/" "$TASKS_FILE"

    echo "-> tasks.md aggiornato: ${TASK_ID} 🟡"
fi

# -----------------------------------------------------------------------------
# Crea/ricrea symlink docs/current-task.md (skip se --detach)
# -----------------------------------------------------------------------------

if [[ $DETACH -eq 1 ]]; then
    echo ""
    echo "📌 SESSION TASK: ${TASK_ID} (detached, no symlink)"
    echo "   Pass this ID to /loom-works:run-task and /loom-works:checkpoint-task"
    echo ""
    MODE_DISPLAY="detached"
else
    rm -f "$SYMLINK_PATH"
    ln -s "tasks/${TASK_FILENAME}" "$SYMLINK_PATH"

    if [[ -L "$SYMLINK_PATH" ]]; then
        echo "-> Symlink creato: $(lw_docs_root)/current-task.md -> tasks/${TASK_FILENAME}"
    else
        echo "ERROR: Impossibile creare symlink" >&2
        exit 1
    fi
    MODE_DISPLAY="linked"
fi

echo "-> started: task=${TASK_ID} sha=${SHA_DISPLAY} mode=${MODE_DISPLAY} file=$(lw_docs_root)/tasks/${TASK_FILENAME}"
