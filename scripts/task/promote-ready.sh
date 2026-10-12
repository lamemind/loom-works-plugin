#!/bin/bash

# =============================================================================
# promote-ready.sh - Porta una task a 🟢 Ready (preflight fatto, zero codice)
# Usage: promote-ready.sh <task-id>
# Env:   PROJECT_ROOT (default: $PWD)
#
# Promuove SOLO da 🔵. Da qualunque altro stato non tocca niente ed esce 0:
# preflight-task e' ri-eseguibile per costruzione, quindi puo' partire su una
# task gia' aperta o gia' chiusa, e riportarla a verde la farebbe sparire dai
# filtri di stato senza che nessuno l'abbia chiesto.
#
# Il confronto legge la cella Prog di tasks.md, non il campo Progress del task
# file: la cella e' cio' che deck, recap-status e reconcile-tasks interrogano,
# mentre il campo del task file e' testo libero e puo' portare prosa (`🟡 85%`).
# =============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --docs-root) LOOM_DOCS_ROOT="$2"; shift 2 ;;
        *) break ;;
    esac
done

TASK_ID="${1:?Usage: promote-ready.sh <task-id>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"

PROJECT_ROOT="$(lw_find_project_root)"
TASKS_DIR="${PROJECT_ROOT}/$(lw_docs_root)/tasks"
TASKS_FILE="${PROJECT_ROOT}/$(lw_docs_root)/tasks.md"

if [[ ! -f "$TASKS_FILE" ]]; then
    echo "WARN: ${TASKS_FILE} assente — Prog NON aggiornata" >&2
    exit 0
fi

# Cella Prog letta dentro la Tasks Overview, colonna dall'header: un riscontro
# mancato e' un WARN, mai un no-op muto (`lw_tasks_md_prog_get` in lib.sh).
CURRENT=$(lw_tasks_md_prog_get "$TASKS_FILE" "$TASK_ID")

if [[ -z "$CURRENT" ]]; then
    echo "WARN: nessuna riga ${TASK_ID} sotto un header con colonna Prog in ${TASKS_FILE} — Prog NON aggiornata" >&2
    exit 0
fi

# Silenzio deliberato fuori dal ramo 🔵: l'output di preflight-task non cambia
# forma a seconda dello stato di partenza, e non promuovere e' il caso normale
# su una task gia' avviata.
if [[ "$CURRENT" != "🔵" ]]; then
    exit 0
fi

if lw_tasks_md_prog_set "$TASKS_FILE" "$TASK_ID" "🟢"; then
    echo "-> tasks.md aggiornato: ${TASK_ID} 🟢"
else
    echo "WARN: riga ${TASK_ID} sparita fra lettura e scrittura — Prog NON aggiornata" >&2
    exit 0
fi

# Grafo lane: il nodo e' senza emoji finche' nessuno lo promuove.
perl -i -pe "s/→ ${TASK_ID}(?![0-9])/→ 🟢${TASK_ID}/ if /^Lane/" "$TASKS_FILE"

TASK_FILE=$(find "$TASKS_DIR" -maxdepth 1 -name "${TASK_ID}-*.md" 2>/dev/null | head -1)
if [[ -n "$TASK_FILE" && -f "$TASK_FILE" ]]; then
    sed -i '0,/^- \*\*Progress\*\*:/s/^\(- \*\*Progress\*\*:\).*/\1 🟢 Ready/' "$TASK_FILE"
    echo "-> Task file aggiornato: Progress 🟢 Ready"
fi
