#!/bin/bash

# =============================================================================
# build-index.sh - Rigenera INDEX.md dai TLDR dei file .md in una directory
# Usage: build-index.sh [--dir <path>] [--output <path>] [--title <title>]
#                      [--exclude <dir1,dir2>]
# =============================================================================
#
# Scansiona ricorsivamente <dir> (default: docs/reference/) e per ogni file .md
# estrae la prima riga nel formato:
#   > **TLDR**: <testo>
# Genera un INDEX.md con struttura a sezioni (una per sottocartella) e tabelle
# `| File | TLDR |`.
#
# I file senza TLDR vengono segnalati a stderr ma NON inclusi nell'indice.
# L'INDEX.md stesso è sempre escluso.
#
# Env:
#   PROJECT_ROOT (default: $PWD)
# =============================================================================

set -euo pipefail

DIR=""
OUTPUT=""
TITLE="Reference Index"
EXCLUDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)      DIR="$2"; shift 2 ;;
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

PROJECT_ROOT="$(lw_find_project_root)"
SCAN_DIR="${PROJECT_ROOT}/${DIR}"
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
trap 'rm -f "$TMP"' EXIT

MISSING=0
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

    rel="${file#$SCAN_DIR/}"
    reldir="$(dirname "$rel")"
    fname="$(basename "$rel")"
    [[ "$reldir" == "." ]] && reldir=""

    # Escapa | nei TLDR
    tldr="${tldr//|/\\|}"
    echo "${reldir}|${fname}|${tldr}" >> "$TMP"
done < <(find "$SCAN_DIR" -type f -name '*.md' -print0 | sort -z)

# --- Genera output ------------------------------------------------------------
{
    echo "# ${TITLE}"
    echo ""
    echo "Indice della documentazione offline."
    echo ""

    # Group by reldir
    current_section=""
    sort "$TMP" | while IFS='|' read -r reldir fname tldr; do
        section="${reldir:-/}"
        if [[ "$section" != "$current_section" ]]; then
            [[ -n "$current_section" ]] && echo ""
            if [[ -z "$reldir" ]]; then
                echo "## (root)"
            else
                echo "## ${reldir}/"
            fi
            echo ""
            echo "| File | TLDR |"
            echo "| ---- | ---- |"
            current_section="$section"
        fi
        echo "| \`${fname}\` | ${tldr} |"
    done
} > "$OUTPUT_FILE"

echo "[build-index] wrote: ${OUTPUT_FILE#$PROJECT_ROOT/}"
[[ $MISSING -gt 0 ]] && echo "[build-index] ${MISSING} file(s) skipped (no TLDR)" >&2
exit 0
