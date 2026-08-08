#!/bin/bash

# =============================================================================
# build-index.sh - Rigenera INDEX.md dai TLDR dei file .md in una directory
# Usage: build-index.sh [--dir <path>] [--output <path>] [--title <title>]
#                      [--exclude <dir1,dir2>]
# =============================================================================
#
# Scansiona ricorsivamente <dir> (default: docs/reference/) e per ogni file .md
# estrae la riga 3 nel formato:
#   > **TLDR**: <testo>
# Genera un INDEX.md con struttura a sezioni (una per sottocartella) e liste
# `- \`file.md\` — <tldr>`.
#
# In coda indicizza anche {docs_root}/inbox/ — il layer delle nozioni non ancora
# collocate — in una sezione propria, preceduta dalla riga di PRECEDENZA: in caso
# di contraddizione con reference/, vince l'inbox.
#
# La sezione (e con essa la riga) si emette solo se l'inbox contiene almeno un file
# indicizzabile, non se la cartella esiste: una regola che sparisce quando smette di
# applicarsi non può driftare, e su un'inbox vuota la precedenza sarebbe permanente.
#
# I file senza TLDR vengono segnalati a stderr ma NON inclusi nell'indice.
# L'INDEX.md stesso è sempre escluso.
#
# I TLDR oltre TLDR_CAP char sono una violazione BLOCCANTE del contratto doc
# (docs/doc-management.md §Soglie): l'indice viene scritto comunque, ma lo
# script esce 2. Il cap viene dal contratto — cambiarlo qui lo sfasa da lì.
#
# Exit code:
#   0  indice scritto, nessuna violazione
#   1  errore duro: indice NON scritto (dir inesistente, argomento ignoto)
#   2  indice scritto, uno o più TLDR oltre il cap
#
# Env:
#   PROJECT_ROOT (default: $PWD)
# =============================================================================

set -euo pipefail

# Cap TLDR in caratteri — contratto doc §Soglie
TLDR_CAP=600

DIR=""
INBOX_DIR=""
OUTPUT=""
TITLE="Reference Index"
EXCLUDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)      DIR="$2"; shift 2 ;;
        --inbox)    INBOX_DIR="$2"; shift 2 ;;
        --docs-root) LOOM_DOCS_ROOT="$2"; shift 2 ;;
        --output)   OUTPUT="$2"; shift 2 ;;
        --title)    TITLE="$2"; shift 2 ;;
        --exclude)  EXCLUDE="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"

[[ -z "$DIR" ]] && DIR="$(lw_docs_root)/reference"
[[ -z "$INBOX_DIR" ]] && INBOX_DIR="$(lw_docs_root)/inbox"

PROJECT_ROOT="$(lw_find_project_root)"
SCAN_DIR="${PROJECT_ROOT}/${DIR}"
INBOX_SCAN_DIR="${PROJECT_ROOT}/${INBOX_DIR}"
OUTPUT_FILE="${OUTPUT:-${SCAN_DIR}/INDEX.md}"

if [[ ! -d "$SCAN_DIR" ]]; then
    echo "[build-index] ERROR: dir not found: $SCAN_DIR" >&2
    exit 1
fi

# --- Estrai TLDR dalla prima riga utile ---------------------------------------
# Accetta: `> **TLDR**: testo` (con o senza spazi flessibili)
extract_tldr() {
    local file="$1"
    # Convenzione strict: TLDR opt-in deve stare esattamente sulla 3a riga del file
    # nel formato `> **TLDR**: <testo>`. Pattern semplice, niente parser stato.
    local line
    line=$(sed -n '3p' "$file") || return 0
    [[ "$line" =~ ^\>\ \*\*TLDR\*\*:\ (.+)$ ]] || return 0
    # Trim trailing whitespace
    local tldr="${BASH_REMATCH[1]}"
    echo "${tldr%"${tldr##*[![:space:]]}"}"
}

should_exclude() {
    local path="$1"
    [[ -z "$EXCLUDE" ]] && return 1
    local IFS=','
    for pat in $EXCLUDE; do
        [[ "$path" == *"/$pat/"* ]] && return 0
        [[ "$path" == *"/$pat" ]] && return 0
    done
    return 1
}

# --- Raccogli files, raggruppa per directory ----------------------------------
# Output temp: "<reldir>|<filename>|<tldr>"
TMP="$(mktemp)"
INBOX_TMP="$(mktemp)"
trap 'rm -f "$TMP" "$INBOX_TMP"' EXIT

MISSING=0
OVERCAP=0

collect() {  # <scan-dir> <tmp-file>
    local scan="$1" out="$2" file tldr rel reldir fname
    [[ -d "$scan" ]] || return 0
    while IFS= read -r -d '' file; do
        # skip INDEX.md stesso
        [[ "$(basename "$file")" == "INDEX.md" ]] && continue
        should_exclude "$file" && continue

        tldr="$(extract_tldr "$file")"
        if [[ -z "$tldr" ]]; then
            echo "[build-index] WARN no TLDR: ${file#$PROJECT_ROOT/}" >&2
            MISSING=$((MISSING+1))
            continue
        fi

        # ${#var} conta caratteri (non byte) con locale UTF-8 — coerente col cap del contratto
        if (( ${#tldr} > TLDR_CAP )); then
            echo "[build-index] OVER-CAP TLDR ${#tldr} char (cap ${TLDR_CAP}): ${file#$PROJECT_ROOT/}" >&2
            OVERCAP=$((OVERCAP+1))
        fi

        rel="${file#"$scan"/}"
        reldir="$(dirname "$rel")"
        fname="$(basename "$rel")"
        [[ "$reldir" == "." ]] && reldir=""

        # Nessun escape di `|`: l'output è a liste, e `read` assegna all'ultima
        # variabile il resto della riga separatori inclusi → il TLDR arriva intatto.
        echo "${reldir}|${fname}|${tldr}" >> "$out"
    done < <(find "$scan" -type f -name '*.md' -print0 | sort -z)
}

collect "$SCAN_DIR" "$TMP"
# L'inbox si indicizza solo se è un perimetro diverso da quello già scansionato,
# o un `--dir` puntato sull'inbox la elencherebbe due volte.
[[ "$INBOX_SCAN_DIR" != "$SCAN_DIR" ]] && collect "$INBOX_SCAN_DIR" "$INBOX_TMP"

# --- Genera output ------------------------------------------------------------
{
    echo "# ${TITLE}"
    echo ""
    echo "Indice della documentazione offline."
    echo ""

    # Group by reldir. `LC_ALL=C sort -t'|' -k1,1` e non `sort`: sotto collazione
    # locale la punteggiatura non pesa al livello primario, quindi il separatore `|`
    # viene ignorato e le righe si ordinano sul testo intero — i figli diretti
    # (reldir vuoto) finiscono sparsi fra le sottocartelle e la sezione `(root)`
    # viene riaperta a ogni interruzione. Ordinare sul campo, in C, tiene un gruppo
    # per directory e rende l'ordine indipendente dal locale di chi lancia.
    current_section=""
    LC_ALL=C sort -t'|' -k1,1 -k2,2 "$TMP" | while IFS='|' read -r reldir fname tldr; do
        section="${reldir:-/}"
        if [[ "$section" != "$current_section" ]]; then
            [[ -n "$current_section" ]] && echo ""
            if [[ -z "$reldir" ]]; then
                echo "## (root)"
            else
                echo "## ${reldir}/"
            fi
            echo ""
            current_section="$section"
        fi
        echo "- \`${fname}\` — ${tldr}"
    done

    # Sezione inbox: emessa solo se c'è almeno una voce. Zero file → nessuna
    # sezione → nessuna riga di precedenza.
    if [[ -s "$INBOX_TMP" ]]; then
        echo ""
        echo "## inbox — nozioni non ancora collocate"
        echo ""
        echo "> Precedenza: in caso di contraddizione con un file di \`reference/\`,"
        echo "> **prevale la voce inbox** — è più recente e nasce dal codice appena scritto."
        echo ""
        LC_ALL=C sort -t'|' -k1,1 -k2,2 "$INBOX_TMP" | while IFS='|' read -r reldir fname tldr; do
            echo "- \`${fname}\` — ${tldr}"
        done
    fi
} > "$OUTPUT_FILE"

echo "[build-index] wrote: ${OUTPUT_FILE#$PROJECT_ROOT/}"
[[ $MISSING -gt 0 ]] && echo "[build-index] ${MISSING} file(s) skipped (no TLDR)" >&2

if (( OVERCAP > 0 )); then
    echo "[build-index] FAIL: ${OVERCAP} TLDR oltre il cap ${TLDR_CAP} — riscrivili come ancora (contratto doc §Soglie)" >&2
    exit 2
fi
exit 0
