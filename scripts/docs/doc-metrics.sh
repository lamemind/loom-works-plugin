#!/usr/bin/env bash

# =============================================================================
# doc-metrics.sh — misure deterministiche sulla doc di progetto
# Usage: doc-metrics.sh [--docs-root <name>] [--dir <path>] [--online]
#                      [--split-threshold N] [--merge-threshold N] [--tldr-cap N]
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
# Flag per file:
#   SPLIT   char >= soglia split
#   MERGE?  char <= pavimento merge — trigger di RIESAME, non un ordine di fusione:
#           il file sopravvive se il suo perimetro di ricerca e' distinto
#   TLDR>N  TLDR oltre il cap
#   NOTLDR  file sotto reference/ senza TLDR su riga 3 (resta fuori dall'INDEX)
#   ONLINE  file @-importato da CLAUDE.md (si paga a ogni sessione)
#   GEN     artefatto generato (INDEX.md) — mai splittato a mano
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
DIR=""
ONLINE=0
FORMAT="text"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --docs-root)        LOOM_DOCS_ROOT="$2"; shift 2 ;;
        --dir)              DIR="$2"; shift 2 ;;
        --online)           ONLINE=1; shift ;;
        --split-threshold)  SPLIT_THRESHOLD="$2"; shift 2 ;;
        --merge-threshold)  MERGE_THRESHOLD="$2"; shift 2 ;;
        --tldr-cap)         TLDR_CAP="$2"; shift 2 ;;
        --format)           FORMAT="$2"; shift 2 ;;
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

# --- Scan ---------------------------------------------------------------------
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

n_files=0; n_split=0; n_merge=0; n_overcap=0; n_notldr=0; total_char=0

while IFS= read -r -d '' file; do
    rel="${file#"$PROJECT_ROOT"/}"
    case "$rel" in
        */tasks/*|*/current-task.md) continue ;;
    esac

    chars="$(char_count "$file")"
    tldr="$(tldr_of "$file")"
    tldr_len=${#tldr}

    flags=""
    if [[ "$(basename "$file")" == "INDEX.md" ]]; then
        flags="GEN"
    elif (( chars >= SPLIT_THRESHOLD )); then
        flags="SPLIT"; n_split=$((n_split+1))
    elif (( chars <= MERGE_THRESHOLD )); then
        flags="MERGE?"; n_merge=$((n_merge+1))
    fi
    if [[ -n "$tldr" ]]; then
        if (( tldr_len > TLDR_CAP )); then
            flags="${flags:+$flags }TLDR>${TLDR_CAP}"; n_overcap=$((n_overcap+1))
        fi
    elif [[ "$rel" == */reference/* && "$(basename "$file")" != "INDEX.md" ]]; then
        flags="${flags:+$flags }NOTLDR"; n_notldr=$((n_notldr+1))
    fi
    is_online "$rel" && flags="${flags:+$flags }ONLINE"

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
    echo "- reference/ senza TLDR (fuori dall'INDEX): ${n_notldr}"
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
