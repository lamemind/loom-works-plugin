#!/bin/bash

# =============================================================================
# clean-tasks.sh - Purge task ON-DEMAND per ID/range (qualsiasi stato, qualsiasi eta')
# Usage: clean-tasks.sh [--docs-root <path>] [--apply] <SPEC>...
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
# La folder resta, e il dry-run lo dice, se un'altra task fuori dall'invocazione
# la dichiara o se il campo Folder non ha la forma .YY-MM-DD-slug.
# Una task con materiale 💎 nella folder (## Materiale) non parte: resta intera,
# le altre partono. Exit: 0 tutte eliminate · 1 errore · 2 gate --ignored-files ·
# 3 almeno una task rifiutata per il materiale 💎.
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
    git -C "$PROJECT_ROOT" add "$TASKS_FILE"
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

CANDIDATES=()   # id|status|task_file|rel_folder (root-relative, vuoto = nessuna folder su disco)
ORPHANS=()      # id  (riga presente, file assente)
MISSING=()      # id  (nessun file, nessuna riga)
declare -A FOLDER_STAYS=()   # id -> perche' la folder resta; assente = parte con la task

for id in "${REQ_IDS[@]}"; do
    task_file=$(ls "${TASKS_DIR}/${id}-"*.md 2>/dev/null | head -1 || true)
    if [[ -n "$task_file" && -f "$task_file" ]]; then
        status=$(task_status "$task_file")
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
                FOLDER_STAYS[$id]="non ha la forma .YY-MM-DD-slug"
            fi
        fi
        CANDIDATES+=("${id}|${status}|${task_file}|${rel_folder}")
    elif row_exists "$id"; then
        ORPHANS+=("$id")
    else
        MISSING+=("$id")
    fi
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

non_done=0
echo "Target on-demand:"

if [[ ${#CANDIDATES[@]} -gt 0 ]]; then
    for c in "${CANDIDATES[@]}"; do
        id="${c%%|*}"; rest="${c#*|}"; st="${rest%%|*}"; rest="${rest#*|}"; tf="${rest%%|*}"; rf="${rest#*|}"
        tag="[Done]"
        if [[ "$st" == "open" ]]; then tag="[NOT Done]"; non_done=$((non_done+1)); fi
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
echo "SUMMARY candidates=${#CANDIDATES[@]} non_done=${non_done} orphans=${#ORPHANS[@]} missing=${#MISSING[@]} protected=${#PROTECTED[@]}"

if [[ ${#CANDIDATES[@]} -eq 0 && ${#ORPHANS[@]} -eq 0 ]]; then
    echo "-> niente da rimuovere"
    exit 0
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

# Riconcilia le righe orfane (file gia' assente: rimuovi solo la riga dangling).
if [[ ${#ORPHANS[@]} -gt 0 ]]; then
    for id in "${ORPHANS[@]}"; do
        echo ""
        echo "--- reconcile orphan ${id} ---"
        remove_task_from_tasksmd "$id"
        lw_git_add_n_commit "$(printf 'chore(tasks): reconcile orphan row %s (file already absent)' "$id")" "$TASKS_FILE"
        echo "-> riga orfana rimossa + commit: ${id}"
    done
fi

for c in "${CANDIDATES[@]}"; do
    id="${c%%|*}"; rest="${c#*|}"; st="${rest%%|*}"; rest="${rest#*|}"; tf="${rest%%|*}"; rf="${rest#*|}"
    slug=$(basename "$tf" .md); slug="${slug#${id}-}"
    stays="${FOLDER_STAYS[$id]:-}"

    if [[ -n "${PROTECTED[$id]:-}" ]]; then
        echo ""
        echo "--- rifiuto ${id} (${st}) ---"
        echo "-> protetta: 💎 ${PROTECTED[$id]} — task file, folder ${rf}/ e riga restano"
        echo "   per eliminarla: sposta l'oggetto fuori dalla folder, o togli 💎 dalla sua voce di ## Materiale"
        continue
    fi

    echo ""
    echo "--- purge ${id} (${st}) ---"

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
    folder_line=""
    if [[ -n "$stays" ]]; then
        echo "-> folder resta: ${rf}/ (${stays})"
    elif [[ -n "$rf" && -e "${PROJECT_ROOT}/${rf}" ]]; then
        tracked="$(git -C "$PROJECT_ROOT" ls-files --cached -- "$rf")"
        rc=0; lw_folder_purge "$rf" || rc=$?
        case $rc in
            0) echo "-> rimossa folder: ${rf}/" ;;
            5) echo "-> ⚠ folder rimasta sul disco: ${rf}/ — contiene file che git non elenca (es. una .git): guardala e toglila a mano" ;;
            *) echo "ERROR: rimozione della folder fallita: ${rf}/" >&2; exit 1 ;;
        esac
        [[ -n "$tracked" ]] && folder_line="  - ${rf}/"
    elif [[ -n "$rf" ]]; then
        echo "-> folder gia' rimossa da una task che la condivide: ${rf}/"
    fi

    # Remove the Overview row from tasks.md
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
    [[ -n "$stays" ]] && msg="${msg}
Folder kept: ${rf}/ (${stays})"

    # Pathspec: task file, folder se rimossa, tasks.md. Un `git rm` stagia la
    # cancellazione, ma il commit la prende dal perimetro, non dall'indice intero.
    purge_paths=("$rel_tf" "$TASKS_FILE")
    [[ -n "$folder_line" ]] && purge_paths+=("$rf")
    lw_git_add_n_commit "$msg" "${purge_paths[@]}"
    echo "-> commit: ${subject}"
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
