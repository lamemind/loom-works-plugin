#!/bin/bash

# =============================================================================
# cleanup-done-tasks.sh - Pota task Done oltre soglia giorni
# Usage: cleanup-done-tasks.sh [--docs-root <path>]
#                               [--days N] [--apply] [task-id ...]
#
# Dry-run di default: elenca candidati senza modifiche.
# Con --apply: elimina task file + folder + riga tasks.md, un commit per task.
# La folder resta, e il dry-run lo dice, se un'altra task fuori dall'invocazione
# la dichiara o se il campo Folder non ha la forma .YY-MM-DD-slug.
# Una task con materiale 💎 nella folder (## Materiale) non parte: resta intera,
# le altre partono. Exit: 0 tutte eliminate · 1 errore · 2 gate --ignored-files ·
# 3 almeno una task rifiutata per il materiale 💎.
# Inoltre riconcilia le righe ORFANE (Done in tasks.md ma file gia' assente):
# rimuove la riga, indipendentemente dalla soglia --days. Senza questo, l'ID
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

# Remove a task's Overview row from tasks.md — solo quella, confinata alla
# sezione `## Tasks Overview`. L'Execution Plan e' design scritto a mano e nessuno
# script lo pota: il token della task resta nelle catene del grafo e nelle celle
# Cross Deps finche' qualcuno lo toglie a mano. Un `sed "/\b<id>\b/d"` sul file
# intero cancellerebbe anche la riga Overview di un'altra task il cui titolo
# nomina l'id, lasciandone il task file senza riga.
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

CANDIDATES=()        # "ID|age_days|task_file|rel_folder" (root-relative, vuoto = nessuna folder su disco)
ORPHANS=()           # "ID" — riga Done in tasks.md ma file gia' assente
SKIPPED=()           # "ID|reason"
declare -A FOLDER_STAYS=()   # ID -> perche' la folder resta; assente = parte con la task

for task_id in "${DONE_IDS[@]}"; do
    task_file=$(ls "${TASKS_DIR}/${task_id}-"*.md 2>/dev/null | head -1 || true)
    if [[ -z "$task_file" || ! -f "$task_file" ]]; then
        # Riga Done senza file: residuo da riconciliare. Nessun file da
        # trattenere -> indipendente dalla soglia --days (rimuovi la riga).
        ORPHANS+=("${task_id}")
        continue
    fi

    # Primary: "✔️ Done at YYYY-MM-DD" inline nel task file (sorgente deterministica)
    done_date=""
    progress_line=$(grep -m1 '^- \*\*Progress\*\*:.*Done at' "$task_file" 2>/dev/null || true)
    if [[ -n "$progress_line" ]]; then
        done_date=$(echo "$progress_line" | grep -oP 'Done at \K\d{4}-\d{2}-\d{2}' || true)
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

    # Read folder field — root-relative, like ./.26-06-03-slug
    folder_field=$(read_field "$task_file" "Folder")
    rel_folder=""
    if [[ -n "$folder_field" ]]; then
        # Stessa normalizzazione di lw_folder_declarers: via `./` e un `/` finale.
        rel_folder="${folder_field#./}"; rel_folder="${rel_folder%/}"
        if [[ ! -d "${PROJECT_ROOT}/${rel_folder}" ]]; then
            rel_folder=""
        elif ! lw_folder_shape_ok "$rel_folder"; then
            # `Folder: .` sarebbe la project root: una folder fuori forma non si tocca.
            rel_folder="$folder_field"
            FOLDER_STAYS[$task_id]="non ha la forma .YY-MM-DD-slug"
        fi
    fi

    CANDIDATES+=("${task_id}|${age_days}|${task_file}|${rel_folder}")
done

# ---- Folder condivise con una task che resta ---------------------------------
# Una folder dichiarata anche da una task che resta fuori da questa invocazione
# resta sul disco e in git: parte la task, non il materiale. Resta anche fuori dal
# gate e da --ignored-files, che decidono dei file che una folder in partenza
# lascerebbe: keep metterebbe in git i suoi ignorati, purge la cancellerebbe.
# Una folder condivisa solo fra task che partono qui si toglie con la prima.
if [[ ${#CANDIDATES[@]} -gt 0 ]]; then
    leaving=()
    for c in "${CANDIDATES[@]}"; do rest="${c#*|}"; rest="${rest#*|}"; leaving+=("${rest%%|*}"); done
    declare -A KEEPERS=()   # folder -> task che restano e la dichiarano
    while IFS=$'\t' read -r kfolder kfile; do
        KEEPERS[$kfolder]="${KEEPERS[$kfolder]:+${KEEPERS[$kfolder]}, }${kfile%%-*}"
    done < <(lw_folder_declarers "$TASKS_DIR" "${leaving[@]}")
    for c in "${CANDIDATES[@]}"; do
        id="${c%%|*}"; rf="${c##*|}"
        [[ -n "$rf" && -z "${FOLDER_STAYS[$id]:-}" && -n "${KEEPERS[$rf]:-}" ]] || continue
        FOLDER_STAYS[$id]="condivisa con ${KEEPERS[$rf]}"
    done
fi

# ---- Materiale 💎: la task che lo porta non parte ----------------------------
# Una voce di `## Materiale` con 💎 marca un oggetto da non eliminare. Se l'oggetto
# sta nella folder e la folder partirebbe qui, la task e' rifiutata: task file,
# folder e riga restano, le altre task partono. Una task rifiutata resta, quindi
# tiene in vita la folder anche per le task che la condividono e partono.
# Nessun flag la scavalca: si sblocca spostando l'oggetto o togliendo 💎.
declare -A PROTECTED=()   # id -> oggetti marcati a rischio, separati da ", "
declare -A HELD=()        # folder -> task rifiutate che la dichiarano
if [[ ${#CANDIDATES[@]} -gt 0 ]]; then
    for c in "${CANDIDATES[@]}"; do
        id="${c%%|*}"; rest="${c#*|}"; rest="${rest#*|}"; tf="${rest%%|*}"; rf="${rest#*|}"
        [[ -n "$rf" && -z "${FOLDER_STAYS[$id]:-}" ]] || continue
        marked=""
        while IFS= read -r p; do marked+="${marked:+, }${p}"; done < <(lw_folder_protected "$tf" "$rf")
        [[ -n "$marked" ]] || continue
        PROTECTED[$id]="$marked"
        HELD[$rf]="${HELD[$rf]:+${HELD[$rf]}, }${id}"
    done
    for c in "${CANDIDATES[@]}"; do
        id="${c%%|*}"; rf="${c##*|}"
        [[ -n "$rf" && -z "${PROTECTED[$id]:-}" && -z "${FOLDER_STAYS[$id]:-}" && -n "${HELD[$rf]:-}" ]] || continue
        FOLDER_STAYS[$id]="condivisa con ${HELD[$rf]}"
    done
fi

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
        id="${c%%|*}"; rest="${c#*|}"; age="${rest%%|*}"; rest="${rest#*|}"; tf="${rest%%|*}"; rf="${rest#*|}"
        folder_info=""
        if [[ -n "${PROTECTED[$id]:-}" ]]; then
            folder_info=" · protetta: 💎 ${PROTECTED[$id]}"
        elif [[ -n "${FOLDER_STAYS[$id]:-}" ]]; then
            folder_info=" · folder ${rf} resta (${FOLDER_STAYS[$id]})"
        elif [[ -n "$rf" ]]; then
            folder_info=" + folder ${rf}"
            surv="$(lw_folder_survivors "$rf")"
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
    if [[ ${#PROTECTED[@]} -gt 0 ]]; then
        echo "-> ${#PROTECTED[@]} task protette da materiale 💎 nella folder: con --apply restano intere (exit 3)"
    fi
    echo "-> dry-run: nessuna modifica (aggiungi --apply per eseguire)"
    exit 0
fi

# ---- Apply: delete + commit per task -----------------------------------------

# ---- Gate: task folder con file ignored/untracked ----------------------------
# `git rm -rf` non rimuove i file ignorati/untracked di una folder: sopravvivono
# su disco (il .gitignore che li nascondeva sparisce → "riemergono"). Se il
# chiamante non ha indicato come gestirli, fallisci PRIMA di qualsiasi modifica.
if [[ -z "$IGNORED_MODE" ]]; then
    gate_hit=0
    for c in "${CANDIDATES[@]}"; do
        id="${c%%|*}"; rf="${c##*|}"
        [[ -n "$rf" && -z "${FOLDER_STAYS[$id]:-}" && -z "${PROTECTED[$id]:-}" && -e "${PROJECT_ROOT}/${rf}" ]] || continue
        surv="$(lw_folder_survivors "$rf")"
        [[ -n "$surv" ]] || continue
        if [[ $gate_hit -eq 0 ]]; then
            echo "" >&2
            echo "ERROR: task folder con file che 'git rm' non rimuove (ignored/untracked):" >&2
            gate_hit=1
        fi
        echo "  ${rf}/" >&2
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
    lw_git_add_n_commit "$(printf 'chore(tasks): reconcile orphan row %s (file already absent)' "$id")" "$TASKS_FILE"
    echo "-> riga orfana rimossa + commit: ${id}"
done

for c in "${CANDIDATES[@]}"; do
    id="${c%%|*}"; rest="${c#*|}"; age="${rest%%|*}"; rest="${rest#*|}"; tf="${rest%%|*}"; rf="${rest#*|}"
    slug=$(basename "$tf" .md); slug="${slug#${id}-}"
    stays="${FOLDER_STAYS[$id]:-}"

    if [[ -n "${PROTECTED[$id]:-}" ]]; then
        echo ""
        echo "--- rifiuto ${id} ---"
        echo "-> protetta: 💎 ${PROTECTED[$id]} — task file, folder ${rf}/ e riga restano"
        echo "   per eliminarla: sposta l'oggetto fuori dalla folder, o togli 💎 dalla sua voce di ## Materiale"
        continue
    fi

    echo ""
    echo "--- purge ${id} ---"

    # Done SHA + data per il body del commit: ultimo commit che ha toccato il task file
    tracked_sha=""; done_date=""
    rel_path="${DOCS_ROOT}/tasks/$(basename "$tf")"
    read -r tracked_sha done_date < <(git -C "$PROJECT_ROOT" log -1 --format='%H %cI' -- "$rel_path" 2>/dev/null) || true

    # keep: PRIMA di qualsiasi git rm, snapshotta in un commit dedicato i file che
    # sopravviverebbero al purge (ignored/untracked). Cosi' restano recuperabili da
    # quel commit; poi il purge sotto li elimina dal disco insieme al resto (ora
    # tracciati). A prescindere dalla scelta, i file NON restano in locale — keep
    # li conserva solo in git history, purge li perde. Una folder che resta non
    # parte, e non ha niente da snapshottare.
    if [[ "$IGNORED_MODE" == "keep" && -n "$rf" && -z "$stays" && -e "${PROJECT_ROOT}/${rf}" ]]; then
        if [[ -n "$(lw_folder_survivors "$rf")" ]]; then
            git -C "$PROJECT_ROOT" add -f -- "$rf"
            git -C "$PROJECT_ROOT" commit -m "$(printf 'chore(tasks): keep ignored files of %s before purge (%s)' "$id" "$rf")" -- "$rf"
            echo "-> keep: snapshot file ignored/untracked in commit dedicato (${rf}/)"
        fi
    fi

    # Remove task file
    rel_tf="${DOCS_ROOT}/tasks/$(basename "$tf")"
    git -C "$PROJECT_ROOT" rm -f "$rel_tf"
    echo "-> rimosso: ${rel_tf}"

    # Remove folder if present — solo se parte con la task e se e' ancora su disco.
    # Task che condividono la stessa Folder partendo insieme si portano dietro lo
    # STESSO path: la prima la rimuove, la seconda la trova gia' sparita.
    # Una folder senza file tracciati (vuota, o con soli non tracciati sotto
    # `purge`) non va a `git rm`: lw_folder_purge lo sa. I tracciati si leggono
    # prima, perche' decidono se la folder entra nel commit e nel suo body.
    folder_info_body=""
    if [[ -n "$stays" ]]; then
        echo "-> folder resta: ${rf}/ (${stays})"
        folder_info_body="Folder kept: ${rf}/ (${stays})
"
    elif [[ -n "$rf" && -e "${PROJECT_ROOT}/${rf}" ]]; then
        tracked="$(git -C "$PROJECT_ROOT" ls-files --cached -- "$rf")"
        rc=0; lw_folder_purge "$rf" || rc=$?
        case $rc in
            0) echo "-> rimossa folder: ${rf}/" ;;
            5) echo "-> ⚠ folder rimasta sul disco: ${rf}/ — contiene file che git non elenca (es. una .git): guardala e toglila a mano" ;;
            *) echo "ERROR: rimozione della folder fallita: ${rf}/" >&2; exit 1 ;;
        esac
        [[ -n "$tracked" ]] && folder_info_body="  - ${rf}/
"
    elif [[ -n "$rf" ]]; then
        echo "-> folder gia' rimossa da una task che la condivide: ${rf}/"
    fi

    # Remove the Overview row from tasks.md
    remove_task_from_tasksmd "$id"
    echo "-> rimossa riga tasks.md: ${id}"

    # Commit
    COMMIT_BODY="Purged (restore: git checkout <this-commit>~1 -- <path>):
  - ${rel_tf}
${folder_info_body}Done commit: ${tracked_sha:-unknown} (${done_date:-unknown})"

    # Pathspec: task file, folder se rimossa, tasks.md. Un `git rm` stagia la
    # cancellazione, ma il commit la prende dal perimetro, non dall'indice intero.
    purge_paths=("$rel_tf" "$TASKS_FILE")
    [[ -n "$folder_info_body" && -z "$stays" ]] && purge_paths+=("$rf")
    lw_git_add_n_commit "$(printf 'chore(tasks): purge done %s (%s) — Done >%sdays\n\n%s' "$id" "$slug" "$age" "$COMMIT_BODY")" "${purge_paths[@]}"
    echo "-> commit: chore(tasks): purge done ${id}"
done

refused=""
for c in "${CANDIDATES[@]}"; do
    id="${c%%|*}"
    [[ -n "${PROTECTED[$id]:-}" ]] && refused+="${refused:+, }${id}"
done
echo ""
echo "-> completato: $(( ${#CANDIDATES[@]} - ${#PROTECTED[@]} )) task purgate, ${#ORPHANS[@]} righe orfane riconciliate"
if [[ -n "$refused" ]]; then
    echo "-> rifiutate: ${refused} — materiale 💎 nella folder"
    exit 3
fi
