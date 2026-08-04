#!/usr/bin/env bash

# =============================================================================
# resolve-registry-path.sh — dove atterra il registro di findings, senza chiedere
# Usage: resolve-registry-path.sh --name <basename.md> [--task <id>] [--docs-root <name>]
# =============================================================================
#
# Il registro di align-doc / lint-doc e' materiale di LAVORO, non doc di progetto:
# non entra mai in {docs_root}/. Ha pero' sempre un posto canonico, quindi la sua
# collocazione non e' una decisione da girare all'utente. Cascata:
#
#   1. task attiva con **Folder** popolato e presente  -> quella folder
#   2. task attiva senza folder                        -> set-task-folder.sh la crea
#   3. nessuna task attiva                             -> scratch .YY-MM-DD-<slug>
#
# Il caso 2 e' quello che prima finiva in AskUserQuestion: la risposta era comunque
# "creala", perche' una task che produce un registro ha per definizione materiale da
# ospitare. set-task-folder.sh e' permissivo (riusa la folder canonica se esiste) e
# aggiorna il campo **Folder** nel task file, quindi il giro dopo cade nel caso 1.
#
# Task attiva, stessa cascata di inject-task.sh e della statusline:
#   --task <id>  ->  $LOOM_TASK  ->  symlink {docs_root}/current-task.md
#
# Stampa (ultime righe, parsabili):
#   SOURCE=task-folder | task-folder-created | scratch | scratch-reused
#   FOLDER=<path relativo a project root>
#   REGISTRY_PATH=<path assoluto del file registro>
#
# Il file NON viene creato: lo scrive il chiamante. Qui si risolve solo dove.
#
# Env: PROJECT_ROOT, LOOM_TASK, LOOM_DOCS_ROOT
# Exit: 0 = risolto · 1 = errore duro (nome mancante, folder non creabile)
# =============================================================================

set -uo pipefail

NAME=""
TASK_ID="${LOOM_TASK:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)      NAME="$2"; shift 2 ;;
        --task)      TASK_ID="$2"; shift 2 ;;
        --docs-root) LOOM_DOCS_ROOT="$2"; export LOOM_DOCS_ROOT; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done

[[ -n "$NAME" ]] || { echo "ERROR: --name <basename.md> obbligatorio" >&2; exit 1; }
[[ "$NAME" == *.md ]] || NAME="${NAME}.md"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"

PROJECT_ROOT="$(lw_find_project_root)"
DOCS_ROOT="$(lw_docs_root)"

emit() {  # <source> <folder-rel>
    echo "SOURCE=$1"
    echo "FOLDER=$2"
    echo "REGISTRY_PATH=${PROJECT_ROOT}/$2/${NAME}"
}

# --- 1. Task attiva -----------------------------------------------------------
if [[ -z "$TASK_ID" ]]; then
    link="${PROJECT_ROOT}/${DOCS_ROOT}/current-task.md"
    if [[ -L "$link" ]]; then
        # il symlink punta a tasks/T63-slug.md: l'ID e' il primo token
        base="$(basename "$(readlink "$link")" .md)"
        TASK_ID="${base%%-*}"
    fi
fi

if [[ -n "$TASK_ID" ]]; then
    TASK_FILE="$(ls "${PROJECT_ROOT}/${DOCS_ROOT}/tasks/${TASK_ID}"-*.md 2>/dev/null | head -1)"
    if [[ -z "$TASK_FILE" ]]; then
        echo "-> task ${TASK_ID} senza task file: cado su scratch" >&2
        TASK_ID=""
    fi
fi

if [[ -n "$TASK_ID" ]]; then
    folder="$(sed -n 's/^- \*\*Folder\*\*:[[:space:]]*//p' "$TASK_FILE" | head -1)"
    folder="${folder%"${folder##*[![:space:]]}"}"   # rtrim
    folder="${folder#./}"

    if [[ -n "$folder" && -d "${PROJECT_ROOT}/${folder}" ]]; then
        emit "task-folder" "$folder"
        exit 0
    fi

    # Campo vuoto, o folder dichiarata ma sparita: set-task-folder.sh riusa la
    # canonica se c'e' e riscrive il campo. E' il ramo che prima chiedeva.
    if out="$("${SCRIPT_DIR}/../task/set-task-folder.sh" "$TASK_ID" 2>&1)"; then
        created="$(sed -n 's/^FOLDER_NAME=//p' <<< "$out" | head -1)"
        if [[ -n "$created" ]]; then
            echo "$out" | grep -v '^FOLDER_NAME=' >&2
            emit "task-folder-created" "$created"
            exit 0
        fi
    fi
    echo "-> set-task-folder.sh non ha prodotto una folder per ${TASK_ID}: cado su scratch" >&2
    echo "$out" >&2
fi

# --- 2. Nessuna task: scratch canonica ---------------------------------------
SLUG="${NAME%.md}"
SLUG="$(tr '[:upper:]_' '[:lower:]-' <<< "$SLUG" | tr -c 'a-z0-9-\n' '-')"
SLUG="${SLUG%-}"
DATE="$(date +%y-%m-%d)"
SCRATCH=".${DATE}-${SLUG}"

if [[ -d "${PROJECT_ROOT}/${SCRATCH}" ]]; then
    emit "scratch-reused" "$SCRATCH"
    exit 0
fi

if "${SCRIPT_DIR}/../scratch/scratch-new.sh" "$SLUG" >&2; then
    emit "scratch" "$SCRATCH"
    exit 0
fi

echo "ERROR: impossibile creare la scratch ${SCRATCH}" >&2
exit 1
