#!/bin/bash

# =============================================================================
# promote-wip.sh - Porta una task a 🟡 (lavoro iniziato), commit dedicato
# Usage: promote-wip.sh <task-id>
# Env:   PROJECT_ROOT (default: $PWD)
#
# Gemello di promote-ready.sh, con due differenze deliberate.
#
# PROMUOVE DA 🔵 E DA 🟢, da nient'altro. Una task ✔️ o 🔒 non si riapre per un
# errore di battitura nell'invocazione: da quegli stati lo script dichiara il
# no-op ed esce 0. Il no-op e' DICHIARATO e non muto (a differenza di
# promote-ready) perche' run-task apre annunciando cosa fara', e "non ho
# promosso" e' parte di quell'annuncio.
#
# COMMITTA DA SE'. Il 🟡 nasce qui perche' start-task.sh e' precluso in detached
# (guardia hard su $LOOM_TASK), e in detached tasks.md e' un file condiviso che
# ogni sessione tocca: una promozione lasciata non committata viaggerebbe sul
# commit della prima sessione che passa — contenuto giusto, attribuzione
# sbagliata, `git log` per task che non torna. La pathspec e' esattamente due
# file noti allo script, quindi lo stage selettivo del detached e' rispettato
# senza che il chiamante debba passare niente.
#
# Nessun lock e nessun retry sulle scritture concorrenti di tasks.md: la
# finestra fra write e commit e' di circa un secondo, e la collisione fra N
# sessioni e' un rischio accettato per scelta. Se un giorno si materializza,
# serve una decisione nuova (flock o retry con rilettura), non un fix silenzioso
# appiccicato qui.
#
# Exit: 0 = promossa, oppure no-op dichiarato · 1 = commit o push falliti
# =============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --docs-root) LOOM_DOCS_ROOT="$2"; shift 2 ;;
        *) break ;;
    esac
done

TASK_ID="${1:?Usage: promote-wip.sh <task-id>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"

PROJECT_ROOT="$(lw_find_project_root)"
DOCS_ROOT="$(lw_docs_root)"
TASKS_DIR="${PROJECT_ROOT}/${DOCS_ROOT}/tasks"
TASKS_FILE="${PROJECT_ROOT}/${DOCS_ROOT}/tasks.md"

if [[ ! -f "$TASKS_FILE" ]]; then
    echo "WARN: ${TASKS_FILE} assente — Prog NON aggiornata" >&2
    exit 0
fi

# Colonna Prog localizzata dall'HEADER, mai per posizione: un indice cablato
# smette di matchare al primo cambio di forma della tabella e produce un no-op
# muto che nessuno vede finche' non confronta tasks.md con la realta'.
CURRENT=$(awk -v id="$TASK_ID" -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    prog == 0 && /^[ \t]*\|/ && trim($2) == "ID" {
        for (i = 2; i <= NF; i++) if (trim($i) == "Prog") prog = i
        next
    }
    prog > 0 && /^[ \t]*\|/ && trim($2) == id { print trim($prog); exit }
' "$TASKS_FILE")

if [[ -z "$CURRENT" ]]; then
    echo "WARN: nessuna riga ${TASK_ID} sotto un header con colonna Prog in ${TASKS_FILE} — Prog NON aggiornata" >&2
    exit 0
fi

if [[ "$CURRENT" == "🟡" ]]; then
    echo "-> ${TASK_ID} gia' 🟡, nessuna promozione"
    exit 0
fi

if [[ "$CURRENT" != "🔵" && "$CURRENT" != "🟢" ]]; then
    echo "-> ${TASK_ID} e' ${CURRENT}: nessuna promozione (si promuove solo da 🔵 o 🟢)"
    exit 0
fi

TMP_TASKS=$(mktemp)
if awk -v id="$TASK_ID" -F'|' -v OFS='|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    prog == 0 && /^[ \t]*\|/ && trim($2) == "ID" {
        for (i = 2; i <= NF; i++) if (trim($i) == "Prog") prog = i
        print; next
    }
    prog > 0 && /^[ \t]*\|/ && trim($2) == id {
        $prog = " 🟡 "; hit = 1; print; next
    }
    { print }
    END { exit(hit ? 0 : 1) }
' "$TASKS_FILE" > "$TMP_TASKS"; then
    mv "$TMP_TASKS" "$TASKS_FILE"
    echo "-> tasks.md aggiornato: ${TASK_ID} ${CURRENT} → 🟡"
else
    rm -f "$TMP_TASKS"
    echo "WARN: riga ${TASK_ID} sparita fra lettura e scrittura — Prog NON aggiornata" >&2
    exit 0
fi

# Il prefisso 🟢 e' opzionale: preflight-task puo' aver gia' promosso il nodo, e
# senza prevederlo la sostituzione non aggancerebbe — il verde resterebbe sul
# grafo a task avviata, senza che nessun errore lo segnali.
perl -i -pe "s/→ 🟢?${TASK_ID}(?![0-9])/→ 🟡${TASK_ID}/ if /^Lane/" "$TASKS_FILE"

TASK_FILE=$(find "$TASKS_DIR" -maxdepth 1 -name "${TASK_ID}-*.md" 2>/dev/null | head -1)
if [[ -n "$TASK_FILE" && -f "$TASK_FILE" ]]; then
    sed -i '0,/^- \*\*Progress\*\*:/s/^\(- \*\*Progress\*\*:\).*/\1 🟡 In Progress/' "$TASK_FILE"
    echo "-> Task file aggiornato: Progress 🟡 In Progress"
fi

COMMIT_PATHS=("${DOCS_ROOT}/tasks.md")
[[ -n "$TASK_FILE" && -f "$TASK_FILE" ]] && COMMIT_PATHS+=("${TASK_FILE#"${PROJECT_ROOT}/"}")

lw_git_add_n_commit "run(${TASK_ID}): 🟡 in lavorazione" "${COMMIT_PATHS[@]}"
case $? in
    0) echo "-> commit promozione: $(lw_current_sha)" ;;
    2) echo "-> nessuna modifica da committare"; exit 0 ;;
    *) echo "ERROR: commit della promozione fallito" >&2; exit 1 ;;
esac

if ! lw_git_push "$(lw_current_branch)"; then
    echo "ERROR: push fallito" >&2
    exit 1
fi
