#!/bin/bash

# =============================================================================
# create-task.sh - Aggiunge task alla tabella tasks.md e committa
# Usage: create-task.sh <task-id> <task-name> <task-desc> <priority>
# Env:   PROJECT_ROOT (default: $PWD)
# =============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode) LOOM_PROJECT_MODE="$2"; shift 2 ;;
        --docs-root) LOOM_DOCS_ROOT="$2"; shift 2 ;;
        *) break ;;
    esac
done

TASK_ID="${1:?Usage: create-task.sh [--mode <repo|no-repo>] <task-id> <task-name> <task-desc> <priority>}"
TASK_NAME="${2:?Task name required (kebab-case per filename)}"
TASK_DESC="${3:?Task description required}"
PRIORITY="${4:?Priority required (High/Med/Low)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"

PROJECT_ROOT="$(lw_find_project_root)"
TASKS_FILE="${PROJECT_ROOT}/$(lw_docs_root)/tasks.md"
TASK_FILE="${PROJECT_ROOT}/$(lw_docs_root)/tasks/${TASK_ID}-${TASK_NAME}.md"

if [[ ! -f "$TASKS_FILE" ]]; then
    echo "ERROR: Tasks file non trovato: ${TASKS_FILE}" >&2
    exit 1
fi

if [[ ! -f "$TASK_FILE" ]]; then
    echo "ERROR: Task file non trovato: ${TASK_FILE}" >&2
    echo "   Assicurati di aver creato il file task prima di eseguire questo script" >&2
    exit 1
fi

case "$PRIORITY" in
    High|Med|Low) ;;
    *)
        echo "ERROR: Priority non valida: ${PRIORITY} (deve essere High, Med o Low)" >&2
        exit 1
        ;;
esac

case "$PRIORITY" in
    High) PRIORITY_EMOJI="🔥" ;;
    Med)  PRIORITY_EMOJI="⚡" ;;
    Low)  PRIORITY_EMOJI="🔹" ;;
esac

TASK_DESC_TRUNCATED=$(printf '%s' "$TASK_DESC" | cut -c1-64)

case "$TASK_ID" in
    D*) KIND_EMOJI="📝" ;;
    *)  KIND_EMOJI="⚙️" ;;
esac

NEW_ROW="| ${TASK_ID} | ${PRIORITY_EMOJI} | ${KIND_EMOJI} | 🔵 | ${TASK_DESC_TRUNCATED} |"

awk -v new_row="$NEW_ROW" '
    /^\| ---/ && in_tasks_section {
        print
        print new_row
        next
    }
    /^## Tasks Overview/ {
        in_tasks_section = 1
    }
    /^## / && !/^## Tasks Overview/ {
        in_tasks_section = 0
    }
    { print }
' "$TASKS_FILE" > "${TASKS_FILE}.tmp"

if cmp -s "$TASKS_FILE" "${TASKS_FILE}.tmp"; then
    echo "ERROR: Tabella Tasks Overview non trovata o riga non inserita" >&2
    rm -f "${TASKS_FILE}.tmp"
    exit 1
fi

mv "${TASKS_FILE}.tmp" "$TASKS_FILE"
echo "-> Aggiunta task ${TASK_ID} alla tabella"

cd "$PROJECT_ROOT" || exit 1

if lw_is_repo; then
    lw_git_add "$TASK_FILE"
    lw_git_add "$TASKS_FILE"
    lw_git_commit "task(${TASK_ID}): create - ${TASK_DESC}"
    lw_git_push
else
    echo "-> no-repo mode: skip git add/commit/push"
fi

echo "-> ✔️task=${TASK_ID} file=$(lw_docs_root)/tasks/${TASK_ID}-${TASK_NAME}.md"
