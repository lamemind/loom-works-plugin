#!/bin/bash

# =============================================================================
# set-task-folder.sh - Assegna il folder canonico a una task esistente
# Usage: set-task-folder.sh [<task-id>] [--slug <slug>] [--docs-root <path>]
# Env:   PROJECT_ROOT (default: $PWD), LOOM_TASK
# =============================================================================
#
# Naming canonico: .YY-MM-DD-{slug}
#
# Assegna il NOME, non crea la directory: il campo **Folder** del task file dice
# dove andra' il materiale, e la folder nasce sul disco col primo file che ci
# scrive qualcuno (`Write` crea le dir intermedie; da bash `mkdir -p` del path
# gia' dichiarato). Una folder vuota non e' materiale di nessuno e git non la
# traccia comunque: creandola in anticipo si sporca la project root con
# directory che nella maggior parte dei casi restano vuote fino alla purge.
#
# Se la folder canonica esiste gia' (rilancio, o folder riempita a mano) la
# riusa e la stagia.
# Stampa il folder name (relativo a PROJECT_ROOT).
#
# task-id omesso -> cascata $LOOM_TASK -> symlink current-task.md (lw_resolve_task).
# =============================================================================

set -euo pipefail

TASK_ID=""
if [[ $# -gt 0 && "$1" != -* ]]; then
    TASK_ID="$1"
    shift
fi

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

RESOLVED="$(lw_resolve_task "$TASK_ID")" || exit 1
eval "$RESOLVED"

# Ricava slug dal task file se non override
if [[ -n "$SLUG_OVERRIDE" ]]; then
    SLUG="$SLUG_OVERRIDE"
else
    BASENAME=$(basename "$TASK_FILE" .md)
    SLUG="${BASENAME#${TASK_ID}-}"
fi

DATE=$(date +%y-%m-%d)
FOLDER_NAME=".${DATE}-${SLUG}"
FOLDER_PATH="${PROJECT_ROOT}/${FOLDER_NAME}"
# Root-relative form written into the **Folder** field: the leading ./ makes the
# parent explicit (project root) so readers never re-derive it as docs/tasks/.
FOLDER_FIELD="./${FOLDER_NAME}"

# Lazy: the directory is NOT created here. Only an already-existing folder (a
# rerun, or one filled by hand) is reused and staged below.
FOLDER_EXISTS=no
[[ -d "$FOLDER_PATH" ]] && FOLDER_EXISTS=yes

# Update **Folder** field in task file (unconditional replace).
if ! grep -q '^- \*\*Folder\*\*:' "$TASK_FILE"; then
    echo "ERROR: campo '- **Folder**:' mancante in ${TASK_FILE}" >&2
    exit 1
fi
sed -i "s|^- \*\*Folder\*\*:.*\$|- **Folder**: ${FOLDER_FIELD}|" "$TASK_FILE"
echo "-> updated **Folder** field in $(basename "$TASK_FILE")"

# Stage the task file, plus the folder when it is already on disk with content.
[[ "$FOLDER_EXISTS" == yes ]] && lw_git_add "$FOLDER_PATH"
lw_git_add "$TASK_FILE"

if [[ "$FOLDER_EXISTS" == yes ]]; then
    echo "-> task folder già su disco, riuso: ${FOLDER_NAME}/"
    echo "   folder + task file staged (commit deferred to caller)"
else
    echo "-> task folder assegnata: ${FOLDER_NAME}/ (non creata)"
    echo "   nasce sul disco col primo file che ci scrivi"
    echo "   task file staged (commit deferred to caller)"
fi
echo "FOLDER_NAME=${FOLDER_NAME}"
