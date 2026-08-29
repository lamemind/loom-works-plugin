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
# OGNI candidato deve comparire LETTERALMENTE nel file d'origine. Chi non passa
# viene scartato prima di arrivare al potatore, che per contratto non puo'
# correggere un nome falso e non ha il file per accorgersene: un errore del
# raccoglitore che superasse il gate diventerebbe incorreggibile.
#
# Il vocabolario e' NOME, ERRORE, SEZIONE — tre etichette che sono tutte
# estrazione letterale, e per questo il gate non ha piu' eccezioni. Il regime
# precedente aveva anche AREA e SINTOMO, frammenti di prosa scritti dall'agent, e
# il gate era costretto a lasciarli passare senza verifica perche' nel file non
# c'erano. Da li' entravano parole che il corpo di nessun file conteneva:
# misurato sull'INDEX, `sorella`, `reclamato` e `topologia` comparivano nella riga
# 3 di task-methodology.md e in nessun'altra riga dei 55 file — chi le cercava non
# trovava nemmeno il file che gliele aveva promesse.
#
# Formato di una riga: `ETICHETTA | frammento | domanda`. La domanda e' il
# problema con cui uno arriva a quel candidato, `-` quando il raccoglitore non ha
# saputo formularla; il gate non la giudica e la lascia passare intatta, perche'
# a scartare su quella base e' il potatore. Una riga fuori formato viene scartata;
# una che inizia per `#` e' l'intestazione della lista — il path del file
# d'origine — e attraversa il gate intatta.
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
#   2. VOCABOLARIO — entrano NOME, ERRORE, SEZIONE. Nient'altro.
#   3. CAP — allocazione in due livelli, sotto. Il cap viene da lib-doc.sh, sede
#      unica: nessun numero di caratteri vive nei prompt dei due agent.
#
# L'ALLOCAZIONE, in due livelli.
#
# Livello 1 — NOME ed ERRORE si dividono il cap con un water-filling max-min
# fair: quota uguale a testa, si serve per prima la categoria che domanda meno,
# quello che avanza dalla sua quota si redistribuisce in parti uguali sulle
# altre, e si ripete. Termina in al piu' N passate ed e' generico su N categorie.
#
# Livello 2 — le SEZIONE prendono SOLO cio' che avanza dal livello 1.
#
# Le tre categorie non sono pari, ed e' il motivo del secondo livello: NOME ed
# ERRORE sono chiavi che qualcuno digita, SEZIONE e' il ripiego per i file che di
# chiavi non ne hanno. Con una quota garantita anche alle sezioni, un file di API
# paghe­rebbe un pezzo di riga per heading che non dicono niente — misurato su
# cc/agent-sdk.md, dove `Identità e natura` e `Rischi residui` valgono da soli
# quanto una decina di simboli. Cosi' invece i due estremi si servono da soli:
# su un file ricco di simboli le sezioni non entrano affatto, su un file di sola
# metodologia (zero NOME, zero ERRORE) il livello 1 non spende nulla e le sezioni
# prendono tutto il cap.
#
# Passata finale — le voci sono atomiche, quindi una categoria puo' restare con
# trenta caratteri in mano e una voce che ne chiede quarantacinque. Il residuo
# complessivo si offre percio' a tutte le voci non ancora prese, la piu' corta per
# prima, finche' nessuna ci sta piu'.
#
# La precedenza sta qui e non nel prompt perche' e' una regola fissa: al potatore
# resta l'unico giudizio che questo script non puo' dare, cioe' quali voci della
# stessa categoria valgono di piu'. Storia delle politiche gia' provate e
# scartate — taglio dalla coda di una resa raggruppata (uccideva tutti i NOME),
# pavimenti per categoria, precedenza di categoria in blocco (riga di soli nomi
# nudi) e testa protetta per categoria di contesto (una cornice come `Identità e
# natura` sopravviveva a dieci nomi veri) — in
# runtime/inbox/T132-produttore-tldr-ordine-merito.md del cappello.
#
# Le superstiti si rendono raggruppate, SEZIONE in testa e NOME in coda: e'
# leggibilita' della riga, non priorita' — la priorita' l'ha gia' consumata
# l'allocazione.
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

# Il canale che consegna l'envelope di un subagent al chiamante puo' neutralizzare
# `<` `>` `&` in entita' HTML. Il nome resta quello giusto, cambia la codifica in
# transito — ma un confronto letterale non lo sa e lo tratterebbe da fabbricazione,
# che e' il verdetto opposto. Misurato sul giro di rigenerazione dei 55 file di
# reference/: 61 ancore perse cosi', concentrate sui nomi che portano un segnaposto
# angolato (`<pid>`, `<slug>`), cioe' le firme di comando e i path di registry.
#
# Il ripristino sta qui e non nel prompt dell'orchestratore perche' li' e' a
# giudizio: tre lotti su otto lo fecero di propria iniziativa, tre no.
#
# Serve a DUE stadi, e ripararne uno solo sposta il difetto invece di chiuderlo:
# il `gate` legge i candidati del raccoglitore, `componi` legge le voci del
# potatore, e sono due envelope distinti che passano per lo stesso canale.
# Misurato su cc/agent-sdk.md con la decodifica nel solo gate: 111 candidati su
# 111 passati, e poi le stesse tre voci bocciate NON-VERBATIM da `componi`.
#
# Due giri, perche' un `&amp;lt;` va decodificato due volte.
_decodifica() {
    local s="$1" _g
    for _g in 1 2; do
        s="${s//&lt;/<}"
        s="${s//&gt;/>}"
        s="${s//&quot;/\"}"
        s="${s//&amp;/&}"
    done
    printf '%s' "$s"
}

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

        local etichetta resto frammento domanda
        etichetta="${riga%%|*}"
        etichetta="${etichetta//[[:space:]]/}"
        resto="${riga#*|}"

        # Tre campi: etichetta, frammento, domanda. Il frammento puo' contenere
        # un `|` (una riga di tabella markdown citata), la domanda no: si taglia
        # sull'ULTIMO separatore, non sul primo. Senza il terzo campo la domanda
        # resta vuota e il potatore la legge come assente, che e' il verdetto
        # giusto — un candidato senza domanda non deve entrare.
        if [[ "$resto" == *"|"* ]]; then
            domanda="${resto##*|}"
            frammento="${resto%|*}"
        else
            domanda=""
            frammento="$resto"
        fi
        frammento="${frammento#"${frammento%%[![:space:]]*}"}"
        frammento="${frammento%"${frammento##*[![:space:]]}"}"
        domanda="${domanda#"${domanda%%[![:space:]]*}"}"
        domanda="${domanda%"${domanda##*[![:space:]]}"}"

        frammento="$(_decodifica "$frammento")"
        [[ -n "$domanda" ]] || domanda="-"

        case "$etichetta" in
            NOME|ERRORE|SEZIONE) ;;
            *)
                echo "[tldr] MALFORMATO: ${riga}" >&2
                malformati=$((malformati+1))
                continue ;;
        esac

        local nudo="$frammento"
        nudo="${nudo#\`}"
        nudo="${nudo%\`}"

        if grep -qF -- "$frammento" "$FILE" || grep -qF -- "$nudo" "$FILE"; then
            printf '%s | %s | %s\n' "$etichetta" "$frammento" "$domanda" >> "$dest"
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

# Chiave di confronto fra una voce resa e un candidato: il testo senza backtick
# e senza spazi ridondanti. Serve a distinguere due casi che l'uguaglianza
# secca confonde — il potatore che RISCRIVE (vietato, esce) e il potatore che
# RI-FORMATTA (aggiunge o toglie i backtick di un nome, innocuo). Misurato sul
# giro dei 55 file: su cc/agent-sdk.md il raccoglitore rese i NOME senza
# backtick, il potatore glieli rimise, e 44 voci su 59 uscirono come
# NON-VERBATIM — la riga finale resto' senza una sola ancora cercabile.
# Maiuscole e punteggiatura restano dentro la chiave: cambiarle e' riscrivere.
_chiave() {
    local s="$1"
    s="${s//\`/}"
    s="${s//$'\t'/ }"
    while [[ "$s" == *"  "* ]]; do s="${s//  / }"; done
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# Quanti caratteri chiede una categoria per rendere TUTTE le sue voci: e' la
# domanda su cui il water-filling decide chi servire per primo. Legge l'array
# `scelte` del chiamante (scoping dinamico di bash), che qui e' sempre componi.
_domanda() {
    local d=0 j
    for j in $1; do d=$(( d + ${#scelte[$j]} + 3 )); done
    printf '%s' "$d"
}

componi() {
    [[ -n "$CANDIDATI" ]] || { echo "[tldr] ERROR: --candidati obbligatorio" >&2; exit 1; }
    [[ -f "$CANDIDATI" ]] || { echo "[tldr] ERROR: lista non trovata: $CANDIDATI" >&2; exit 1; }
    [[ -n "$VOCI" ]] || { echo "[tldr] ERROR: --voci obbligatorio" >&2; exit 1; }
    [[ -f "$VOCI" ]] || { echo "[tldr] ERROR: voci non trovate: $VOCI" >&2; exit 1; }

    # Frammento → etichetta, dalla lista che il gate ha gia' filtrato. E' la sola
    # fonte di verita' su cosa il potatore aveva il permesso di scegliere.
    declare -A ETICHETTA_DI CANONICA_DI
    while IFS= read -r riga; do
        [[ -z "${riga//[[:space:]]/}" ]] && continue
        [[ "$riga" == \#* ]] && continue
        local e r f k
        e="${riga%%|*}"; e="${e//[[:space:]]/}"
        r="${riga#*|}"
        # Terzo campo (la domanda) tagliato via sull'ultimo separatore: qui serve
        # solo la corrispondenza frammento → etichetta.
        if [[ "$r" == *"|"* ]]; then f="${r%|*}"; else f="$r"; fi
        f="${f#"${f%%[![:space:]]*}"}"
        f="${f%"${f##*[![:space:]]}"}"
        ETICHETTA_DI["$f"]="$e"
        k="$(_chiave "$f")"
        [[ -n "$k" ]] && CANONICA_DI["$k"]="$f"
    done < "$CANDIDATI"

    # Le voci si raccolgono nell'ordine in cui il potatore le ha rese: dentro
    # una categoria quell'ordine e' la sua decisione su cosa sopravvive.
    local -a scelte=() etichette=()
    local rese=0 non_verbatim=0 fuori_vocabolario=0

    while IFS= read -r voce; do
        [[ -z "${voce//[[:space:]]/}" ]] && continue
        voce="${voce#"${voce%%[![:space:]]*}"}"
        voce="${voce%"${voce##*[![:space:]]}"}"
        # Stessa codifica in transito che il gate ripara sui candidati: la lista
        # filtrata porta gia' la forma decodificata, la voce del potatore no.
        voce="$(_decodifica "$voce")"
        rese=$((rese+1))

        local et="${ETICHETTA_DI[$voce]:-}"
        if [[ -z "$et" ]]; then
            # Prima di bocciare, riprova sulla chiave normalizzata: se la voce
            # differisce dal candidato solo per i backtick, il potatore non ha
            # riscritto nulla, ha ri-formattato. Si riprende la forma della lista
            # filtrata — quella verificata contro il file — e si tira dritto.
            local kv
            kv="$(_chiave "$voce")"
            if [[ -n "$kv" && -n "${CANONICA_DI[$kv]:-}" ]]; then
                voce="${CANONICA_DI[$kv]}"
                et="${ETICHETTA_DI[$voce]:-}"
            fi
        fi
        if [[ -z "$et" ]]; then
            echo "[tldr] NON-VERBATIM: ${voce}" >&2
            non_verbatim=$((non_verbatim+1))
            continue
        fi

        case "$et" in
            NOME|ERRORE|SEZIONE)
                scelte+=("$voce"); etichette+=("$et") ;;
            *)
                echo "[tldr] FUORI-VOCABOLARIO ${et}: ${voce}" >&2
                fuori_vocabolario=$((fuori_vocabolario+1)) ;;
        esac
    done < "$VOCI"

    if (( ${#scelte[@]} == 0 )); then
        echo "[tldr] ERROR: nessuna voce utilizzabile, la riga non si compone" >&2
        exit 1
    fi

    # Costo di una voce: la sua lunghezza piu' il separatore ` · ` che la lega
    # alla precedente. La prima voce della riga il separatore non ce l'ha, quindi
    # il conto qui sovrastima di tre caratteri: la riga esce appena sotto il cap
    # invece che a filo, ed e' l'errore nella direzione innocua.
    local SEPW=3
    local i j c v riga

    # Indici per categoria, nell'ordine di merito in cui il potatore ha reso.
    local L_NOME="" L_ERRORE="" L_SEZIONE=""
    for (( i=0; i<${#scelte[@]}; i++ )); do
        case "${etichette[$i]}" in
            NOME)    L_NOME+="$i " ;;
            ERRORE)  L_ERRORE+="$i " ;;
            SEZIONE) L_SEZIONE+="$i " ;;
        esac
    done

    local -a ammessi=()
    local -A preso=()
    local usato=0

    # --- livello 1: NOME ed ERRORE, water-filling max-min fair ----------------
    local -a resta=()
    [[ -n "$L_NOME"   ]] && resta+=("NOME")
    [[ -n "$L_ERRORE" ]] && resta+=("ERRORE")

    local -A budget=() spesa=()
    if (( ${#resta[@]} > 0 )); then
        for c in "${resta[@]}"; do
            budget[$c]=$(( LW_DOC_TLDR_CAP / ${#resta[@]} ))
            spesa[$c]=0
        done
        while (( ${#resta[@]} > 0 )); do
            # Si serve per prima la categoria che domanda meno: e' cio' che le
            # permette di liberare la quota che non le serve, invece di tenerla
            # bloccata mentre un'altra ne avrebbe bisogno.
            local best="" bestd=-1 d lista
            for c in "${resta[@]}"; do
                lista="L_$c"
                d="$(_domanda "${!lista}")"
                if (( bestd < 0 || d < bestd )); then bestd=$d; best=$c; fi
            done
            lista="L_$best"
            local costo
            for j in ${!lista}; do
                costo=$(( ${#scelte[$j]} + SEPW ))
                # Ci si ferma alla prima voce che non entra invece di saltarla:
                # l'ordine dentro la categoria e' merito, e scavalcare una voce
                # cara per prenderne una economica piu' in basso e' una decisione
                # che spetta al potatore, non a questo script. Il residuo lo
                # recupera la passata finale.
                (( spesa[$best] + costo <= budget[$best] )) || break
                ammessi+=("$j"); preso[$j]=1
                spesa[$best]=$(( spesa[$best] + costo ))
            done
            local avanzo=$(( budget[$best] - spesa[$best] ))
            local -a ancora=()
            for c in "${resta[@]}"; do [[ "$c" == "$best" ]] || ancora+=("$c"); done
            resta=("${ancora[@]}")
            if (( avanzo > 0 && ${#resta[@]} > 0 )); then
                local quota=$(( avanzo / ${#resta[@]} ))
                for c in "${resta[@]}"; do budget[$c]=$(( budget[$c] + quota )); done
            fi
        done
        for c in NOME ERRORE; do usato=$(( usato + ${spesa[$c]:-0} )); done
    fi

    # --- livello 2: le SEZIONE su cio' che avanza dal livello 1 ---------------
    if [[ -n "$L_SEZIONE" ]]; then
        local costo
        for j in $L_SEZIONE; do
            costo=$(( ${#scelte[$j]} + SEPW ))
            (( usato + costo <= LW_DOC_TLDR_CAP )) || break
            ammessi+=("$j"); preso[$j]=1; usato=$(( usato + costo ))
        done
    fi

    # --- passata finale: il residuo alle voci rimaste, la piu' corta per prima -
    # Le voci sono atomiche: una categoria puo' restare con trenta caratteri in
    # mano e una voce che ne chiede quarantacinque. Qui quel resto si spende.
    while :; do
        local scelto=-1 costo_scelto=0
        for (( i=0; i<${#scelte[@]}; i++ )); do
            [[ -n "${preso[$i]:-}" ]] && continue
            local costo=$(( ${#scelte[$i]} + SEPW ))
            (( usato + costo <= LW_DOC_TLDR_CAP )) || continue
            if (( scelto < 0 || costo < costo_scelto )); then
                scelto=$i; costo_scelto=$costo
            fi
        done
        (( scelto < 0 )) && break
        ammessi+=("$scelto"); preso[$scelto]=1; usato=$(( usato + costo_scelto ))
    done

    # Caso limite: la prima voce da sola sfonda il cap. La riga si scrive
    # comunque — troncarla a meta' parola produrrebbe un'ancora rotta, e
    # build-index.sh la segnala gia'.
    if (( ${#ammessi[@]} == 0 )); then
        ammessi=(0); preso[0]=1
        echo "[tldr] OLTRE-CAP: nessuna voce entra nel cap, si tiene la prima" >&2
    fi

    local tagliate=0
    for (( i=0; i<${#scelte[@]}; i++ )); do
        [[ -n "${preso[$i]:-}" ]] && continue
        echo "[tldr] OLTRE-CAP scartata ${etichette[$i]}: ${scelte[$i]}" >&2
        tagliate=$((tagliate+1))
    done

    # Resa: raggruppata per categoria, SEZIONE in testa. E' leggibilita' della
    # riga, non priorita' — la priorita' l'ha gia' consumata l'allocazione.
    local -a sez_r=() err_r=() nome_r=()
    for (( i=0; i<${#scelte[@]}; i++ )); do
        [[ -n "${preso[$i]:-}" ]] || continue
        case "${etichette[$i]}" in
            SEZIONE) sez_r+=("${scelte[$i]}") ;;
            ERRORE)  err_r+=("${scelte[$i]}") ;;
            NOME)    nome_r+=("${scelte[$i]}") ;;
        esac
    done
    local -a ordinate=("${sez_r[@]}" "${err_r[@]}" "${nome_r[@]}")
    riga=""
    for v in "${ordinate[@]}"; do
        if [[ -z "$riga" ]]; then riga="$v"; else riga="${riga} · ${v}"; fi
    done

    if [[ -n "$OUT" ]]; then
        printf '%s\n' "$riga" > "$OUT"
    else
        printf '%s\n' "$riga"
    fi

    echo "[tldr] componi: ${rese} voci rese, ${#ordinate[@]} nella riga (${#riga} char, cap ${LW_DOC_TLDR_CAP}) — sez=${#sez_r[@]} err=${#err_r[@]} nomi=${#nome_r[@]}; scarti: ${non_verbatim} non-verbatim, ${fuori_vocabolario} fuori-vocabolario, ${tagliate} oltre-cap" >&2
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
