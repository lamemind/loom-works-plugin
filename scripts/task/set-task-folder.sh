#!/bin/bash

# =============================================================================
# set-task-folder.sh - Crea folder canonico per una task esistente
# Usage: set-task-folder.sh <task-id> [--slug <slug>]
# Env:   PROJECT_ROOT (default: $PWD)
# =============================================================================
#
# Naming canonico: .YY-MM-DD-{slug}
# Chiama folder-create.sh per mkdir.
# Stampa il folder name creato (relativo a PROJECT_ROOT).
# =============================================================================

set -euo pipefail

TASK_ID="${1:?Usage: set-task-folder.sh <task-id> [--slug <slug>] [--docs-root <path>]}"
shift

SLUG_OVERRIDE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --slug)
            SLUG_OVERRIDE="${2:?--slug requires a value}"
            shift 2
            ;;
        --docs-root)
            LOOM_DOCS_ROOT="${2:?--docs-root requires a value}"
            shift 2
            ;;
        *)
            echo "ERROR: argomento sconosciuto: $1" >&2
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"

PROJECT_ROOT="$(lw_find_project_root)"

# Ricava slug dal task file se non override
if [[ -n "$SLUG_OVERRIDE" ]]; then
    SLUG="$SLUG_OVERRIDE"
else
    TASK_FILE_PATTERN="${PROJECT_ROOT}/$(lw_docs_root)/tasks/${TASK_ID}-*.md"
    TASK_FILE=$(ls $TASK_FILE_PATTERN 2>/dev/null | head -1)
    if [[ -z "$TASK_FILE" ]]; then
        echo "ERROR: task file non trovato per ${TASK_ID}" >&2
        exit 1
    fi
    BASENAME=$(basename "$TASK_FILE" .md)
    SLUG="${BASENAME#${TASK_ID}-}"
fi

DATE=$(date +%y-%m-%d)
FOLDER_NAME=".${DATE}-${SLUG}"
FOLDER_PATH="${PROJECT_ROOT}/${FOLDER_NAME}"

"${SCRIPT_DIR}/../utils/folder-create.sh" "$FOLDER_PATH"

# Update **Folder** field in task file (unconditional replace).
TASK_FILE_PATTERN="${PROJECT_ROOT}/$(lw_docs_root)/tasks/${TASK_ID}-*.md"
TASK_FILE=$(ls $TASK_FILE_PATTERN 2>/dev/null | head -1)
if [[ -z "$TASK_FILE" ]]; then
    echo "ERROR: task file non trovato per ${TASK_ID} (atteso: ${TASK_FILE_PATTERN})" >&2
    exit 1
fi
if ! grep -q '^- \*\*Folder\*\*:' "$TASK_FILE"; then
    echo "ERROR: campo '- **Folder**:' mancante in ${TASK_FILE}" >&2
    exit 1
fi
sed -i "s|^- \*\*Folder\*\*:.*\$|- **Folder**: ${FOLDER_NAME}|" "$TASK_FILE"
echo "-> updated **Folder** field in $(basename "$TASK_FILE")"

# Stage folder + task file so callers' next commit includes them.
# In no-repo mode lw_git_add is a noop.
lw_git_add "$FOLDER_PATH"
lw_git_add "$TASK_FILE"

echo "-> created task folder: ${FOLDER_NAME}/"
echo "   folder + task file staged (commit deferred to caller)"
echo "FOLDER_NAME=${FOLDER_NAME}"
