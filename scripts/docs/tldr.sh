#!/usr/bin/env bash

# =============================================================================
# tldr.sh — i tre passi deterministici del produttore di TLDR
# Usage: tldr.sh prepara --file <sorgente.md> --out <copia.md>
#        tldr.sh gate    --file <copia.md> --candidati <lista.txt> [--out <path>]
#        tldr.sh componi --candidati <filtrata.txt> --voci <voci.txt> [--out <path>]
#        tldr.sh set     --file <sorgente.md> (--tldr "<testo>" | --tldr-file <path>)
# =============================================================================
#
# Il TLDR di un file di reference/ e' un artefatto DERIVATO, prodotto dalla skill
# write-tldr alternando agent e passi deterministici:
#
#   prepara → raccoglitore (agent) → gate → potatore (agent) → componi → set
#
# Qui vive tutto cio' che e' decidibile senza modello. Il principio che tiene
# insieme i quattro verbi: un agent puo' sbagliare solo dove un controllo a valle
# se ne accorge. Il raccoglitore puo' fabbricare un nome (lo prende `gate`), il
# potatore puo' riformulare o sforare l'ordine (lo prende `componi`).
#
# --- prepara ------------------------------------------------------------------
#
# Copia il file SENZA la riga 3, quando la riga 3 e' un TLDR. Il raccoglitore
# legge la copia, e il gate misura contro la copia.
#
# Senza questo passo il TLDR si auto-perpetua: il raccoglitore legge il file
# intero, ricicla i frammenti del TLDR precedente, e il gate li conferma perche'
# nel file ci sono davvero — alla riga 3. Misurato su doc-system-references.md:
# tre voci su sette del TLDR nuovo venivano dal TLDR vecchio e da nessun'altra
# riga del file, comprese le tesi che il produttore esiste per eliminare.
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
# --- componi ------------------------------------------------------------------
#
# Il gate d'USCITA: prende le voci rese dal potatore e ne fa la riga, applicando
# le tre regole che il potatore ha nel prompt e puo' comunque violare.
#
#   1. VERBATIM — ogni voce deve comparire identica nella lista filtrata. Il
#      potatore puo' solo copiare o scartare: una voce che non si ritrova e' una
#      riformulazione, e viene scartata. Cosi' l'etichetta di ogni voce si
#      recupera dalla lista invece di essere richiesta al potatore, che non la
#      rende.
#   2. ORDINE — un solo ORIENTAMENTO in testa, poi ERRORE, poi SINTOMO, poi NOME.
#      TESI e META non entrano mai. Gli ORIENTAMENTO in eccesso escono.
#   3. CAP — si taglia dalla coda dell'ordine finche' la riga rientra. La coda e'
#      la parte meno discriminante per costruzione, quindi il taglio non ha
#      bisogno di giudizio. Il cap viene da lib-doc.sh, sede unica: nessun numero
#      di caratteri vive nei prompt dei due agent.
#
# Quando la sola prima voce sfonda il cap la riga si scrive comunque: troncarla a
# meta' parola produrrebbe un'ancora rotta, e build-index.sh la segnala gia'.
#
# --- set ----------------------------------------------------------------------
#
# Scrive la riga 3 nella forma `> **TLDR**: <testo>`, sostituendo quella presente o
# inserendola se assente. La riga 2 deve essere vuota (formato dei file doc): se non
# lo e' il file non ha la forma attesa e lo script si ferma invece di sfondarla.
#
# `--tldr-file` e' la forma da preferire, e `componi --out` scrive proprio quel
# file: un TLDR di un file tecnico e' pieno di backtick, e passarlo come argomento
# shell lo espone a un errore di quoting che scrive sul disco una riga corrotta
# senza che nulla protesti. Misurato: un `--tldr` scritto a mano ha prodotto
# `` `refresh.sh" `` al posto di `` `refresh.sh` ``.
#
# Il cap in caratteri NON e' una guardia di questo verbo: `set` stampa la misura e
# non giudica. Chi taglia e' `componi`, chi blocca e' build-index.sh.
#
# Exit: 0 = fatto (per `gate` e `componi`: anche con scarti — uno scarto e' un
#       dato, non un fallimento) · 1 = errore d'uso o file che non ha la forma attesa
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-doc.sh
source "${SCRIPT_DIR}/lib-doc.sh"

VERB="${1:-}"
shift || true

FILE=""
CANDIDATI=""
VOCI=""
OUT=""
TESTO=""
TESTO_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --file)       FILE="$2"; shift 2 ;;
        --candidati)  CANDIDATI="$2"; shift 2 ;;
        --voci)       VOCI="$2"; shift 2 ;;
        --out)        OUT="$2"; shift 2 ;;
        --tldr)       TESTO="$2"; shift 2 ;;
        --tldr-file)  TESTO_FILE="$2"; shift 2 ;;
        *) echo "[tldr] unknown arg: $1" >&2; exit 1 ;;
    esac
done

# `componi` non tocca il file sorgente: lavora sulle due liste e basta.
if [[ "$VERB" != "componi" ]]; then
    [[ -n "$FILE" ]] || { echo "[tldr] ERROR: --file obbligatorio" >&2; exit 1; }
    [[ -f "$FILE" ]] || { echo "[tldr] ERROR: file non trovato: $FILE" >&2; exit 1; }
fi

# --- prepara ------------------------------------------------------------------

prepara() {
    [[ -n "$OUT" ]] || { echo "[tldr] ERROR: --out obbligatorio" >&2; exit 1; }

    local riga3 amputata=0
    riga3="$(sed -n '3p' "$FILE")"

    if [[ "$riga3" =~ ^\>\ \*\*TLDR\*\*:\  ]]; then
        # La riga 4 e' la vuota che separa il TLDR dal corpo: se la togliessimo
        # insieme alla 3 il corpo scalerebbe di due righe invece che di una, e i
        # numeri di riga di un eventuale referto non tornerebbero piu'.
        { sed -n '1,2p' "$FILE"; sed -n '4,$p' "$FILE"; } > "$OUT"
        amputata=1
    else
        cp "$FILE" "$OUT"
    fi

    if (( amputata )); then
        echo "[tldr] prepara ${FILE}: riga 3 (TLDR) rimossa dalla copia" >&2
    else
        echo "[tldr] prepara ${FILE}: nessun TLDR alla riga 3, copia integrale" >&2
    fi
}

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

# --- componi ------------------------------------------------------------------

componi() {
    [[ -n "$CANDIDATI" ]] || { echo "[tldr] ERROR: --candidati obbligatorio" >&2; exit 1; }
    [[ -f "$CANDIDATI" ]] || { echo "[tldr] ERROR: lista non trovata: $CANDIDATI" >&2; exit 1; }
    [[ -n "$VOCI" ]] || { echo "[tldr] ERROR: --voci obbligatorio" >&2; exit 1; }
    [[ -f "$VOCI" ]] || { echo "[tldr] ERROR: voci non trovate: $VOCI" >&2; exit 1; }

    # Frammento → etichetta, dalla lista che il gate ha gia' filtrato. E' la sola
    # fonte di verita' su cosa il potatore aveva il permesso di scegliere.
    declare -A ETICHETTA_DI
    while IFS= read -r riga; do
        [[ -z "${riga//[[:space:]]/}" ]] && continue
        [[ "$riga" == \#* ]] && continue
        local e f
        e="${riga%%|*}"; e="${e//[[:space:]]/}"
        f="${riga#*|}"
        f="${f#"${f%%[![:space:]]*}"}"
        f="${f%"${f##*[![:space:]]}"}"
        ETICHETTA_DI["$f"]="$e"
    done < "$CANDIDATI"

    local -a orientamento=() errore=() sintomo=() nome=()
    local rese=0 non_verbatim=0 fuori_ordine=0 orient_extra=0

    while IFS= read -r voce; do
        [[ -z "${voce//[[:space:]]/}" ]] && continue
        voce="${voce#"${voce%%[![:space:]]*}"}"
        voce="${voce%"${voce##*[![:space:]]}"}"
        rese=$((rese+1))

        local et="${ETICHETTA_DI[$voce]:-}"
        if [[ -z "$et" ]]; then
            echo "[tldr] NON-VERBATIM: ${voce}" >&2
            non_verbatim=$((non_verbatim+1))
            continue
        fi

        case "$et" in
            ORIENTAMENTO)
                if (( ${#orientamento[@]} )); then
                    echo "[tldr] ORIENTAMENTO-EXTRA: ${voce}" >&2
                    orient_extra=$((orient_extra+1))
                else
                    orientamento+=("$voce")
                fi ;;
            ERRORE)  errore+=("$voce") ;;
            SINTOMO) sintomo+=("$voce") ;;
            NOME)    nome+=("$voce") ;;
            TESI|META)
                echo "[tldr] FUORI-ORDINE ${et}: ${voce}" >&2
                fuori_ordine=$((fuori_ordine+1)) ;;
        esac
    done < "$VOCI"

    local -a ordinate=()
    ordinate+=("${orientamento[@]}")
    ordinate+=("${errore[@]}")
    ordinate+=("${sintomo[@]}")
    ordinate+=("${nome[@]}")

    if (( ${#ordinate[@]} == 0 )); then
        echo "[tldr] ERROR: nessuna voce utilizzabile, la riga non si compone" >&2
        exit 1
    fi

    # Taglio dalla coda: la coda e' la parte meno discriminante per costruzione.
    local riga="" tagliate=0
    while :; do
        riga=""
        local v
        for v in "${ordinate[@]}"; do
            if [[ -z "$riga" ]]; then riga="$v"; else riga="${riga} · ${v}"; fi
        done
        (( ${#riga} <= LW_DOC_TLDR_CAP )) && break
        (( ${#ordinate[@]} <= 1 )) && break
        echo "[tldr] OLTRE-CAP scartata: ${ordinate[-1]}" >&2
        unset 'ordinate[-1]'
        tagliate=$((tagliate+1))
    done

    if [[ -n "$OUT" ]]; then
        printf '%s\n' "$riga" > "$OUT"
    else
        printf '%s\n' "$riga"
    fi

    echo "[tldr] componi: ${rese} voci rese, ${#ordinate[@]} nella riga (${#riga} char, cap ${LW_DOC_TLDR_CAP}); scarti: ${non_verbatim} non-verbatim, ${fuori_ordine} fuori-ordine, ${orient_extra} orientamenti extra, ${tagliate} oltre-cap" >&2
}

# --- set ----------------------------------------------------------------------

set_tldr() {
    if [[ -n "$TESTO_FILE" ]]; then
        [[ -f "$TESTO_FILE" ]] || { echo "[tldr] ERROR: --tldr-file non trovato: $TESTO_FILE" >&2; exit 1; }
        # Una riga sola: il TLDR e' per definizione la riga 3, e un file con due
        # righe e' un errore del chiamante, non un testo da concatenare.
        TESTO="$(sed -n '1p' "$TESTO_FILE")"
        TESTO="${TESTO%"${TESTO##*[![:space:]]}"}"
    fi
    [[ -n "$TESTO" ]] || { echo "[tldr] ERROR: --tldr o --tldr-file obbligatorio" >&2; exit 1; }

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
    prepara) prepara ;;
    gate)    gate ;;
    componi) componi ;;
    set)     set_tldr ;;
    *) echo "[tldr] ERROR: verbo sconosciuto: '${VERB}' (prepara|gate|componi|set)" >&2; exit 1 ;;
esac
