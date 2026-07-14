#!/bin/bash

# =============================================================================
# clean-tasks.sh - Purge task ON-DEMAND per ID/range (qualsiasi stato, qualsiasi eta')
# Usage: clean-tasks.sh [--mode <repo|no-repo>] [--docs-root <path>] [--apply] <SPEC>...
#
# SPEC:
#   Tnn          id singolo            (es. T15)
#   Tnn-Tmm      range inclusivo       (es. T15-T20)
#   Tnn-mm       range shorthand       (es. T15-20)
#
# Dry-run di default: elenca i target con stato [Done]/[NOT Done], senza modifiche,
# ed emette una riga SUMMARY machine-readable.
# Con --apply: elimina task file + folder dot-prefixed + riga tasks.md, un commit
# per task. NON filtra per stato ne' per eta': pota qualunque ID indicato.
#
# La POLICY di conferma (chiedere quando ci sono NON-Done) vive nella skill, non
# qui. Per cleanup per ETA' (Done > N giorni) usa cleanup-done-tasks.sh.
# =============================================================================

set -euo pipefail

APPLY=0
IGNORED_MODE=""   # "" | keep | purge — come gestire i file ignored/untracked in una task folder
SPECS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)          LOOM_PROJECT_MODE="$2"; shift 2 ;;
        --docs-root)     LOOM_DOCS_ROOT="$2"; shift 2 ;;
        --apply)         APPLY=1; shift ;;
        --ignored-files) IGNORED_MODE="${2:?--ignored-files requires keep|purge}"; shift 2 ;;
        [A-Za-z]*)       SPECS+=("$1"); shift ;;
        *)               echo "ERROR: argomento sconosciuto: $1" >&2; exit 1 ;;
    esac
done

if [[ -n "$IGNORED_MODE" && "$IGNORED_MODE" != "keep" && "$IGNORED_MODE" != "purge" ]]; then
    echo "ERROR: --ignored-files accetta 'keep' o 'purge' (dato: ${IGNORED_MODE})" >&2
    exit 1
fi

if [[ ${#SPECS[@]} -eq 0 ]]; then
    echo "ERROR: nessuno SPEC task (es. T15, T15-T20, T15-20)" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utils/lib.sh"

# Read an OPTIONAL '- **Label**: value' field from a task file.
# Empty string (exit 0) when absent — safe under `set -euo pipefail`.
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
CURRENT_LINK="${PROJECT_ROOT}/${DOCS_ROOT}/current-task.md"

if [[ ! -f "$TASKS_FILE" ]]; then
    echo "ERROR: tasks.md non trovato: ${TASKS_FILE}" >&2
    exit 1
fi

# Remove a task's Overview row + Execution Plan node from tasks.md.
# Leaves the file staged (git add); the caller owns the commit.
# Identica a cleanup-done-tasks.sh per garantire comportamento uniforme.
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

# current-task.md e' un symlink runtime verso la task attiva. Se punta alla task
# che stiamo rimuovendo, eliminalo per non lasciarlo dangling.
maybe_drop_current_link() {  # <removed_basename>
    [[ -L "$CURRENT_LINK" ]] || return 0
    local target
    target="$(readlink "$CURRENT_LINK")"
    if [[ "$(basename "$target")" == "$1" ]]; then
        rm -f "$CURRENT_LINK"
        echo "-> rimosso symlink current-task.md (puntava alla task rimossa)"
    fi
}

# Stato Done/open dal campo Progress (✔️ o "Done at" => done).
task_status() {  # <task_file> -> "done" | "open"
    local line
    line=$(grep -m1 '^- \*\*Progress\*\*:' "$1" 2>/dev/null || true)
    if [[ "$line" == *"✔️"* || "$line" == *"Done at"* ]]; then
        echo "done"
    else
        echo "open"
    fi
}

# 0 se l'ID ha una riga nella Tasks Overview (anche senza file: orfana).
row_exists() {  # <task_id>
    awk -v tid="$1" '
        /^## Tasks Overview/ { in_s=1 }
        /^## / && !/^## Tasks Overview/ { in_s=0 }
        in_s && $0 ~ ("^\\| *"tid" *\\|") { found=1 }
        END { exit !found }
    ' "$TASKS_FILE"
}

# ---- Expand SPECs to a unique ordered ID list --------------------------------

REQ_IDS=()
add_id() {  # <id>
    local id="$1" e
    for e in "${REQ_IDS[@]:-}"; do
        [[ "$e" == "$id" ]] && return 0
    done
    REQ_IDS+=("$id")
}

for spec in "${SPECS[@]}"; do
    SPEC_UC="${spec^^}"
    if [[ "$SPEC_UC" =~ ^([A-Z]+)([0-9]+)-([A-Z]*)([0-9]+)$ ]]; then
        pfx="${BASH_REMATCH[1]}"; start="${BASH_REMATCH[2]}"
        epfx="${BASH_REMATCH[3]}"; end="${BASH_REMATCH[4]}"
        if [[ -n "$epfx" && "$epfx" != "$pfx" ]]; then
            echo "ERROR: range con prefissi diversi: ${spec}" >&2; exit 1
        fi
        s=$((10#$start)); e=$((10#$end))
        if [[ $s -gt $e ]]; then
            echo "ERROR: range invertito (${start} > ${end}): ${spec}" >&2; exit 1
        fi
        for ((i=s; i<=e; i++)); do add_id "$(printf '%s%02d' "$pfx" "$i")"; done
    elif [[ "$SPEC_UC" =~ ^([A-Z]+)([0-9]+)$ ]]; then
        add_id "$(printf '%s%02d' "${BASH_REMATCH[1]}" "$((10#${BASH_REMATCH[2]}))")"
    else
        echo "ERROR: SPEC non valido: ${spec} (atteso Tnn | Tnn-Tmm | Tnn-mm)" >&2
        exit 1
    fi
done

# ---- Resolve each requested ID -----------------------------------------------

CANDIDATES=()   # id|status|task_file|folder_path
ORPHANS=()      # id  (riga presente, file assente)
MISSING=()      # id  (nessun file, nessuna riga)

for id in "${REQ_IDS[@]}"; do
    task_file=$(ls "${TASKS_DIR}/${id}-"*.md 2>/dev/null | head -1 || true)
    if [[ -n "$task_file" && -f "$task_file" ]]; then
        status=$(task_status "$task_file")
        folder_field=$(read_field "$task_file" "Folder")
        folder_path=""
        if [[ -n "$folder_field" ]]; then
            folder_path="${PROJECT_ROOT}/${folder_field#./}"
            [[ -d "$folder_path" ]] || folder_path=""
        fi
        CANDIDATES+=("${id}|${status}|${task_file}|${folder_path}")
    elif row_exists "$id"; then
        ORPHANS+=("$id")
    else
        MISSING+=("$id")
    fi
done

# ---- Report ------------------------------------------------------------------

non_done=0
echo "Target on-demand:"

if [[ ${#CANDIDATES[@]} -gt 0 ]]; then
    for c in "${CANDIDATES[@]}"; do
        id="${c%%|*}"; rest="${c#*|}"; st="${rest%%|*}"; rest="${rest#*|}"; tf="${rest%%|*}"; fp="${rest#*|}"
        tag="[Done]"
        if [[ "$st" == "open" ]]; then tag="[NOT Done]"; non_done=$((non_done+1)); fi
        folder_info=""
        if [[ -n "$fp" ]]; then
            folder_info=" + folder $(basename "$fp")"
            surv="$(lw_folder_survivors "$(realpath --relative-to="$PROJECT_ROOT" "$fp")")"
            if [[ -n "$surv" ]]; then
                n=$(printf '%s\n' "$surv" | grep -c .)
                folder_info="${folder_info} [⚠ ${n} ignored/untracked]"
            fi
        fi
        echo "   ${id}  ${tag}  $(basename "$tf")${folder_info}"
    done
fi

for oid in "${ORPHANS[@]:-}"; do
    [[ -n "$oid" ]] && echo "   ${oid}  [orphan row]  (file assente, rimuovo solo la riga)"
done

for mid in "${MISSING[@]:-}"; do
    [[ -n "$mid" ]] && echo "   ${mid}  [missing]  (nessun file, nessuna riga — skip)"
done

echo ""
echo "SUMMARY candidates=${#CANDIDATES[@]} non_done=${non_done} orphans=${#ORPHANS[@]} missing=${#MISSING[@]}"

if [[ ${#CANDIDATES[@]} -eq 0 && ${#ORPHANS[@]} -eq 0 ]]; then
    echo "-> niente da rimuovere"
    exit 0
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

# Riconcilia le righe orfane (file gia' assente: rimuovi solo la riga dangling).
if [[ ${#ORPHANS[@]} -gt 0 ]]; then
    for id in "${ORPHANS[@]}"; do
        echo ""
        echo "--- reconcile orphan ${id} ---"
        remove_task_from_tasksmd "$id"
        git -C "$PROJECT_ROOT" commit -m "$(printf 'chore(tasks): reconcile orphan row %s (file already absent)' "$id")"
        echo "-> riga orfana rimossa + commit: ${id}"
    done
fi

for c in "${CANDIDATES[@]}"; do
    id="${c%%|*}"; rest="${c#*|}"; st="${rest%%|*}"; rest="${rest#*|}"; tf="${rest%%|*}"; fp="${rest#*|}"
    slug=$(basename "$tf" .md); slug="${slug#${id}-}"

    echo ""
    echo "--- purge ${id} (${st}) ---"

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
    maybe_drop_current_link "$(basename "$tf")"

    # Remove folder if present — solo se ancora su disco. Task che condividono la
    # stessa Folder si portano dietro lo STESSO $fp (risolto in blocco a monte):
    # la prima la rimuove, la seconda la trova gia' sparita → skip pulito (evita il
    # doppio `git rm`, exit 128 sotto `set -e`, che abortirebbe il run a meta').
    folder_line=""
    if [[ -n "$fp" && -e "$fp" ]]; then
        rel_fp="$(realpath --relative-to="$PROJECT_ROOT" "$fp")"
        git -C "$PROJECT_ROOT" rm -rf "$rel_fp"
        echo "-> rimossa folder (tracked): ${rel_fp}/"
        folder_line="  - ${rel_fp}/"
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

    # Commit (subject parlante su stato: Done vs forced)
    if [[ "$st" == "done" ]]; then
        subject=$(printf 'chore(tasks): purge %s (%s) — on-demand' "$id" "$slug")
        status_label="Done"
    else
        subject=$(printf 'chore(tasks): purge %s (%s) — on-demand (NOT Done, forced)' "$id" "$slug")
        status_label="NOT Done"
    fi

    msg="${subject}

Purged (restore: git checkout <this-commit>~1 -- <path>):
  - ${rel_tf}"
    [[ -n "$folder_line" ]] && msg="${msg}
${folder_line}"
    msg="${msg}
Status at purge: ${status_label}"

    git -C "$PROJECT_ROOT" commit -m "$msg"
    echo "-> commit: ${subject}"
done

echo ""
echo "-> completato: ${#CANDIDATES[@]} task purgate, ${#ORPHANS[@]} righe orfane riconciliate"
