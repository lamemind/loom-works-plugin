#!/usr/bin/env bash

# =============================================================================
# tldr.sh — gate deterministico e scrittura della riga 3 dei file di reference/
# Usage: tldr.sh gate --file <sorgente.md> --candidati <lista.txt> [--out <path>]
#        tldr.sh set  --file <sorgente.md> --tldr "<testo>"
# =============================================================================
#
# Il TLDR di un file di reference/ e' un artefatto DERIVATO, prodotto dalla skill
# write-tldr in tre stadi: raccoglitore (agent) → gate (questo script) → potatore
# (agent). Qui vive tutto cio' che e' decidibile senza modello.
#
# --- gate ---------------------------------------------------------------------
#
# Ogni candidato etichettato NOME o ERRORE deve comparire LETTERALMENTE nel file
# d'origine. Chi non passa viene scartato prima di arrivare al potatore, che per
# contratto non puo' correggere un nome falso e non ha il file per accorgersene:
# un errore del raccoglitore che superasse il gate diventerebbe incorreggibile.
#
# Formato di una riga: `ETICHETTA | frammento`. Le etichette sono ORIENTAMENTO,
# NOME, ERRORE, SINTOMO, TESI, META. Una riga fuori formato viene scartata. Una riga
# che inizia per `#` e' l'intestazione della lista (il path del file d'origine) e
# attraversa il gate intatta.
#
# Il confronto e' letterale (`grep -F`) e il `--` che chiude le opzioni NON e'
# opzionale: senza, ogni frammento che inizia per trattino (`--tab`, `--drainable`)
# viene letto da grep come una sua opzione e riportato come fabbricazione. Misurato:
# senza il `--` il gate riportava dieci scarti su novanta candidati, di cui sette
# erano artefatti dello strumento.
#
# Un frammento racchiuso in backtick viene provato anche nella forma nuda: la doc
# cita i simboli col backtick, il sorgente li scrive senza.
#
# Il gate copre SOLO NOME ed ERRORE. Un flag inventato dentro un frammento
# etichettato diversamente gli sfugge — e' il limite dichiarato, non un difetto.
#
# --- set ----------------------------------------------------------------------
#
# Scrive la riga 3 nella forma `> **TLDR**: <testo>`, sostituendo quella presente o
# inserendola se assente. La riga 2 deve essere vuota (formato dei file doc): se non
# lo e' il file non ha la forma attesa e lo script si ferma invece di sfondarla.
#
# Il cap in caratteri NON vive qui: e' guardia di build-index.sh, sede unica in
# lib-doc.sh. Questo script stampa la misura e non giudica.
#
# Exit: 0 = fatto (per `gate`: anche con scarti — uno scarto e' un dato, non un
#       fallimento) · 1 = errore d'uso o file che non ha la forma attesa
# =============================================================================

set -uo pipefail

VERB="${1:-}"
shift || true

FILE=""
CANDIDATI=""
OUT=""
TESTO=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --file)      FILE="$2"; shift 2 ;;
        --candidati) CANDIDATI="$2"; shift 2 ;;
        --out)       OUT="$2"; shift 2 ;;
        --tldr)      TESTO="$2"; shift 2 ;;
        *) echo "[tldr] unknown arg: $1" >&2; exit 1 ;;
    esac
done

[[ -n "$FILE" ]] || { echo "[tldr] ERROR: --file obbligatorio" >&2; exit 1; }
[[ -f "$FILE" ]] || { echo "[tldr] ERROR: file non trovato: $FILE" >&2; exit 1; }

# --- gate ---------------------------------------------------------------------

gate() {
    [[ -n "$CANDIDATI" ]] || { echo "[tldr] ERROR: --candidati obbligatorio" >&2; exit 1; }
    [[ -f "$CANDIDATI" ]] || { echo "[tldr] ERROR: lista non trovata: $CANDIDATI" >&2; exit 1; }

    local dest
    dest="$(mktemp)"

    local totale=0 passati=0 scartati=0 malformati=0

    while IFS= read -r riga; do
        [[ -z "${riga//[[:space:]]/}" ]] && continue
        # L'intestazione `# <path>` dice al potatore di quale file sta scegliendo il
        # TLDR: attraversa il gate intatta e non e' un candidato.
        if [[ "$riga" == \#* ]]; then printf '%s\n' "$riga" >> "$dest"; continue; fi
        totale=$((totale+1))

        local etichetta frammento
        etichetta="${riga%%|*}"
        etichetta="${etichetta//[[:space:]]/}"
        frammento="${riga#*|}"
        frammento="${frammento#"${frammento%%[![:space:]]*}"}"
        frammento="${frammento%"${frammento##*[![:space:]]}"}"

        case "$etichetta" in
            ORIENTAMENTO|NOME|ERRORE|SINTOMO|TESI|META) ;;
            *)
                echo "[tldr] MALFORMATO: ${riga}" >&2
                malformati=$((malformati+1))
                continue ;;
        esac

        if [[ "$etichetta" != "NOME" && "$etichetta" != "ERRORE" ]]; then
            printf '%s | %s\n' "$etichetta" "$frammento" >> "$dest"
            passati=$((passati+1))
            continue
        fi

        local nudo="$frammento"
        nudo="${nudo#\`}"
        nudo="${nudo%\`}"

        if grep -qF -- "$frammento" "$FILE" || grep -qF -- "$nudo" "$FILE"; then
            printf '%s | %s\n' "$etichetta" "$frammento" >> "$dest"
            passati=$((passati+1))
        else
            echo "[tldr] SCARTATO ${etichetta}: ${frammento}" >&2
            scartati=$((scartati+1))
        fi
    done < "$CANDIDATI"

    if [[ -n "$OUT" ]]; then
        mv "$dest" "$OUT"
    else
        cat "$dest"
        rm -f "$dest"
    fi

    echo "[tldr] gate ${FILE}: ${totale} candidati, ${passati} passati, ${scartati} scartati, ${malformati} malformati" >&2
}

# --- set ----------------------------------------------------------------------

set_tldr() {
    [[ -n "$TESTO" ]] || { echo "[tldr] ERROR: --tldr obbligatorio" >&2; exit 1; }

    local riga2 riga3
    riga2="$(sed -n '2p' "$FILE")"
    riga3="$(sed -n '3p' "$FILE")"

    if [[ -n "${riga2//[[:space:]]/}" ]]; then
        echo "[tldr] ERROR: riga 2 non vuota, il file non ha la forma attesa: $FILE" >&2
        exit 1
    fi

    # Sostituzione o inserimento. Inserendo si aggiunge anche la riga vuota che
    # separa il TLDR dal corpo, a meno che la riga 3 non fosse gia' vuota.
    local resto=3 separatore=1
    if [[ "$riga3" =~ ^\>\ \*\*TLDR\*\*:\  ]]; then
        resto=4; separatore=0
    elif [[ -z "${riga3//[[:space:]]/}" ]]; then
        resto=4
    fi

    local tmp
    tmp="$(mktemp)"
    {
        sed -n '1,2p' "$FILE"
        printf '> **TLDR**: %s\n' "$TESTO"
        (( separatore )) && printf '\n'
        sed -n "${resto},\$p" "$FILE"
    } > "$tmp"
    mv "$tmp" "$FILE"

    echo "[tldr] set ${FILE}: ${#TESTO} char" >&2
}

case "$VERB" in
    gate) gate ;;
    set)  set_tldr ;;
    *) echo "[tldr] ERROR: verbo sconosciuto: '${VERB}' (gate|set)" >&2; exit 1 ;;
esac
