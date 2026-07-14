#!/bin/bash

# =============================================================================
# cleanup-done-tasks.sh - Pota task Done oltre soglia giorni
# Usage: cleanup-done-tasks.sh [--mode <repo|no-repo>] [--docs-root <path>]
#                               [--days N] [--apply] [task-id ...]
#
# Dry-run di default: elenca candidati senza modifiche.
# Con --apply: elimina task file + folder + riga tasks.md, un commit per task.
# Inoltre riconcilia le righe ORFANE (Done in tasks.md ma file gia' assente):
# rimuove riga+nodo, indipendentemente dalla soglia --days. Senza questo, l'ID
# resterebbe vivo solo come riga e verrebbe riusato dall'allocatore -> collisione.
#
# Filtro opzionale: se passati task-id come argomenti, opera solo su quelli.
# =============================================================================

set -euo pipefail

DAYS=60
APPLY=0
IGNORED_MODE=""   # "" | keep | purge — come gestire i file ignored/untracked in una task folder
TASK_FILTER=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)          LOOM_PROJECT_MODE="$2"; shift 2 ;;
        --docs-root)     LOOM_DOCS_ROOT="$2"; shift 2 ;;
        --days)          DAYS="${2:?--days requires a number}"; shift 2 ;;
        --apply)         APPLY=1; shift ;;
        --ignored-files) IGNORED_MODE="${2:?--ignored-files requires keep|purge}"; shift 2 ;;
        T*|D*)           TASK_FILTER+=("$1"); shift ;;
        *)               echo "ERROR: argomento sconosciuto: $1" >&2; exit 1 ;;
    esac
done

if [[ -n "$IGNORED_MODE" && "$IGNORED_MODE" != "keep" && "$IGNORED_MODE" != "purge" ]]; then
    echo "ERROR: --ignored-files accetta 'keep' o 'purge' (dato: ${IGNORED_MODE})" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utils/lib.sh"

# Read an OPTIONAL '- **Label**: value' field from a task file.
# Returns empty string (exit 0) when the field is absent — safe under
# `set -euo pipefail`, where a bare `grep` no-match (exit 1) would abort.
# Returns ONLY the first whitespace-delimited token of the value (path / SHA):
# an inline annotation after it — e.g. `Folder: .26-06-16-cat (condivisa con T19)`
# — is dropped. The old `tr -d '[:space:]'` collapsed such a note INTO the path
# (`.26-06-16-cat(condivisaconT19)`) → nonexistent dir → folder silently skipped
# → orphaned folder with no warning. First-token extraction fixes that.
read_field() {  # read_field <file> <label>
    grep -m1 "^- \*\*$2\*\*:" "$1" 2>/dev/null | sed 's/^[^:]*: *//' | awk '{print $1; exit}' || true
}

PROJECT_ROOT="$(lw_find_project_root)"
DOCS_ROOT="$(lw_docs_root)"
TASKS_FILE="${PROJECT_ROOT}/${DOCS_ROOT}/tasks.md"
TASKS_DIR="${PROJECT_ROOT}/${DOCS_ROOT}/tasks"

if [[ ! -f "$TASKS_FILE" ]]; then
    echo "ERROR: tasks.md non trovato: ${TASKS_FILE}" >&2
    exit 1
fi

# Remove a task's Overview row + Execution Plan node from tasks.md.
# Shared by candidate purge and orphan-row reconciliation. Leaves the file
# staged (git add); the caller owns the commit.
remove_task_from_tasksmd() {  # <task_id>
    local id="$1"
    awk -v tid="$id" '
        /^## Tasks Overview/ { in_s=1 }
        /^## / && !/^## Tasks Overview/ { in_s=0 }
        in_s && $0 ~ ("^\\| *"tid" *\\|") { next }
        { print }
    ' "$TASKS_FILE" > "${TASKS_FILE}.tmp"
    mv "${TASKS_FILE}.tmp" "$TASKS_FILE"
    # Execution Plan node: lines containing the ID as a word token
    sed -i "/\b${id}\b/d" "$TASKS_FILE" 2>/dev/null || true
    git -C "$PROJECT_ROOT" add "$TASKS_FILE"
}

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
ORPHANS=()           # "ID" — riga Done in tasks.md ma file gia' assente
SKIPPED=()           # "ID|reason"

for task_id in "${DONE_IDS[@]}"; do
    task_file=$(ls "${TASKS_DIR}/${task_id}-"*.md 2>/dev/null | head -1 || true)
    if [[ -z "$task_file" || ! -f "$task_file" ]]; then
        # Riga Done senza file: residuo da riconciliare. Nessun file da
        # trattenere -> indipendente dalla soglia --days (rimuovi riga+nodo).
        ORPHANS+=("${task_id}")
        continue
    fi

    # Primary: "✔️ Done at YYYY-MM-DD" inline nel task file (sorgente deterministica)
    done_date=""
    progress_line=$(grep -m1 '^- \*\*Progress\*\*:.*Done at' "$task_file" 2>/dev/null || true)
    if [[ -n "$progress_line" ]]; then
        done_date=$(echo "$progress_line" | grep -oP 'Done at \K\d{4}-\d{2}-\d{2}' || true)
    fi

    # Fallback 1: Last tracked commit SHA → data git
    tracked_sha=$(read_field "$task_file" "Last tracked commit")
    if [[ -z "$done_date" && -n "$tracked_sha" ]]; then
        done_date=$(git -C "$PROJECT_ROOT" show -s --format=%cI "$tracked_sha" 2>/dev/null || true)
    fi

    # Fallback 2: last commit touching the task file
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

if [[ ${#ORPHANS[@]} -gt 0 ]]; then
    echo "🔧 Righe orfane (Done, file assente) — da riconciliare:"
    for oid in "${ORPHANS[@]}"; do
        echo "   ${oid}"
    done
    echo ""
fi

if [[ ${#CANDIDATES[@]} -eq 0 && ${#ORPHANS[@]} -eq 0 ]]; then
    echo "-> nessuna task Done oltre ${DAYS} giorni, nessuna riga orfana"
    exit 0
fi

if [[ ${#CANDIDATES[@]} -gt 0 ]]; then
    echo "Candidati (Done > ${DAYS}gg):"
    for c in "${CANDIDATES[@]}"; do
        id="${c%%|*}"; rest="${c#*|}"; age="${rest%%|*}"; rest="${rest#*|}"; tf="${rest%%|*}"; fp="${rest#*|}"
        folder_info=""
        if [[ -n "$fp" ]]; then
            folder_info=" + folder $(basename "$fp")"
            surv="$(lw_folder_survivors "$(realpath --relative-to="$PROJECT_ROOT" "$fp")")"
            if [[ -n "$surv" ]]; then
                n=$(printf '%s\n' "$surv" | grep -c .)
                folder_info="${folder_info} [⚠ ${n} ignored/untracked]"
            fi
        fi
        echo "   ${id}  (${age}gg)  $(basename "$tf")${folder_info}"
    done
fi

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

# ---- Gate: task folder con file ignored/untracked ----------------------------
# `git rm -rf` non rimuove i file ignorati/untracked di una folder: sopravvivono
# su disco (il .gitignore che li nascondeva sparisce → "riemergono"). Se il
# chiamante non ha indicato come gestirli, fallisci PRIMA di qualsiasi modifica.
if [[ -z "$IGNORED_MODE" ]]; then
    gate_hit=0
    for c in "${CANDIDATES[@]}"; do
        fp="${c##*|}"
        [[ -n "$fp" && -e "$fp" ]] || continue
        rel_fp="$(realpath --relative-to="$PROJECT_ROOT" "$fp")"
        surv="$(lw_folder_survivors "$rel_fp")"
        [[ -n "$surv" ]] || continue
        if [[ $gate_hit -eq 0 ]]; then
            echo "" >&2
            echo "ERROR: task folder con file che 'git rm' non rimuove (ignored/untracked):" >&2
            gate_hit=1
        fi
        echo "  ${rel_fp}/" >&2
        printf '%s\n' "$surv" | sed 's#^#    - #' >&2
    done
    if [[ $gate_hit -eq 1 ]]; then
        echo "" >&2
        echo "Il chiamante deve indicare come gestirli, poi rilanciare --apply con:" >&2
        echo "  --ignored-files keep    → secondo commit che PRESERVA quei file in git" >&2
        echo "  --ignored-files purge   → rm secco della folder (path assoluto, guardato)" >&2
        exit 2
    fi
fi

# ---- Reconcile orphan rows (file already absent: drop the dangling row) ------

for id in "${ORPHANS[@]}"; do
    echo ""
    echo "--- reconcile orphan ${id} ---"
    remove_task_from_tasksmd "$id"
    git -C "$PROJECT_ROOT" commit -m "$(printf 'chore(tasks): reconcile orphan row %s (file already absent)' "$id")"
    echo "-> riga orfana rimossa + commit: ${id}"
done

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

    # keep: PRIMA di qualsiasi git rm, snapshotta in un commit dedicato i file che
    # sopravviverebbero al purge (ignored/untracked). Cosi' restano recuperabili da
    # quel commit; poi il purge sotto li elimina dal disco insieme al resto (ora
    # tracciati). A prescindere dalla scelta, i file NON restano in locale — keep
    # li conserva solo in git history, purge li perde.
    if [[ "$IGNORED_MODE" == "keep" && -n "$fp" && -e "$fp" ]]; then
        rel_fp="$(realpath --relative-to="$PROJECT_ROOT" "$fp")"
        if [[ -n "$(lw_folder_survivors "$rel_fp")" ]]; then
            git -C "$PROJECT_ROOT" add -f -- "$rel_fp"
            git -C "$PROJECT_ROOT" commit -m "$(printf 'chore(tasks): keep ignored files of %s before purge (%s)' "$id" "$rel_fp")"
            echo "-> keep: snapshot file ignored/untracked in commit dedicato (${rel_fp}/)"
        fi
    fi

    # Remove task file
    rel_tf="${DOCS_ROOT}/tasks/$(basename "$tf")"
    git -C "$PROJECT_ROOT" rm -f "$rel_tf"
    echo "-> rimosso: ${rel_tf}"

    # Remove folder if present — solo se ancora su disco. Task che condividono la
    # stessa Folder si portano dietro lo STESSO $fp (risolto in blocco a monte):
    # la prima la rimuove, la seconda la trova gia' sparita → skip pulito (evita il
    # doppio `git rm`, exit 128 sotto `set -e`, che abortirebbe il run a meta').
    folder_info_body=""
    if [[ -n "$fp" && -e "$fp" ]]; then
        rel_fp="$(realpath --relative-to="$PROJECT_ROOT" "$fp")"
        git -C "$PROJECT_ROOT" rm -rf "$rel_fp"
        echo "-> rimossa folder (tracked): ${rel_fp}/"
        folder_info_body="  - ${rel_fp}/"
        # git rm NON tocca i file ignored/untracked (ne' le dir rimaste vuote):
        # rm secco guardato per farli sparire dal disco. In keep sono gia' stati
        # snapshottati sopra; in purge vanno persi. In ogni caso: via dal locale.
        if [[ -e "$fp" ]]; then
            lw_safe_rmrf "$fp"
            echo "-> rm secco residui su disco: ${rel_fp}/"
        fi
    elif [[ -n "$fp" ]]; then
        echo "-> folder gia' rimossa da una task che la condivide: $(basename "$fp")/"
    fi

    # Remove row + Execution Plan node from tasks.md
    remove_task_from_tasksmd "$id"
    echo "-> rimossa riga tasks.md: ${id}"

    # Commit
    COMMIT_BODY="Purged (restore: git checkout <this-commit>~1 -- <path>):
  - ${rel_tf}
${folder_info_body}Done commit: ${tracked_sha:-unknown} (${done_date:-unknown})"

    git -C "$PROJECT_ROOT" commit -m "$(printf 'chore(tasks): purge done %s (%s) — Done >%sdays\n\n%s' "$id" "$slug" "$age" "$COMMIT_BODY")"
    echo "-> commit: chore(tasks): purge done ${id}"
done

echo ""
echo "-> completato: ${#CANDIDATES[@]} task purgate, ${#ORPHANS[@]} righe orfane riconciliate"
