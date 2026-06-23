#!/bin/bash

# =============================================================================
# cleanup-done-tasks.sh - Pota task Done oltre soglia giorni
# Usage: cleanup-done-tasks.sh [--mode <repo|no-repo>] [--docs-root <path>]
#                               [--days N] [--apply] [task-id ...]
#
# Dry-run di default: elenca candidati senza modifiche.
# Con --apply: elimina task file + folder + riga tasks.md, un commit per task.
#
# Filtro opzionale: se passati task-id come argomenti, opera solo su quelli.
# =============================================================================

set -euo pipefail

DAYS=60
APPLY=0
TASK_FILTER=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)      LOOM_PROJECT_MODE="$2"; shift 2 ;;
        --docs-root) LOOM_DOCS_ROOT="$2"; shift 2 ;;
        --days)      DAYS="${2:?--days requires a number}"; shift 2 ;;
        --apply)     APPLY=1; shift ;;
        T*|D*)       TASK_FILTER+=("$1"); shift ;;
        *)           echo "ERROR: argomento sconosciuto: $1" >&2; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utils/lib.sh"

# Read an OPTIONAL '- **Label**: value' field from a task file.
# Returns empty string (exit 0) when the field is absent — safe under
# `set -euo pipefail`, where a bare `grep` no-match (exit 1) would abort.
read_field() {  # read_field <file> <label>
    grep -m1 "^- \*\*$2\*\*:" "$1" 2>/dev/null | sed 's/.*: *//' | tr -d '[:space:]' || true
}

PROJECT_ROOT="$(lw_find_project_root)"
DOCS_ROOT="$(lw_docs_root)"
TASKS_FILE="${PROJECT_ROOT}/${DOCS_ROOT}/tasks.md"
TASKS_DIR="${PROJECT_ROOT}/${DOCS_ROOT}/tasks"

if [[ ! -f "$TASKS_FILE" ]]; then
    echo "ERROR: tasks.md non trovato: ${TASKS_FILE}" >&2
    exit 1
fi

# ---- Collect Done task IDs from tasks.md ------------------------------------

mapfile -t DONE_IDS < <(
    awk '/^## Tasks Overview/{in_s=1; next} /^## /{if(in_s) in_s=0} in_s && /✔️/' "$TASKS_FILE" \
    | grep -oP '^\|\s*\K[A-Z0-9]+(?=\s*\|)'
)

if [[ ${#DONE_IDS[@]} -eq 0 ]]; then
    echo "-> nessuna task Done in tasks.md"
    exit 0
fi

# Apply filter if specified
if [[ ${#TASK_FILTER[@]} -gt 0 ]]; then
    FILTERED=()
    for id in "${DONE_IDS[@]}"; do
        for f in "${TASK_FILTER[@]}"; do
            if [[ "$id" == "$f" ]]; then
                FILTERED+=("$id")
                break
            fi
        done
    done
    DONE_IDS=("${FILTERED[@]}")
fi

# ---- Determine age for each Done task ----------------------------------------

NOW_EPOCH=$(date +%s)

CANDIDATES=()        # "ID|age_days|task_file|folder_path"
SKIPPED=()           # "ID|reason"

for task_id in "${DONE_IDS[@]}"; do
    task_file=$(ls "${TASKS_DIR}/${task_id}-"*.md 2>/dev/null | head -1 || true)
    if [[ -z "$task_file" || ! -f "$task_file" ]]; then
        SKIPPED+=("${task_id}|task file non trovato")
        continue
    fi

    # Primary: Last tracked commit field
    tracked_sha=$(read_field "$task_file" "Last tracked commit")

    done_date=""
    if [[ -n "$tracked_sha" ]]; then
        done_date=$(git -C "$PROJECT_ROOT" show -s --format=%cI "$tracked_sha" 2>/dev/null || true)
    fi

    # Fallback: last commit touching the task file
    if [[ -z "$done_date" ]]; then
        rel_path="${DOCS_ROOT}/tasks/$(basename "$task_file")"
        done_date=$(git -C "$PROJECT_ROOT" log -1 --format=%cI -- "$rel_path" 2>/dev/null || true)
    fi

    if [[ -z "$done_date" ]]; then
        SKIPPED+=("${task_id}|data Done non determinabile (skip sicuro)")
        continue
    fi

    done_epoch=$(date -d "$done_date" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S%z" "$done_date" +%s 2>/dev/null || true)
    if [[ -z "$done_epoch" ]]; then
        SKIPPED+=("${task_id}|data Done non parsabile: ${done_date}")
        continue
    fi

    age_days=$(( (NOW_EPOCH - done_epoch) / 86400 ))

    if [[ $age_days -lt $DAYS ]]; then
        continue
    fi

    # Read folder field
    folder_field=$(read_field "$task_file" "Folder")
    folder_path=""
    if [[ -n "$folder_field" && "$folder_field" != "" ]]; then
        # folder_field is root-relative like ./26-06-03-T10-...
        folder_path="${PROJECT_ROOT}/${folder_field#./}"
        if [[ ! -d "$folder_path" ]]; then
            folder_path=""
        fi
    fi

    CANDIDATES+=("${task_id}|${age_days}|${task_file}|${folder_path}")
done

# ---- Report ------------------------------------------------------------------

if [[ ${#SKIPPED[@]} -gt 0 ]]; then
    echo "⚠️  Skip (dati mancanti):"
    for s in "${SKIPPED[@]}"; do
        id="${s%%|*}"; reason="${s#*|}"
        echo "   ${id}: ${reason}"
    done
    echo ""
fi

if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
    echo "-> nessuna task Done oltre ${DAYS} giorni"
    exit 0
fi

echo "Candidati (Done > ${DAYS}gg):"
for c in "${CANDIDATES[@]}"; do
    id="${c%%|*}"; rest="${c#*|}"; age="${rest%%|*}"; rest="${rest#*|}"; tf="${rest%%|*}"; fp="${rest#*|}"
    folder_info=""
    [[ -n "$fp" ]] && folder_info=" + folder $(basename "$fp")"
    echo "   ${id}  (${age}gg)  $(basename "$tf")${folder_info}"
done

if [[ $APPLY -eq 0 ]]; then
    echo ""
    echo "-> dry-run: nessuna modifica (aggiungi --apply per eseguire)"
    exit 0
fi

# ---- Apply: delete + commit per task -----------------------------------------

if ! lw_is_repo; then
    echo "ERROR: --apply richiede modalità repo" >&2
    exit 1
fi

for c in "${CANDIDATES[@]}"; do
    id="${c%%|*}"; rest="${c#*|}"; age="${rest%%|*}"; rest="${rest#*|}"; tf="${rest%%|*}"; fp="${rest#*|}"
    slug=$(basename "$tf" .md); slug="${slug#${id}-}"

    echo ""
    echo "--- purge ${id} ---"

    # Determine Done SHA for commit body
    tracked_sha=$(read_field "$tf" "Last tracked commit")
    done_date=""
    if [[ -n "$tracked_sha" ]]; then
        done_date=$(git -C "$PROJECT_ROOT" show -s --format="%cI" "$tracked_sha" 2>/dev/null || true)
    fi
    if [[ -z "$done_date" ]]; then
        rel_path="${DOCS_ROOT}/tasks/$(basename "$tf")"
        done_date=$(git -C "$PROJECT_ROOT" log -1 --format=%cI -- "$rel_path" 2>/dev/null || true)
    fi

    # Remove task file
    rel_tf="${DOCS_ROOT}/tasks/$(basename "$tf")"
    git -C "$PROJECT_ROOT" rm -f "$rel_tf"
    echo "-> rimosso: ${rel_tf}"

    # Remove folder if present
    folder_info_body=""
    if [[ -n "$fp" ]]; then
        rel_fp="$(realpath --relative-to="$PROJECT_ROOT" "$fp")"
        git -C "$PROJECT_ROOT" rm -rf "$rel_fp"
        echo "-> rimossa folder: ${rel_fp}/"
        folder_info_body="  - ${rel_fp}/"
    fi

    # Remove row from tasks.md
    awk -v tid="$id" '
        /^## Tasks Overview/ { in_s=1 }
        /^## / && !/^## Tasks Overview/ { in_s=0 }
        in_s && $0 ~ ("^\\| *"tid" *\\|") { next }
        { print }
    ' "$TASKS_FILE" > "${TASKS_FILE}.tmp"
    mv "${TASKS_FILE}.tmp" "$TASKS_FILE"
    git -C "$PROJECT_ROOT" add "$TASKS_FILE"
    echo "-> rimossa riga tasks.md: ${id}"

    # Remove node from Execution Plan if present (lines like "T14:" or "-> T14" etc.)
    # Only lines containing exactly the task ID as a word token
    sed -i "/\b${id}\b/d" "$TASKS_FILE" 2>/dev/null || true
    git -C "$PROJECT_ROOT" add "$TASKS_FILE"

    # Commit
    COMMIT_BODY="Purged (restore: git checkout <this-commit>~1 -- <path>):
  - ${rel_tf}
${folder_info_body}Done commit: ${tracked_sha:-unknown} (${done_date:-unknown})"

    git -C "$PROJECT_ROOT" commit -m "$(printf 'chore(tasks): purge done %s (%s) — Done >%sdays\n\n%s' "$id" "$slug" "$age" "$COMMIT_BODY")"
    echo "-> commit: chore(tasks): purge done ${id}"
done

echo ""
echo "-> purge completato: ${#CANDIDATES[@]} task eliminate"
