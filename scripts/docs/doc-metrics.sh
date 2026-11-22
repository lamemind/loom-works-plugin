#!/usr/bin/env bash

# =============================================================================
# doc-metrics.sh — la coda dei file inbox di progetto
# Usage: doc-metrics.sh --docs-root <name> --inbox
#                       [--natura nozioni|derivazione|sweep] [--drainable]
#                       [--format text|tsv]
# =============================================================================
#
# Famiglia MISURA: exit 0 sempre sull'esito della misura, anche a risultato
# vuoto · exit 2 SOLO quando la misura non e' stata fatta perche' l'invocazione
# era sbagliata — e in quel caso stdout resta VUOTO: e' il discriminante fra i
# due sensi del 2.
#
# Un modo solo, --inbox, ed e' obbligatorio: lo script non misura i file della
# docs-root, e un'invocazione senza --inbox e' un'invocazione sbagliata. Il flag
# resta nell'argv perche' e' la forma che i chiamanti scrivono.
#
# La coda, ordine `created` crescente e niente altro:
#   PATH · NATURA · INDEXED · DRAINABLE · BRANCH · NOZIONI · APERTE · CHAR ·
#   CREATED · AGE_DAYS · CAPPELLO
# Le colonne di stato vengono da `inbox.sh parse`, invocato una volta per file:
# doc-metrics NON conosce il formato inbox (lib-doc §2.2). Il 2 di parse su un
# file malformato NON e' un fallimento: diventa NATURA=malformato (altre colonne
# vuote, riga su stderr) e l'exit resta 0 — una coda che contiene un malformato
# e' una misura riuscita. --drainable = token drainable presente E branch:
# assente (un file branched non entra in nessuna coda, drainable o no);
# malformato sempre escluso dal filtro. CREATED dal commit che ha AGGIUNTO il
# file, fallback stat per un file mai committato — mai l'mtime: un checkout lo
# azzera su tutti i file insieme. CAPPELLO dal nome del file (provenienza
# leggibile, non un dato su cui si decide). CHAR e' il costo di chi apre il
# file per leggerlo.
#
# Env: PROJECT_ROOT (default: auto-detect)
# =============================================================================

set -uo pipefail

INBOX_ONLY=0
NATURA_FILTER=""
DRAINABLE_ONLY=0
FORMAT="text"

usage_err() { echo "[doc-metrics] ERROR: $*" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --docs-root)  LOOM_DOCS_ROOT="$2"; shift 2 ;;
        --inbox)      INBOX_ONLY=1; shift ;;
        --natura)     NATURA_FILTER="$2"; shift 2 ;;
        --drainable)  DRAINABLE_ONLY=1; shift ;;
        --format)     FORMAT="$2"; shift 2 ;;
        *) usage_err "argomento ignoto: $1" ;;
    esac
done

[[ "$INBOX_ONLY" -eq 1 ]] || usage_err "--inbox obbligatorio: lo script misura solo la coda inbox"
case "$FORMAT" in text|tsv) ;; *) usage_err "--format deve essere text|tsv" ;; esac
if [[ -n "$NATURA_FILTER" ]]; then
    case "$NATURA_FILTER" in nozioni|derivazione|sweep) ;; *) usage_err "--natura deve essere nozioni|derivazione|sweep" ;; esac
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"
# shellcheck source=lib-doc.sh
source "${SCRIPT_DIR}/lib-doc.sh"

PROJECT_ROOT="$(lw_find_project_root)"
DOCS_ROOT="$(lw_docs_root)"

# Il ciclo sui file non apre processi oltre `git log` e `inbox.sh parse`.
# I caratteri di un file li conta doc_file_chars_var di lib-doc.sh, in code
# point e senza processi: `wc -m` costava un processo per file e in Git Bash
# contava byte (lib-doc.sh §Conteggio dei caratteri). Gli helper qui sotto
# assegnano alla variabile che il chiamante nomina invece di stampare, come le
# letture di lib-doc.sh: in Git Bash su Windows ogni `$(…)` e' un fork emulato, e
# moltiplicato per i file e per le ancore era quasi tutto il tempo dello script
# (lib-doc.sh §Lettura senza sottoprocessi).

cappello_of() {  # <var> <basename> → <var> = ID dal nome, vuoto se il nome non ne porta uno
    local _co_id=""
    [[ "$2" =~ ^([A-Za-z]+[0-9]+)- ]] && _co_id="${BASH_REMATCH[1]}"
    printf -v "$1" '%s' "$_co_id"
}

# --- La coda ------------------------------------------------------------------
INBOX_DIR="${PROJECT_ROOT}/${DOCS_ROOT}/inbox"
NOW="$(date +%s)"
QTMP="$(mktemp)"
trap 'rm -f "$QTMP"' EXIT

if [[ -d "$INBOX_DIR" ]]; then
    while IFS= read -r -d '' file; do
        rel="${file#"$PROJECT_ROOT"/}"
        # L'ultima riga del log, cioe' il commit di aggiunta piu' vecchio
        created="$(git -C "$PROJECT_ROOT" log --diff-filter=A --format=%at -- "$rel" 2>/dev/null)"
        created="${created##*$'\n'}"
        [[ "$created" =~ ^[0-9]+$ ]] || created="$(stat -c %Y "$file")"

        parse_out="$("${SCRIPT_DIR}/inbox.sh" parse --file "$file" --format tsv 2>/dev/null)"
        parse_rc=$?

        if [[ $parse_rc -eq 2 ]]; then
            ragione="${parse_out#*$'\t'}"; ragione="${ragione%%$'\t'*}"
            echo "[doc-metrics] WARN malformato: ${rel} — ${ragione}" >&2
            # escluso da qualunque filtro: nessun processo lo consuma, e non
            # ha una natura che possa matchare --natura
            if [[ -z "$NATURA_FILTER" && "$DRAINABLE_ONLY" -eq 0 ]]; then
                printf '%s\t%s\tmalformato\t\t\t\t\t\t\t\n' "$created" "$rel" >> "$QTMP"
            fi
            continue
        elif [[ $parse_rc -ne 0 ]]; then
            echo "[doc-metrics] WARN parse fallito (exit ${parse_rc}): ${rel}" >&2
            continue
        fi

        natura="";  indexed="no"; drainable="no"; branch=""
        n_noz=0; n_aperte=0
        # tab tradotto in unit separator prima della read: con IFS=$'\t' i tab
        # sono whitespace e i campi VUOTI in mezzo collassano, spostando le colonne
        while IFS=$'\x1f' read -r kind f1 f2 f3 f4 _; do
            case "$kind" in
                MARKER)
                    natura="$f1"
                    [[ "$f2" == "indexed" ]] && indexed="si"
                    [[ "$f3" == "drainable" ]] && drainable="si"
                    branch="$f4" ;;
                NOZIONE)
                    n_noz=$((n_noz+1))
                    [[ "$f2" == "aperta" ]] && n_aperte=$((n_aperte+1)) ;;
            esac
        done <<< "${parse_out//$'\t'/$'\037'}"

        if [[ -n "$NATURA_FILTER" && "$natura" != "$NATURA_FILTER" ]]; then continue; fi
        if [[ "$DRAINABLE_ONLY" -eq 1 ]]; then
            [[ "$drainable" == "si" && -z "$branch" ]] || continue
        fi

        doc_file_chars_var chars "$file"
        cappello_of cappello "${file##*/}"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$created" "$rel" "$natura" "$indexed" "$drainable" "$branch" \
            "$n_noz" "$n_aperte" "$chars" "$cappello" >> "$QTMP"
    done < <(find "$INBOX_DIR" -maxdepth 1 -type f -name '*.md' -print0 | sort -z)
fi

# filtro natura/drainable sui malformati: --drainable li esclude sempre
# (nessun processo li consuma); --natura non li matcha mai
if [[ "$FORMAT" == "tsv" ]]; then
    if [[ -s "$QTMP" ]]; then
        printf 'PATH\tNATURA\tINDEXED\tDRAINABLE\tBRANCH\tNOZIONI\tAPERTE\tCHAR\tCREATED\tAGE_DAYS\tCAPPELLO\n'
        sort -t$'\t' -k1,1n -k2,2 "$QTMP" | tr '\t' '\037' | while IFS=$'\x1f' read -r ts p nat idx dr br nn na ch cp; do
            if [[ "$nat" == "malformato" ]]; then
                printf '%s\tmalformato\t\t\t\t\t\t\t\t\t\n' "$p"
            else
                printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                    "$p" "$nat" "$idx" "$dr" "$br" "$nn" "$na" "$ch" "$ts" "$(( (NOW - ts) / 86400 ))" "$cp"
            fi
        done
    fi
else
    echo "[doc-metrics] coda inbox: ${DOCS_ROOT}/inbox  ·  ordine: created crescente"
    echo
    printf '%-46s %-12s %-4s %-5s %-22s %4s %4s %8s %9s\n' \
        "PATH" "NATURA" "IDX" "DRAIN" "BRANCH" "NOZ" "APER" "CHAR" "CAPPELLO"
    sort -t$'\t' -k1,1n -k2,2 "$QTMP" | tr '\t' '\037' | while IFS=$'\x1f' read -r ts p nat idx dr br nn na ch cp; do
        if [[ "$nat" == "malformato" ]]; then
            printf '%-46s %-12s\n' "$p" "malformato"
        else
            printf '%-46s %-12s %-4s %-5s %-22s %4s %4s %8s %9s\n' \
                "$p" "$nat" "$idx" "$dr" "${br:--}" "$nn" "$na" "$ch" "${cp:--}"
        fi
    done
fi

exit 0
