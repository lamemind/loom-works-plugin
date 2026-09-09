#!/bin/bash

# =============================================================================
# bump-gitlink.sh — allinea il gitlink dei submodule del cappello
# Usage: bump-gitlink.sh [--dry-run] [<path>...]
# =============================================================================
#
# Un repo cappello pinna ogni membro a un commit fisso (gitlink, mode 160000).
# Quando un submodule avanza — un commit nel deck, nel plugin, in compass — il
# gitlink resta indietro finche' qualcuno non lo bumpa. Questo script e' l'UNICA
# sequenza di bump della famiglia: la usa il deck (tasto ^U) e la si lancia a
# mano da shell. Averne due implementazioni darebbe due sequenze capaci di
# divergere, e la sequenza sicura e' esattamente quella che nessuno deve poter
# dimenticare.
#
# DUE GUARDIE, in quest'ordine, per ogni membro col checkout diverso dal gitlink.
#
# ① IL VERSO. `git submodule status` marca con `+` un checkout che non coincide
#    col gitlink, e NON dice in quale verso (`man git-submodule`: «`+` if the
#    currently checked out submodule commit does not match the SHA-1 found in
#    the index»). Un cappello pullato senza `git submodule update` ha il
#    checkout PIU' VECCHIO del gitlink e porta lo stesso `+`: un `git add <sub>`
#    li' pinnerebbe il cappello a un commit precedente — una regressione
#    silenziosa, che la guardia sul remote non vede perche' quel commit vecchio
#    sul remote c'e' eccome. Si verifica quindi che il gitlink registrato sia
#    ANTENATO di HEAD del membro, e altrimenti si salta.
#
# ② IL REMOTE. Il cappello puo' pinnare solo commit gia' raggiungibili dal
#    remote del membro. Un gitlink verso un commit locale non pushato produce un
#    cappello che si clona ma non si ricostruisce: `git submodule update --init`
#    fallisce sul commit mancante. Il danno e' invisibile a chi l'ha creato — la
#    sua copia quel commit ce l'ha — e si manifesta nel clone di qualcun altro,
#    giorni dopo.
#
# COSA NON FA: non pusha il cappello. Il bump si ferma al commit locale, perche'
# un gitlink committato per sbaglio si annulla con un `git reset` che non tocca
# nessun remote, mentre uno gia' pushato e' nella copia di chiunque abbia
# pullato. Non riallinea i membri INDIETRO: quello e' `git submodule update`,
# che la skill pull-repos gia' copre.
#
# STDOUT: sempre TSV, una riga per membro, tre campi:
#
#     <path> \t <stato> \t <dettaglio>
#
# Stati: allineato · non-inizializzato · conflitto · avanti · indietro ·
#        non-pushato · remote-irraggiungibile · bumpato
#
# `avanti` = passa entrambe le guardie (dry-run: «lo bumperei»). `bumpato` =
# entrato nel commit appena fatto. Sono due fatti diversi e portano due nomi: un
# solo nome renderebbe la riga di stato del deck indistinguibile da un'anteprima.
# Il dettaglio porta il GESTO che manca, cosi' chi legge non deve dedurlo.
#
# Nessuna riga di intestazione: il primo campo e' gia' un path, e un header
# sarebbe una riga in piu' da scartare per ogni consumer.
#
# --dry-run: classifica e basta. NON contatta la rete — la guardia ② gira sui
# remote-tracking ref locali senza `fetch`, perche' il deck rimisura ogni 30
# secondi e non deve aprire una connessione a ogni giro. Ne discende che il
# sensore puo' dire «bumpabile» di un commit che il bump poi salta: la guardia
# sta sull'AZIONE, e un contatore non e' un'autorizzazione.
#
# Exit: 0 = classificato (con o senza bump) · 1 = errore git o commit fallito
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib.sh"

DRY_RUN=0
declare -a FILTER=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --) shift; FILTER+=("$@"); break ;;
        -*) echo "ERROR: opzione sconosciuta: $1" >&2; exit 1 ;;
        *) FILTER+=("$1"); shift ;;
    esac
done

ROOT="$(lw_find_project_root)"

# Nessun submodule dichiarato: niente da misurare, niente da dire. Non e' un
# errore — e' la condizione normale della maggioranza dei progetti.
[[ -f "${ROOT}/.gitmodules" ]] || exit 0

if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: ${ROOT} non e' un repo git" >&2
    exit 1
fi

# Le righe si accumulano e si stampano alla fine: la classificazione di tutti i
# membri precede il commit, e i membri entrati nel commit cambiano stato dopo.
declare -a ROWS=()
declare -a BUMP_PATHS=()
declare -a BUMP_OLD=()
declare -a BUMP_NEW=()
declare -a BUMP_SUBJECT=()

row() {  # <path> <stato> <dettaglio>
    ROWS+=("$1"$'\t'"$2"$'\t'"$3")
}

short() {  # <sub-abs> <sha>
    git -C "$1" rev-parse --short "$2" 2>/dev/null || printf '%s' "${2:0:7}"
}

# ---- Classificazione ---------------------------------------------------------

if [[ ${#FILTER[@]} -gt 0 ]]; then
    status_out="$(git -C "$ROOT" submodule status -- "${FILTER[@]}" 2>&1)"
else
    status_out="$(git -C "$ROOT" submodule status 2>&1)"
fi
status_rc=$?
if [[ "$status_rc" -ne 0 ]]; then
    echo "ERROR: git submodule status: ${status_out}" >&2
    exit 1
fi

while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    prefix="${line:0:1}"
    rest="${line:1}"
    sha="${rest%% *}"
    path="${rest#* }"
    # Il describe fra parentesi e' opzionale (assente sui non inizializzati). Si
    # toglie il suffisso PIU' CORTO che matcha " (*", cioe' l'ultima parentesi
    # aperta: un path che ne contenesse una resterebbe comunque intero.
    path="${path% (*}"
    [[ -n "$path" ]] || continue
    sub="${ROOT}/${path}"

    case "$prefix" in
        '-')
            # Nessun checkout: non c'e' nessun bump che lo sistemi, e contarlo
            # fra i disallineati darebbe un numero che il tasto non porta a zero.
            row "$path" "non-inizializzato" "git submodule update --init -- ${path}"
            continue
            ;;
        'U')
            row "$path" "conflitto" "risolvi il conflitto di merge in ${path}"
            continue
            ;;
        ' ')
            row "$path" "allineato" "-"
            continue
            ;;
    esac

    # Da qui in giu' il prefisso e' `+`: checkout diverso dal gitlink, verso
    # ancora ignoto.

    gitlink="$(git -C "$ROOT" ls-tree HEAD -- "$path" 2>/dev/null | awk '{print $3}')"
    if [[ -z "$gitlink" ]]; then
        # Submodule aggiunto ma mai committato nel cappello: non c'e' un gitlink
        # da confrontare, quindi non c'e' un verso da misurare.
        row "$path" "indietro" "nessun gitlink in HEAD per ${path}: committalo a mano"
        continue
    fi

    head_sha="$(git -C "$sub" rev-parse HEAD 2>/dev/null)"
    if [[ -z "$head_sha" ]]; then
        row "$path" "non-inizializzato" "git submodule update --init -- ${path}"
        continue
    fi

    # ① GUARDIA SUL VERSO. Esce 0 solo se HEAD del membro DISCENDE dal gitlink.
    # Copre due situazioni con lo stesso rimedio: il checkout piu' vecchio del
    # gitlink, e il gitlink che il membro non conosce affatto (mai fetchato) —
    # in entrambe `git submodule update` e' il gesto che riallinea.
    if ! git -C "$sub" merge-base --is-ancestor "$gitlink" HEAD >/dev/null 2>&1; then
        row "$path" "indietro" "git submodule update -- ${path}"
        continue
    fi

    # ② GUARDIA SUL REMOTE. Il fetch gira SOLO nel bump: e' l'unica parte
    # dell'intero script che tocca la rete, e il sensore la chiama ogni 30
    # secondi.
    #
    # Senza `origin` la guardia non si applica: non c'e' nessun remote da cui il
    # commit possa essere irraggiungibile. E' lo stesso modello del resto della
    # famiglia — repo sempre, remote opzionale (lib.sh, lw_has_remote) — e
    # rifiutare qui il bump renderebbe impossibile per sempre l'allineamento su
    # una famiglia tenuta solo in locale.
    if git -C "$sub" remote get-url origin >/dev/null 2>&1; then
        if [[ "$DRY_RUN" -eq 0 ]]; then
            if ! git -C "$sub" fetch -q origin 2>/dev/null; then
                row "$path" "remote-irraggiungibile" "git -C ${path} fetch origin"
                continue
            fi
        fi
        # Vuoto = ogni commit fino a HEAD e' raggiungibile da un remote-tracking
        # ref. `-n 1` basta: si sta misurando l'esistenza, non il conteggio.
        if [[ -n "$(git -C "$sub" rev-list -n 1 "$head_sha" --not --remotes 2>/dev/null)" ]]; then
            row "$path" "non-pushato" "git -C ${path} push"
            continue
        fi
    fi

    subject="$(git -C "$sub" log -1 --format=%s 2>/dev/null)"
    old_short="$(short "$sub" "$gitlink")"
    new_short="$(short "$sub" "$head_sha")"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        row "$path" "avanti" "${old_short}→${new_short} ${subject}"
    else
        BUMP_PATHS+=("$path")
        BUMP_OLD+=("$old_short")
        BUMP_NEW+=("$new_short")
        BUMP_SUBJECT+=("$subject")
    fi
done <<< "$status_out"

# ---- Il commit ---------------------------------------------------------------
#
# Uno solo, con pathspec sui SOLI membri idonei: il working tree del cappello e'
# un cantiere vivo e un `git add -A` ci rastrellerebbe dentro il lavoro di altre
# sessioni. Il messaggio eredita le due grafie gia' in uso nella storia del
# cappello invece di inventarne una terza.

EXIT=0

if [[ "$DRY_RUN" -eq 0 && ${#BUMP_PATHS[@]} -gt 0 ]]; then
    if [[ ${#BUMP_PATHS[@]} -eq 1 ]]; then
        msg="chore(${BUMP_PATHS[0]}): gitlink — ${BUMP_SUBJECT[0]}"
    else
        joined="$(printf '%s + ' "${BUMP_PATHS[@]}")"
        msg="chore(gitlink): ${joined% + }"$'\n'
        for i in "${!BUMP_PATHS[@]}"; do
            msg+=$'\n'"${BUMP_PATHS[$i]} ${BUMP_OLD[$i]}→${BUMP_NEW[$i]} ${BUMP_SUBJECT[$i]}"
        done
    fi

    # Lo stdout di git va su STDERR: qui stdout e' il canale del TSV, e la riga
    # `[master abc1234] chore(...)` che `git commit` stampa si infilerebbe fra i
    # record come una riga a un campo solo.
    lw_git_add_n_commit "$msg" "${BUMP_PATHS[@]}" >&2
    case $? in
        0)
            for i in "${!BUMP_PATHS[@]}"; do
                row "${BUMP_PATHS[$i]}" "bumpato" "${BUMP_OLD[$i]}→${BUMP_NEW[$i]} ${BUMP_SUBJECT[$i]}"
            done
            ;;
        2)
            # L'indice non ha visto nessuna differenza sui path passati: il
            # gitlink era gia' quello. Nessun commit vuoto, e nessun errore —
            # una seconda esecuzione a vuoto e' il caso normale, non un guasto.
            for i in "${!BUMP_PATHS[@]}"; do
                row "${BUMP_PATHS[$i]}" "allineato" "gitlink gia' aggiornato"
            done
            ;;
        *)
            for i in "${!BUMP_PATHS[@]}"; do
                row "${BUMP_PATHS[$i]}" "avanti" "commit del gitlink fallito"
            done
            EXIT=1
            ;;
    esac
fi

[[ ${#ROWS[@]} -gt 0 ]] && printf '%s\n' "${ROWS[@]}"

exit "$EXIT"
