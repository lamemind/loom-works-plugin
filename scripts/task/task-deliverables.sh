#!/bin/bash

# =============================================================================
# task-deliverables.sh - I DLV di un task file come oggetti indirizzabili
#
# Usage: task-deliverables.sh [--docs-root D] <task-id> [--scope <spec>]
#        task-deliverables.sh [--docs-root D] <task-id> --check <n>
# Env:   PROJECT_ROOT (default: $PWD)
#
# Due verbi sullo stesso oggetto, un parser solo: risolvere il perimetro e
# spuntare una voce contano i DLV nello stesso identico modo, e due copie del
# conteggio divergerebbero al primo task file con una forma inattesa.
#
# NUMERAZIONE — posizionale 1-based sulle sole checkbox a COLONNA ZERO dentro
# `## Deliverables Checklist`. Le righe indentate sono prosa di una voce, non
# voci: DLV4 di T125 porta sei sotto-bullet, contarli sposterebbe di sei la
# numerazione di tutto cio' che segue. La posizione non e' scritta da nessuna
# parte nel file — si conta, e chi conta deve contare uguale.
#
# PERIMETRO — spec "UI di stampante": `1,2,6` (lista), `3-8` (range),
# combinabili (`1,3-5,9`). Normalizzato crescente e deduplicato: l'ordine di
# esecuzione e' quello del file, non quello in cui l'utente ha battuto i numeri.
# Nessuna spec = tutti i DLV ancora aperti.
#
# ERRORE SECCO, mai degradazione — un perimetro che non si risolve ferma la
# skill invece di eseguire "quello che si e' capito": un run-task che lavora su
# un insieme diverso da quello dichiarato in apertura e' indistinguibile a
# valle da uno corretto.
#   - indice fuori range          -> exit 1
#   - DLV gia' [x] nel perimetro  -> exit 1 (non si ri-esegue MAI cio' che e'
#     fatto; per rifarlo davvero si toglie la spunta a mano, che e' un gesto
#     deliberato e visibile nel diff)
#   - perimetro vuoto             -> exit 1 (niente da eseguire non e' un
#     successo silenzioso)
#
# Output (modo perimetro), il testo SEMPRE ultimo campo perche' puo' contenere `|`:
#   TASK=T125
#   TASK_FILE=/abs/path/T125-slug.md
#   SCOPE_SPEC=3,5-6
#   DLV|1|done|out|**Referto sul regime attuale** — ...
#   DLV|3|open|in|**Modello del perimetro** — ...
#   SCOPE_RESOLVED=3,5,6
#   SCOPE_COUNT=3
#
# Exit: 0 = ok · 1 = perimetro/sezione non risolvibili · 2 = task non risolvibile
# =============================================================================

SCOPE_SPEC=""
CHECK_N=""
TASK_ID_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --docs-root) LOOM_DOCS_ROOT="$2"; shift 2 ;;
        --scope) SCOPE_SPEC="$2"; shift 2 ;;
        --check) CHECK_N="$2"; shift 2 ;;
        -*) echo "ERROR: opzione sconosciuta: $1" >&2; exit 1 ;;
        *) TASK_ID_ARG="$1"; shift ;;
    esac
done

if [[ -n "$SCOPE_SPEC" && -n "$CHECK_N" ]]; then
    echo "ERROR: --scope e --check sono modi diversi, non si combinano" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"

RESOLVED="$(lw_resolve_task "$TASK_ID_ARG")" || exit 2
eval "$RESOLVED"

# --- Parsing: una riga per DLV top-level, `lineno|state|text` -----------------
mapfile -t RAW < <(awk '
    /^## / {
        insec = ($0 ~ /^## Deliverables Checklist/)
        next
    }
    insec && /^- \[[ xX]\]/ {
        state = (substr($0, 4, 1) == " ") ? "open" : "done"
        text = substr($0, 7)
        sub(/^[ \t]+/, "", text)
        printf "%d|%s|%s\n", NR, state, text
    }
' "$TASK_FILE")

if [[ ${#RAW[@]} -eq 0 ]]; then
    echo "ERROR: nessun deliverable in '## Deliverables Checklist' di ${TASK_FILE}" >&2
    echo "       Attese righe '- [ ] ...' a colonna zero sotto quell'header." >&2
    exit 1
fi

TOTAL=${#RAW[@]}

dlv_field() {  # <indice 1-based> <1=lineno|2=state|3=text>
    local i="$1" f="$2" row="${RAW[$(($1 - 1))]}"
    case "$f" in
        1) printf '%s' "${row%%|*}" ;;
        2) row="${row#*|}"; printf '%s' "${row%%|*}" ;;
        3) row="${row#*|}"; printf '%s' "${row#*|}" ;;
    esac
}

# --- Modo --check: spunta una voce -------------------------------------------
if [[ -n "$CHECK_N" ]]; then
    if [[ ! "$CHECK_N" =~ ^[0-9]+$ ]] || (( CHECK_N < 1 || CHECK_N > TOTAL )); then
        echo "ERROR: --check ${CHECK_N} fuori range: ${TASK_ID} ha ${TOTAL} deliverable (1-${TOTAL})" >&2
        exit 1
    fi
    if [[ "$(dlv_field "$CHECK_N" 2)" == "done" ]]; then
        echo "-> DLV${CHECK_N} gia' spuntato, nessuna modifica"
        exit 0
    fi
    # Sostituzione ancorata al NUMERO DI RIGA, mai al testo: due DLV che iniziano
    # con le stesse parole sono normali in un task file, e un sed sul pattern
    # spunterebbe il primo dei due senza che nulla lo segnali.
    LINENO_DLV="$(dlv_field "$CHECK_N" 1)"
    sed -i "${LINENO_DLV}s/^- \[ \]/- [x]/" "$TASK_FILE"
    echo "-> DLV${CHECK_N} spuntato: $(dlv_field "$CHECK_N" 3)"
    exit 0
fi

# --- Modo perimetro: risoluzione e validazione --------------------------------
declare -A IN_SCOPE=()
SCOPE_LIST=()

if [[ -n "$SCOPE_SPEC" ]]; then
    NORM="${SCOPE_SPEC// /}"
    if [[ ! "$NORM" =~ ^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$ ]]; then
        echo "ERROR: perimetro malformato: '${SCOPE_SPEC}'" >&2
        echo "       Attesa una lista di indici e range: 1,2,6 · 3-8 · 1,3-5,9" >&2
        exit 1
    fi
    IFS=',' read -ra PARTS <<< "$NORM"
    for part in "${PARTS[@]}"; do
        if [[ "$part" == *-* ]]; then
            from="${part%%-*}"; to="${part##*-}"
            if (( from > to )); then
                echo "ERROR: range invertito nel perimetro: '${part}'" >&2
                exit 1
            fi
        else
            from="$part"; to="$part"
        fi
        for (( n = from; n <= to; n++ )); do
            if (( n < 1 || n > TOTAL )); then
                echo "ERROR: DLV${n} fuori range: ${TASK_ID} ha ${TOTAL} deliverable (1-${TOTAL})" >&2
                exit 1
            fi
            IN_SCOPE["$n"]=1
        done
    done
    for (( n = 1; n <= TOTAL; n++ )); do
        [[ -n "${IN_SCOPE[$n]:-}" ]] || continue
        if [[ "$(dlv_field "$n" 2)" == "done" ]]; then
            echo "ERROR: DLV${n} e' gia' [x] e il perimetro lo include: $(dlv_field "$n" 3)" >&2
            echo "       Un deliverable fatto non si ri-esegue. Per rifarlo davvero, togli la spunta nel task file e rilancia." >&2
            exit 1
        fi
        SCOPE_LIST+=("$n")
    done
else
    for (( n = 1; n <= TOTAL; n++ )); do
        [[ "$(dlv_field "$n" 2)" == "open" ]] || continue
        IN_SCOPE["$n"]=1
        SCOPE_LIST+=("$n")
    done
    if [[ ${#SCOPE_LIST[@]} -eq 0 ]]; then
        echo "ERROR: ${TASK_ID} non ha deliverable aperti — tutti e ${TOTAL} sono gia' [x]" >&2
        echo "       Niente da eseguire. Se la task va riaperta, togli le spunte nel task file." >&2
        exit 1
    fi
fi

echo "TASK=${TASK_ID}"
echo "TASK_FILE=${TASK_FILE}"
echo "SCOPE_SPEC=${SCOPE_SPEC:-(nudo: tutti gli aperti)}"
for (( n = 1; n <= TOTAL; n++ )); do
    membership="out"
    [[ -n "${IN_SCOPE[$n]:-}" ]] && membership="in"
    printf 'DLV|%d|%s|%s|%s\n' "$n" "$(dlv_field "$n" 2)" "$membership" "$(dlv_field "$n" 3)"
done
printf 'SCOPE_RESOLVED=%s\n' "$(IFS=','; echo "${SCOPE_LIST[*]}")"
echo "SCOPE_COUNT=${#SCOPE_LIST[@]}"
