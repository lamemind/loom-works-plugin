#!/usr/bin/env bash

# =============================================================================
# doc-metrics.sh — misure deterministiche sulla doc di progetto
# Usage: doc-metrics.sh [--docs-root <name>] [--dir <path>] [--online] [--inbox]
#                      [--split-threshold N] [--merge-threshold N] [--tldr-cap N]
#                      [--regroup-threshold N] [--inbox-cap N]
#                      [--format text|tsv]
# =============================================================================
#
# Conta i CHAR (non i byte) di ogni file .md della doc, estrae il TLDR di riga 3
# e alza i flag rispetto alle soglie del contratto doc (docs/doc-management.md
# §Soglie). Le soglie sono NUMERI: due esecuzioni sullo stesso albero devono dare
# lo stesso esito — è la ragione per cui questo passo è uno script e non un
# giudizio a runtime dell'agent.
#
# `--online` aggiunge il footprint per-sessione: gli @-import di CLAUDE.md PIÙ le
# entry hook SessionStart (misurate da check-injection-budget.sh). Le due voci
# vanno lette insieme: gli @-import da soli sono circa il 70% del costo reale.
#
# `--inbox` emette SOLO la coda di smaltimento — i file di {docs_root}/inbox/ —
# ed e' l'inventario che drain-doc consuma. L'ordine e' a due chiavi: prima i
# file con SENTINELLA DI DRIFT (riga 4, vedi drift_of), poi l'eta' crescente
# dentro ogni classe. Una sentinella dice che quella nozione sta curando una
# pagina gia' falsa, e un drift e' vivo dall'istante in cui il codice cambia:
# farla aspettare la coda significa tenere in piedi la bugia.
# Le colonne CAPPELLO e STATO dicono se il file e' drenabile: un file inbox e'
# WIP finche' la task che lo possiede non e' chiusa. Il verdetto e' un dato, non
# un giudizio — drain-doc filtra su un valore, per la stessa ragione per cui
# l'ordine lo decide questo script e non il chiamante.
# L'eta' viene dal commit che ha AGGIUNTO il file (`git log --diff-filter=A`, il
# piu' vecchio), non dall'mtime: un file inbox si riscrive solo per errore,
# mentre un checkout ne azzera l'mtime di tutti insieme e l'ordine a coda
# sparirebbe senza che nulla lo segnali. Fallback su mtime per un file mai
# committato. Il flag NON altera l'output di default: doc-partition.sh lo
# consuma.
#
# Flag per file:
#   SPLIT   char >= soglia split
#   MERGE?  char <= pavimento merge — trigger di RIESAME, non un ordine di fusione:
#           il file sopravvive se il suo perimetro di ricerca e' distinto
#   TLDR>N  TLDR oltre il cap
#   NOTLDR  file sotto reference/ o inbox/ senza TLDR su riga 3 (fuori dall'INDEX)
#   ONLINE  file @-importato da CLAUDE.md (si paga a ogni sessione)
#   INBOX   nozione non ancora collocata — si smaltisce, non si mantiene, ed e'
#           esente da SPLIT e MERGE: un file inbox aggrega un cappello e nasce
#           per morire al drain, quindi spezzarlo lo riporterebbe alle N voci
#           d'INDEX che il file per cappello esiste per chiudere. Il tetto
#           dell'inbox resta sul CONTEGGIO dei file.
#   GEN     artefatto generato (INDEX.md) — mai splittato a mano
#
# Tre layer, contati separatamente perche' hanno regimi di costo diversi: ONLINE si
# paga a ogni sessione, OFFLINE all'apertura, INBOX all'apertura piu' il TLDR online
# — ed e' l'unico che deve tendere a zero. Il layer si legge dal path, tranne per
# online che si legge dagli @-import: INDEX.md sta sotto reference/ ma e' online.
#
# CARTELLE: char per cartella (figli diretti, la stessa unita' con cui
# doc-partition.sh forma i gruppi) contro la soglia di REGROUP — sopra, la cartella
# non e' piu' un perimetro che un auditor tiene in testa tutto insieme.
#
# Escluso dallo scan: tasks/ (runtime, non doc) e current-task.md (symlink).
#
# Env: PROJECT_ROOT (default: auto-detect), LOOM_DOCS_ROOT (default: docs)
# Exit: 0 sempre — è una misura, non un guard. Chi decide è il chiamante.
# =============================================================================

set -uo pipefail

SPLIT_THRESHOLD=15000
MERGE_THRESHOLD=3000
TLDR_CAP=600
# Stesso numero di doc-partition.sh --max-char, e per la stessa ragione: misura
# quanta doc legge un auditor. Riusarlo tiene coerenti topologia e fan-out.
REGROUP_THRESHOLD=60000
INBOX_CAP=8
DIR=""
ONLINE=0
INBOX_ONLY=0
FORMAT="text"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --docs-root)          LOOM_DOCS_ROOT="$2"; shift 2 ;;
        --dir)                DIR="$2"; shift 2 ;;
        --online)             ONLINE=1; shift ;;
        --inbox)              INBOX_ONLY=1; shift ;;
        --split-threshold)    SPLIT_THRESHOLD="$2"; shift 2 ;;
        --merge-threshold)    MERGE_THRESHOLD="$2"; shift 2 ;;
        --tldr-cap)           TLDR_CAP="$2"; shift 2 ;;
        --regroup-threshold)  REGROUP_THRESHOLD="$2"; shift 2 ;;
        --inbox-cap)          INBOX_CAP="$2"; shift 2 ;;
        --format)             FORMAT="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"

PROJECT_ROOT="$(lw_find_project_root)"
DOCS_ROOT="$(lw_docs_root)"
[[ -z "$DIR" ]] && DIR="${PROJECT_ROOT}/${DOCS_ROOT}"
[[ "$DIR" != /* ]] && DIR="${PROJECT_ROOT}/${DIR}"

[[ -d "$DIR" ]] || { echo "[doc-metrics] ERROR: dir not found: $DIR" >&2; exit 2; }

# --- Set dei file online (@-import di CLAUDE.md) ------------------------------
# Solo primo livello: un file online che ne @-importa altri non viene seguito.
ONLINE_LIST=""
CLAUDE_MD="${PROJECT_ROOT}/CLAUDE.md"
if [[ -f "$CLAUDE_MD" ]]; then
    ONLINE_LIST="$(grep -oE '@[^ )]+\.md' "$CLAUDE_MD" 2>/dev/null | sed 's/^@//' | sort -u)"
fi

is_online() {  # <rel-to-project-root>
    [[ -z "$ONLINE_LIST" ]] && return 1
    grep -qxF "$1" <<< "$ONLINE_LIST"
}

char_count() { wc -m < "$1" | tr -d ' '; }

tldr_of() {  # <file> — convenzione strict: riga 3, stessa di build-index.sh
    local line
    line="$(sed -n '3p' "$1" 2>/dev/null)" || return 0
    [[ "$line" =~ ^\>\ \*\*TLDR\*\*:\ (.+)$ ]] || return 0
    local t="${BASH_REMATCH[1]}"
    echo "${t%"${t##*[![:space:]]}"}"
}

# Sentinella di drift: riga 4 di un file inbox, subito sotto il TLDR.
#   > **PRIORITY**: 🚨 · drift: <path> <path>
# Riga assente = priorità normale, ed è il caso di maggioranza: i file nati prima
# che le sentinelle esistessero non vanno ritoccati. Posizione fissa come il
# TLDR, quindi si legge con un `sed -n` invece che con un grep sul corpo — e
# fuori dalla riga 3 non entra nell'INDEX, che è online: costo per-sessione zero.
drift_of() {  # <file> → i path candidati, o vuoto se la riga manca
    local line
    line="$(sed -n '4p' "$1" 2>/dev/null)" || return 0
    [[ "$line" =~ ^\>\ \*\*PRIORITY\*\*:\ 🚨(.*)$ ]] || return 0
    local rest="${BASH_REMATCH[1]}"
    [[ "$rest" =~ drift:[[:space:]]*(.+)$ ]] && rest="${BASH_REMATCH[1]}" || rest="—"
    echo "${rest%"${rest##*[![:space:]]}"}"
}

# --- Cappello di un file inbox ------------------------------------------------
# L'ID sta nel NOME del file (`T74-<slug>.md` → `T74`), quindi si legge senza
# aprirlo, e il taglio sul primo `-` regge anche i legacy col suffisso numerico
# (`T89-<slug>-2.md`). Lo STATO viene dalla colonna Prog di tasks.md: `done` solo
# su ✔️, tutto il resto e' WIP.
declare -A TASK_PROG=()
load_task_prog() {
    local tasks_md="${PROJECT_ROOT}/${DOCS_ROOT}/tasks.md" id prog
    [[ -f "$tasks_md" ]] || return 0
    while IFS=$'\t' read -r id prog; do
        TASK_PROG["$id"]="$prog"
    # La colonna Prog si localizza dall'header, non per indice fisso: le colonne di
    # tasks.md sono gia' cambiate una volta (drop della K a T93) e un parse
    # posizionale non lo segnala — leggerebbe Pri al posto di Prog e chiamerebbe
    # WIP l'intera coda. Header assente → fallback sulla 4a.
    done < <(awk -F'|' '
        /^[[:space:]]*\|/ {
            for (i = 2; i <= NF; i++) { f[i] = $i; gsub(/^[ \t]+|[ \t]+$/, "", f[i]) }
            if (f[2] == "ID") { for (i = 2; i <= NF; i++) if (f[i] == "Prog") col = i; next }
            if (f[2] ~ /^[A-Za-z]+[0-9]+$/) print f[2] "\t" f[col ? col : 4]
        }' "$tasks_md")
}

cappello_of() {  # <basename> → ID, o — se il nome non ne porta uno
    [[ "$1" =~ ^([A-Za-z]+[0-9]+)- ]] && echo "${BASH_REMATCH[1]}" || echo "—"
}

# Cappello SENZA riga in tasks.md → done. `clean-tasks` purga solo le task chiuse,
# quindi un cappello che non esiste piu' e' chiuso; il ramo opposto terrebbe il
# file bloccato in coda per sempre, e nessuno potrebbe piu' sbloccarlo.
stato_of() {  # <cappello> → done | wip
    local prog
    [[ "$1" == "—" ]] && { echo "done"; return; }
    prog="${TASK_PROG[$1]-}"
    [[ -z "$prog" || "$prog" == *✔* ]] && echo "done" || echo "wip"
}

# --- Coda inbox (--inbox) -----------------------------------------------------
# Ordine: i file con sentinella di drift per primi, poi a coda — il piu' vecchio
# per primo dentro ogni classe. La priorita' si antepone QUI e non nel chiamante:
# due lettori della stessa coda devono vedere lo stesso ordine.
if [[ "$INBOX_ONLY" -eq 1 ]]; then
    INBOX_DIR="${PROJECT_ROOT}/${DOCS_ROOT}/inbox"
    NOW="$(date +%s)"
    QTMP="$(mktemp)"
    trap 'rm -f "$QTMP"' EXIT

    load_task_prog

    if [[ -d "$INBOX_DIR" ]]; then
        while IFS= read -r -d '' file; do
            rel="${file#"$PROJECT_ROOT"/}"
            created="$(cd "$PROJECT_ROOT" && git log --diff-filter=A --format=%at -- "$rel" 2>/dev/null | tail -1)"
            [[ "$created" =~ ^[0-9]+$ ]] || created="$(stat -c %Y "$file")"
            tldr="$(tldr_of "$file")"
            drift="$(drift_of "$file")"
            cap="$(cappello_of "$(basename "$file")")"
            if [[ -n "$drift" ]]; then rank=0; else rank=1; drift="—"; fi
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$rank" "$created" "$rel" "$(char_count "$file")" "${#tldr}" "$drift" \
                "$cap" "$(stato_of "$cap")" >> "$QTMP"
        done < <(find "$INBOX_DIR" -maxdepth 1 -type f -name '*.md' -print0)
    fi

    n_q=0; c_q=0; n_urg=0; n_wip=0
    while IFS=$'\t' read -r rk _ _ c _ _ _ st; do
        n_q=$((n_q+1)); c_q=$((c_q + c)); (( rk == 0 )) && n_urg=$((n_urg+1))
        [[ "$st" == "wip" ]] && n_wip=$((n_wip+1))
    done < "$QTMP"

    if [[ "$FORMAT" == "tsv" ]]; then
        printf 'PATH\tCHAR\tAGE_DAYS\tTLDR\tPRIO\tDRIFT\tCREATED\tCAPPELLO\tSTATO\n'
        sort -t$'\t' -k1,1n -k2,2n "$QTMP" | while IFS=$'\t' read -r rk ts p c t dr cp st; do
            (( rk == 0 )) && prio="urgente" || prio="normale"
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$p" "$c" "$(( (NOW - ts) / 86400 ))" "$t" "$prio" "$dr" "$ts" "$cp" "$st"
        done
    else
        echo "[doc-metrics] coda inbox: ${DOCS_ROOT}/inbox  ·  ordine: sentinelle prima, poi il più vecchio"
        echo
        printf '%-52s %8s %6s %6s %5s %9s %6s\n' "PATH" "CHAR" "AGE_D" "TLDR" "PRIO" "CAPPELLO" "STATO"
        sort -t$'\t' -k1,1n -k2,2n "$QTMP" | while IFS=$'\t' read -r rk ts p c t dr cp st; do
            (( rk == 0 )) && prio="🚨" || prio="-"
            printf '%-52s %8s %6s %6s %5s %9s %6s\n' \
                "$p" "$c" "$(( (NOW - ts) / 86400 ))" "$t" "$prio" "$cp" "$st"
            (( rk == 0 )) && echo "      drift: ${dr}"
        done
        echo
        if (( n_q > INBOX_CAP )); then
            echo "- file inbox: ${n_q} / ${INBOX_CAP}  ·  char: ${c_q}  → OLTRE IL TETTO, lo smaltimento non è più opzionale"
        else
            echo "- file inbox: ${n_q} / ${INBOX_CAP}  ·  char: ${c_q}"
        fi
        echo "- drenabili: $(( n_q - n_wip ))  ·  bloccati da un cappello ancora aperto: ${n_wip}"
        if (( n_urg > 0 )); then
            echo "- con sentinella di drift: ${n_urg}  → smaltibili subito, il tetto non li riguarda"
        fi
    fi
    exit 0
fi

# --- Scan ---------------------------------------------------------------------
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

n_files=0; n_split=0; n_merge=0; n_overcap=0; n_notldr=0; total_char=0
n_online=0; n_offline=0; n_inbox=0; n_altro=0
c_online=0; c_offline=0; c_inbox=0; c_altro=0
declare -A DIR_CHAR=() DIR_FILES=()

while IFS= read -r -d '' file; do
    rel="${file#"$PROJECT_ROOT"/}"
    case "$rel" in
        */tasks/*|*/current-task.md) continue ;;
    esac

    chars="$(char_count "$file")"
    tldr="$(tldr_of "$file")"
    tldr_len=${#tldr}
    online=0; is_online "$rel" && online=1

    # Layer: online vince sul path (INDEX.md sta sotto reference/ ma si paga a ogni
    # sessione), inbox vince su online (un file inbox @-importato resta inbox).
    if [[ "$rel" == */inbox/* ]]; then
        layer="inbox"
    elif (( online )); then
        layer="online"
    elif [[ "$rel" == */reference/* ]]; then
        layer="offline"
    else
        layer="altro"
    fi

    flags=""
    if [[ "$(basename "$file")" == "INDEX.md" ]]; then
        flags="GEN"
    elif [[ "$layer" == "inbox" ]]; then
        # Né split né merge: il verdetto su un file inbox è «smaltiscilo». Sotto il
        # pavimento perché nasce piccolo, sopra la soglia perché aggrega un cappello
        # intero — e spezzarlo lo riporterebbe alle N voci d'INDEX che il file per
        # cappello esiste per chiudere. Il tetto dell'inbox è sul conteggio dei file.
        :
    elif (( chars >= SPLIT_THRESHOLD )); then
        flags="SPLIT"; n_split=$((n_split+1))
    elif (( chars <= MERGE_THRESHOLD )); then
        flags="MERGE?"; n_merge=$((n_merge+1))
    fi
    if [[ -n "$tldr" ]]; then
        if (( tldr_len > TLDR_CAP )); then
            flags="${flags:+$flags }TLDR>${TLDR_CAP}"; n_overcap=$((n_overcap+1))
        fi
    elif [[ "$rel" == */reference/* || "$layer" == "inbox" ]] && [[ "$(basename "$file")" != "INDEX.md" ]]; then
        flags="${flags:+$flags }NOTLDR"; n_notldr=$((n_notldr+1))
    fi
    [[ "$layer" == "inbox" ]] && flags="${flags:+$flags }INBOX"
    (( online )) && flags="${flags:+$flags }ONLINE"

    case "$layer" in
        online)  n_online=$((n_online+1));   c_online=$((c_online + chars)) ;;
        offline) n_offline=$((n_offline+1)); c_offline=$((c_offline + chars)) ;;
        inbox)   n_inbox=$((n_inbox+1));     c_inbox=$((c_inbox + chars)) ;;
        *)       n_altro=$((n_altro+1));     c_altro=$((c_altro + chars)) ;;
    esac

    d="$(dirname "$rel")"
    DIR_CHAR["$d"]=$(( ${DIR_CHAR[$d]:-0} + chars ))
    DIR_FILES["$d"]=$(( ${DIR_FILES[$d]:-0} + 1 ))

    printf '%s\t%s\t%s\t%s\n' "$rel" "$chars" "$tldr_len" "${flags:--}" >> "$TMP"
    n_files=$((n_files+1))
    total_char=$((total_char + chars))
done < <(find "$DIR" -type f -name '*.md' -print0 | sort -z)

# --- Output -------------------------------------------------------------------
if [[ "$FORMAT" == "tsv" ]]; then
    printf 'PATH\tCHAR\tTLDR\tFLAGS\n'
    sort -t$'\t' -k2,2nr "$TMP"
else
    echo "[doc-metrics] root: ${DIR#"$PROJECT_ROOT"/}  ·  split ${SPLIT_THRESHOLD}  ·  merge ${MERGE_THRESHOLD}  ·  cap TLDR ${TLDR_CAP}"
    echo
    printf '%-56s %8s %6s  %s\n' "PATH" "CHAR" "TLDR" "FLAGS"
    sort -t$'\t' -k2,2nr "$TMP" | while IFS=$'\t' read -r p c t f; do
        printf '%-56s %8s %6s  %s\n' "$p" "$c" "$t" "$f"
    done
    echo
    echo "TOTALI"
    echo "- file: ${n_files}  ·  char: ${total_char}"
    echo "- sopra soglia split (${SPLIT_THRESHOLD}): ${n_split}"
    echo "- sotto pavimento merge (${MERGE_THRESHOLD}), da riesaminare: ${n_merge}"
    echo "- TLDR sopra cap (${TLDR_CAP}): ${n_overcap}"
    echo "- senza TLDR (fuori dall'INDEX): ${n_notldr}"
    echo
    echo "LAYER"
    printf '%-40s %6s %10s\n' "LAYER" "FILE" "CHAR"
    printf '%-40s %6s %10s\n' "online (@-import CLAUDE.md)" "$n_online"  "$c_online"
    printf '%-40s %6s %10s\n' "offline (reference/)"        "$n_offline" "$c_offline"
    printf '%-40s %6s %10s\n' "inbox (non collocata)"       "$n_inbox"   "$c_inbox"
    printf '%-40s %6s %10s\n' "altro"                       "$n_altro"   "$c_altro"
    echo
    if (( n_inbox > INBOX_CAP )); then
        echo "- file inbox: ${n_inbox} / ${INBOX_CAP}  → OLTRE IL TETTO, lo smaltimento non è più opzionale"
    else
        echo "- file inbox: ${n_inbox} / ${INBOX_CAP}"
    fi
    echo
    echo "CARTELLE (soglia regroup ${REGROUP_THRESHOLD})"
    printf '%-56s %6s %10s  %s\n' "DIR" "FILE" "CHAR" "FLAGS"
    n_regroup=0
    while IFS=$'\t' read -r ch d; do
        rf=""
        if (( ch >= REGROUP_THRESHOLD )); then rf="REGROUP"; n_regroup=$((n_regroup+1)); fi
        printf '%-56s %6s %10s  %s\n' "$d" "${DIR_FILES[$d]}" "$ch" "${rf:--}"
    done < <(for d in "${!DIR_CHAR[@]}"; do printf '%s\t%s\n' "${DIR_CHAR[$d]}" "$d"; done \
             | sort -t$'\t' -k1,1nr -k2,2)
    echo
    echo "- cartelle oltre soglia regroup (${REGROUP_THRESHOLD}): ${n_regroup}"
fi

# --- Footprint per-sessione ---------------------------------------------------
if [[ "$ONLINE" -eq 1 ]]; then
    echo
    echo "FOOTPRINT PER-SESSIONE"
    online_total=0
    if [[ -n "$ONLINE_LIST" ]]; then
        while IFS= read -r rel; do
            [[ -f "${PROJECT_ROOT}/${rel}" ]] || continue
            c="$(char_count "${PROJECT_ROOT}/${rel}")"
            online_total=$((online_total + c))
            printf '  @-import  %-52s %8s\n' "$rel" "$c"
        done <<< "$ONLINE_LIST"
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
        # CHAR = ultimo token puramente numerico della riga: lo STATUS può essere
        # "OVER (9800)" (parentesi → non numerico) e la label può contenere cifre
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
