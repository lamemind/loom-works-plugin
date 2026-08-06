#!/bin/bash

# =============================================================================
# start-task.sh - Attiva una task per checkpoint tracking
# Usage: start-task.sh [--detach] <task-id>
# Env:   PROJECT_ROOT (default: $PWD)
# =============================================================================

DETACH=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --docs-root) LOOM_DOCS_ROOT="$2"; shift 2 ;;
        --detach) DETACH=1; shift ;;
        *) break ;;
    esac
done

TASK_ID="${1:?Usage: start-task.sh [--detach] <task-id>}"

# -----------------------------------------------------------------------------
# Guardia: sessione gia' vincolata via $LOOM_TASK
# -----------------------------------------------------------------------------
# start-task e' la primitiva che CREA il binding, scrivendo il symlink. Dove il
# binding esiste gia' per altra via (env esportata dallo spawn deck) qui non c'e'
# mestiere: il symlink resterebbe un puntatore che la sessione corrente ignora
# — l'env batte il symlink nella cascata — cioe' esattamente la forma di stale
# che questa guardia esiste per non produrre. Rifiuto anche quando l'ID coincide:
# concordi adesso, divergenti al primo start-task su un'altra task.

if [[ -n "${LOOM_TASK:-}" ]]; then
    {
        echo "ERROR: sessione gia' vincolata a ${LOOM_TASK} via \$LOOM_TASK — start-task non procede."
        echo "       Niente symlink, niente riga 🟡 in tasks.md, niente SHA di tracking."
        echo ""
        echo "       - lavorare su ${LOOM_TASK}      -> /loom-works:run-task (risolve dall'env)"
        echo "       - lavorare su un'altra task  -> /loom-works:run-task <ID> (arg esplicito, batte l'env)"
        echo "       - creare il binding di worktree -> rilancia in una sessione senza \$LOOM_TASK"
    } >&2
    exit 1
fi

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
# Aggiorna file task: Progress
# -----------------------------------------------------------------------------

sed -i '0,/^- \*\*Progress\*\*:/s/^\(- \*\*Progress\*\*:\).*/\1 🟡 0%/' "$TASK_FILE"

echo "-> Task file aggiornato: Progress 🟡 0%"

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

echo "-> started: task=${TASK_ID} mode=${MODE_DISPLAY} file=$(lw_docs_root)/tasks/${TASK_FILENAME}"
