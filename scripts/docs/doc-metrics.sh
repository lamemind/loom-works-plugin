#!/usr/bin/env bash

# =============================================================================
# doc-metrics.sh — misure deterministiche sulla doc di progetto (v2)
# Usage: doc-metrics.sh --docs-root <name> [--dir <path>] [--online]
#                       [--inbox [--natura nozioni|derivazione|sweep] [--drainable]]
#                       [--format text|tsv]
# =============================================================================
#
# Famiglia MISURA: exit 0 sempre sull'esito della misura, anche a risultato
# vuoto · exit 2 SOLO quando la misura non e' stata fatta perche' l'invocazione
# era sbagliata — e in quel caso stdout resta VUOTO: e' il discriminante fra i
# due sensi del 2.
#
# Misura dimensione e layer, non giudica: nessuna soglia di topologia ne' di
# TLDR, nessun file marcato come troppo grande, troppo piccolo o col TLDR
# mancante. La colonna TLDR e' la lunghezza della riga 3, 0 se manca.
#
# I due modi sono mutuamente esclusivi: --inbox emette la coda ed esce.
#
# Modo principale — flag per file:
#   ONLINE    file @-importato da CLAUDE.md (si paga a ogni sessione)
#   INBOX     nozione non ancora collocata
#   GEN       INDEX.md — esclusivo, nessun altro flag calcolato
# Un file senza flag porta `-`. Il modo principale emette DUE tabelle: quella
# dei file (PATH · CHAR · TLDR · FLAGS) e, in coda allo stesso stream, quella
# delle cartelle (DIR · FILES · CHAR · FLAGS, flag sempre `-`). In TSV le separa
# una riga vuota e le distingue l'header. Le colonne restano quelle di sempre,
# compresa FLAGS delle cartelle: un consumer che le legge non si rompe.
#
# Modo --inbox — la coda, ordine `created` crescente e niente altro:
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
# --online: invariato e SENZA consumer automatico in v2 — nessun flusso lo
# invoca. Resta come diagnostica on-demand: la domanda che risponde (quanto
# costa una sessione) e' reale al momento del publish.
#
# Env: PROJECT_ROOT (default: auto-detect)
# =============================================================================

set -uo pipefail

DIR=""
ONLINE=0
INBOX_ONLY=0
NATURA_FILTER=""
DRAINABLE_ONLY=0
FORMAT="text"

usage_err() { echo "[doc-metrics] ERROR: $*" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --docs-root)  LOOM_DOCS_ROOT="$2"; shift 2 ;;
        --dir)        DIR="$2"; shift 2 ;;
        --online)     ONLINE=1; shift ;;
        --inbox)      INBOX_ONLY=1; shift ;;
        --natura)     NATURA_FILTER="$2"; shift 2 ;;
        --drainable)  DRAINABLE_ONLY=1; shift ;;
        --format)     FORMAT="$2"; shift 2 ;;
        *) usage_err "argomento ignoto: $1" ;;
    esac
done

case "$FORMAT" in text|tsv) ;; *) usage_err "--format deve essere text|tsv" ;; esac
if [[ -n "$NATURA_FILTER" ]]; then
    [[ "$INBOX_ONLY" -eq 1 ]] || usage_err "--natura richiede --inbox"
    case "$NATURA_FILTER" in nozioni|derivazione|sweep) ;; *) usage_err "--natura deve essere nozioni|derivazione|sweep" ;; esac
fi
[[ "$DRAINABLE_ONLY" -eq 1 && "$INBOX_ONLY" -eq 0 ]] && usage_err "--drainable richiede --inbox"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"
# shellcheck source=lib-doc.sh
source "${SCRIPT_DIR}/lib-doc.sh"

PROJECT_ROOT="$(lw_find_project_root)"
DOCS_ROOT="$(lw_docs_root)"
[[ -z "$DIR" ]] && DIR="${PROJECT_ROOT}/${DOCS_ROOT}"
[[ "$DIR" != /* ]] && DIR="${PROJECT_ROOT}/${DIR}"

[[ -d "$DIR" ]] || usage_err "dir not found: $DIR"

# I due cicli sui file non aprono processi oltre `git log` e `inbox.sh parse`.
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

# --- Modo --inbox --------------------------------------------------------------
if [[ "$INBOX_ONLY" -eq 1 ]]; then
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
fi

# --- Modo principale ------------------------------------------------------------
doc_load_online "$PROJECT_ROOT"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

n_files=0; total_char=0
n_online=0; n_offline=0; n_inbox=0; n_altro=0
c_online=0; c_offline=0; c_inbox=0; c_altro=0
declare -A DIR_CHAR=() DIR_FILES=()

while IFS= read -r -d '' file; do
    rel="${file#"$PROJECT_ROOT"/}"
    doc_excluded "$rel" && continue

    doc_file_chars_var chars "$file"
    doc_layer_var layer "$rel"
    base="${file##*/}"

    tldr=""; tldr_len=0
    if [[ "$layer" != "inbox" ]]; then
        # il TLDR dei file inbox sta in riga 4 e lo possiede inbox.sh: qui non
        # si legge (nessuna regex propria sul formato inbox)
        doc_tldr_var tldr "$file" 3
        doc_chars_var tldr_len "$tldr"
    fi

    flags=""
    if [[ "$base" == "INDEX.md" ]]; then
        flags="GEN"    # esclusivo: artefatto generato, nessun altro flag
    else
        [[ "$layer" == "inbox" ]] && flags="INBOX"
        [[ "$layer" == "online" ]] && flags="${flags:+$flags }ONLINE"
        # un file inbox @-importato resta inbox come layer, ma il costo online va detto
        [[ "$layer" == "inbox" ]] && doc_is_online "$rel" && flags="${flags:+$flags }ONLINE"
    fi

    case "$layer" in
        online)  n_online=$((n_online+1));   c_online=$((c_online + chars)) ;;
        offline) n_offline=$((n_offline+1)); c_offline=$((c_offline + chars)) ;;
        inbox)   n_inbox=$((n_inbox+1));     c_inbox=$((c_inbox + chars)) ;;
        *)       n_altro=$((n_altro+1));     c_altro=$((c_altro + chars)) ;;
    esac

    # Stessa resa di `dirname`: `.` senza barre, `/` per un file alla radice
    if [[ "$rel" == */* ]]; then d="${rel%/*}"; d="${d:-/}"; else d="."; fi
    DIR_CHAR["$d"]=$(( ${DIR_CHAR[$d]:-0} + chars ))
    DIR_FILES["$d"]=$(( ${DIR_FILES[$d]:-0} + 1 ))

    printf '%s\t%s\t%s\t%s\n' "$rel" "$chars" "$tldr_len" "${flags:--}" >> "$TMP"
    n_files=$((n_files+1))
    total_char=$((total_char + chars))
done < <(find "$DIR" -type f -name '*.md' -print0 | sort -z)

# Le righe della tabella CARTELLE — `DIR \t FILES \t CHAR \t FLAGS`, ordine char
# decrescente, flag sempre `-`. Una sola implementazione per i due formati: il
# testo le incolonna con printf, il TSV le emette com'e'.
dir_rows() {
    local d ch
    for d in "${!DIR_CHAR[@]}"; do printf '%s\t%s\n' "${DIR_CHAR[$d]}" "$d"; done \
        | sort -t$'\t' -k1,1nr -k2,2 \
        | while IFS=$'\t' read -r ch d; do
              printf '%s\t%s\t%s\t-\n' "$d" "${DIR_FILES[$d]}" "$ch"
          done
}

# --- Output ---------------------------------------------------------------------
if [[ "$FORMAT" == "tsv" ]]; then
    if [[ -s "$TMP" ]]; then
        printf 'PATH\tCHAR\tTLDR\tFLAGS\n'
        sort -t$'\t' -k2,2nr "$TMP"
        # Seconda tabella nello STESSO stream, separata da una riga vuota: un solo
        # spawn misura file e cartelle, e il consumer non somma i char per
        # cartella. Il consumer riconosce la tabella dall'header `DIR`; uno che
        # non la trova legge la prima tabella e basta.
        printf '\n'
        printf 'DIR\tFILES\tCHAR\tFLAGS\n'
        dir_rows
    fi
else
    echo "[doc-metrics] root: ${DIR#"$PROJECT_ROOT"/}"
    echo
    printf '%-56s %8s %6s  %s\n' "PATH" "CHAR" "TLDR" "FLAGS"
    sort -t$'\t' -k2,2nr "$TMP" | while IFS=$'\t' read -r p c t f; do
        printf '%-56s %8s %6s  %s\n' "$p" "$c" "$t" "$f"
    done
    echo
    echo "TOTALI"
    echo "- file: ${n_files}  ·  char: ${total_char}"
    echo
    echo "LAYER"
    printf '%-40s %6s %10s\n' "LAYER" "FILE" "CHAR"
    printf '%-40s %6s %10s\n' "online (@-import CLAUDE.md)" "$n_online"  "$c_online"
    printf '%-40s %6s %10s\n' "offline (reference/)"        "$n_offline" "$c_offline"
    printf '%-40s %6s %10s\n' "inbox (non collocata)"       "$n_inbox"   "$c_inbox"
    printf '%-40s %6s %10s\n' "altro"                       "$n_altro"   "$c_altro"
    echo
    echo "- file inbox: ${n_inbox}"
    echo
    echo "CARTELLE"
    printf '%-56s %6s %10s\n' "DIR" "FILE" "CHAR"
    while IFS=$'\t' read -r d nf ch _; do
        printf '%-56s %6s %10s\n' "$d" "$nf" "$ch"
    done < <(dir_rows)
fi

# --- Footprint per-sessione -----------------------------------------------------
if [[ "$ONLINE" -eq 1 ]]; then
    echo
    echo "FOOTPRINT PER-SESSIONE"
    online_total=0
    if [[ -n "$LW_DOC_ONLINE_LIST" ]]; then
        while IFS= read -r rel; do
            [[ -f "${PROJECT_ROOT}/${rel}" ]] || continue
            doc_file_chars_var c "${PROJECT_ROOT}/${rel}"
            online_total=$((online_total + c))
            printf '  @-import  %-52s %8s\n' "$rel" "$c"
        done <<< "$LW_DOC_ONLINE_LIST"
    fi
    printf '  %-62s %8s\n' "subtotale @-import (CLAUDE.md)" "$online_total"

    GUARD="${SCRIPT_DIR}/../dev/check-injection-budget.sh"
    hook_total=0; hook_ok=0
    if [[ -x "$GUARD" ]] && command -v jq >/dev/null 2>&1; then
        while read -r ev char; do
            [[ "$ev" == "SessionStart" ]] || continue
            [[ "$char" =~ ^[0-9]+$ ]] || continue
            hook_total=$((hook_total + char))
            hook_ok=1
        # CHAR = ultimo token puramente numerico della riga: lo STATUS puo' essere
        # "OVER (9800)" (parentesi → non numerico) e la label puo' contenere cifre
        # nude, ma sempre PRIMA della colonna CHAR.
        done < <("$GUARD" --project "$PROJECT_ROOT" 2>/dev/null \
            | awk '$1=="SessionStart" { for (i=NF; i>=2; i--) if ($i ~ /^[0-9]+$/) { print $1, $i; break } }')
    fi
    if [[ "$hook_ok" -eq 1 ]]; then
        printf '  %-62s %8s\n' "subtotale iniezione hook (SessionStart)" "$hook_total"
        printf '  %-62s %8s\n' "TOTALE per-sessione" "$((online_total + hook_total))"
    else
        echo "  iniezione hook: non misurata (guard non eseguibile o jq assente)"
        echo "  → il totale reale è più alto: gli @-import sono solo una parte del costo"
    fi
fi

exit 0
