#!/bin/bash

# =============================================================================
# build-index.sh — rigenera INDEX.md dai TLDR di reference/ + sezioni inbox (v2)
# Usage: build-index.sh [--dir <path>] [--inbox <path>] [--docs-root <name>]
#                       [--output <path>] [--title <title>] [--exclude <dir1,dir2>]
# =============================================================================
#
# Scansiona ricorsivamente <dir> (default: {docs_root}/reference/) e per ogni
# file .md estrae il TLDR di riga 3 (`> **TLDR**: <testo>`). Genera un INDEX.md
# a sezioni (una per sottocartella) con liste `- \`file.md\` — <tldr>`.
#
# Sezioni inbox (v2):
#   - L'indicizzazione la decide il MARKER `indexed`, non la presenza del TLDR:
#     un `nozioni` con `indexed` senza TLDR entra col SOLO TITOLO, in corsivo —
#     il router che sceglie dove cercare deve poter vedere che quella voce gli
#     offre meno. Il TLDR resta obbligatorio per reference/.
#   - I file inbox si leggono attraverso `inbox.sh parse`, MAI con regex proprie:
#     da li' arrivano marker, TLDR (riga 4) e titolo insieme. `doc_tldr` diretto
#     sulla riga 3 resta per i soli file di reference/.
#   - Gli inbox con `branch:` vanno in una sezione PER BRANCH, dopo quella di
#     prod, fra loro in ordine alfabetico: la precedenza e' qualificata dal
#     branch, quindi varia da voce a voce e un'intestazione collettiva direbbe
#     che una condizione esiste senza dire quale ti riguarda.
#   - Le sezioni si emettono SOLO se contengono almeno un file indicizzabile:
#     una regola di precedenza che sopravvive a un'inbox vuota drifterebbe da sola.
#
# Il cap del TLDR viene da lib-doc.sh (sede unica). I TLDR oltre il cap sono una
# violazione BLOCCANTE: l'indice viene scritto comunque, ma lo script esce 2.
#
# Exit (famiglia generatore):
#   0  indice scritto, nessuna violazione
#   1  errore duro: indice NON scritto (dir inesistente, argomento ignoto)
#   2  indice scritto, uno o piu' TLDR oltre il cap
#
# Env: PROJECT_ROOT (default: auto-detect)
# =============================================================================

set -euo pipefail

DIR=""
INBOX_DIR=""
OUTPUT=""
TITLE="Reference Index"
EXCLUDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)       DIR="$2"; shift 2 ;;
        --inbox)     INBOX_DIR="$2"; shift 2 ;;
        --docs-root) LOOM_DOCS_ROOT="$2"; shift 2 ;;
        --output)    OUTPUT="$2"; shift 2 ;;
        --title)     TITLE="$2"; shift 2 ;;
        --exclude)   EXCLUDE="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"
# shellcheck source=lib-doc.sh
source "${SCRIPT_DIR}/lib-doc.sh"

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

# --- Raccolta reference/ --------------------------------------------------------
# Temp: "<reldir>|<filename>|<tldr>"
TMP="$(mktemp)"
INBOX_TMP="$(mktemp)"       # "<branch>|<filename>|<voce>" — branch vuoto = prod
trap 'rm -f "$TMP" "$INBOX_TMP"' EXIT

MISSING=0
OVERCAP=0

while IFS= read -r -d '' file; do
    [[ "$(basename "$file")" == "INDEX.md" ]] && continue
    should_exclude "$file" && continue

    tldr="$(doc_tldr "$file" 3)"
    if [[ -z "$tldr" ]]; then
        echo "[build-index] WARN no TLDR: ${file#"$PROJECT_ROOT"/}" >&2
        MISSING=$((MISSING+1))
        continue
    fi

    if (( ${#tldr} > LW_DOC_TLDR_CAP )); then
        echo "[build-index] OVER-CAP TLDR ${#tldr} char (cap ${LW_DOC_TLDR_CAP}): ${file#"$PROJECT_ROOT"/}" >&2
        OVERCAP=$((OVERCAP+1))
    fi

    rel="${file#"$SCAN_DIR"/}"
    reldir="$(dirname "$rel")"
    fname="$(basename "$rel")"
    [[ "$reldir" == "." ]] && reldir=""

    # Nessun escape di `|`: l'output e' a liste, e `read` assegna all'ultima
    # variabile il resto della riga separatori inclusi → il TLDR arriva intatto.
    echo "${reldir}|${fname}|${tldr}" >> "$TMP"
done < <(find "$SCAN_DIR" -type f -name '*.md' -print0 | sort -z)

# --- Raccolta inbox (via inbox.sh parse) ----------------------------------------
# Indicizzabile = natura nozioni + token indexed. Voce = TLDR se c'e', altrimenti
# il titolo in corsivo. Il branch decide la sezione.
if [[ -d "$INBOX_SCAN_DIR" && "$INBOX_SCAN_DIR" != "$SCAN_DIR" ]]; then
    while IFS= read -r -d '' file; do
        parse_out="$("${SCRIPT_DIR}/inbox.sh" parse --file "$file" --format tsv 2>/dev/null)" && parse_rc=0 || parse_rc=$?
        if [[ $parse_rc -eq 2 ]]; then
            echo "[build-index] WARN malformato, escluso: ${file#"$PROJECT_ROOT"/}" >&2
            continue
        elif [[ $parse_rc -ne 0 ]]; then
            echo "[build-index] WARN parse fallito, escluso: ${file#"$PROJECT_ROOT"/}" >&2
            continue
        fi

        natura=""; indexed=""; branch=""; titolo=""; tldr=""; tldr_len=0
        # tab tradotto in unit separator: con IFS=$'\t' i tab sono whitespace e i
        # campi vuoti in mezzo collassano (un `nozioni · branch:` senza indexed
        # sposterebbe il branch nella colonna sbagliata)
        while IFS=$'\x1f' read -r kind f1 f2 f3 f4 _; do
            case "$kind" in
                TITOLO) titolo="$f1" ;;
                MARKER) natura="$f1"; indexed="$f2"; branch="$f4" ;;
                TLDR)   tldr="$f1"; tldr_len="$f2" ;;
            esac
        done < <(tr '\t' '\037' <<< "$parse_out")

        [[ "$natura" == "nozioni" && "$indexed" == "indexed" ]] || continue

        if [[ -n "$tldr" ]]; then
            if (( tldr_len > LW_DOC_TLDR_CAP )); then
                echo "[build-index] OVER-CAP TLDR ${tldr_len} char (cap ${LW_DOC_TLDR_CAP}): ${file#"$PROJECT_ROOT"/}" >&2
                OVERCAP=$((OVERCAP+1))
            fi
            voce="$tldr"
        else
            voce="*${titolo}*"
        fi

        echo "${branch}|$(basename "$file")|${voce}" >> "$INBOX_TMP"
    done < <(find "$INBOX_SCAN_DIR" -maxdepth 1 -type f -name '*.md' -print0 | sort -z)
fi

# --- Genera output --------------------------------------------------------------
{
    echo "# ${TITLE}"
    echo ""
    echo "Indice della documentazione offline."
    echo ""

    # `LC_ALL=C sort -t'|' -k1,1` e non `sort`: sotto collazione locale la
    # punteggiatura non pesa al livello primario, quindi il separatore `|` viene
    # ignorato e la sezione `(root)` si riapre a ogni interruzione. Ordinare sul
    # campo, in C, rende l'ordine indipendente dal locale di chi lancia.
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

    if [[ -s "$INBOX_TMP" ]]; then
        # prod prima (branch vuoto ordina in testa con sort -k1,1), poi una
        # sezione per branch in ordine alfabetico
        current_branch="__unset__"
        LC_ALL=C sort -t'|' -k1,1 -k2,2 "$INBOX_TMP" | while IFS='|' read -r branch fname voce; do
            if [[ "$branch" != "$current_branch" ]]; then
                echo ""
                if [[ -z "$branch" ]]; then
                    echo "## inbox — nozioni non ancora collocate"
                    echo ""
                    echo "> Precedenza: in caso di contraddizione con un file di \`reference/\`, **prevale la voce inbox** — descrive un rilascio che la doc consolidata non ha ancora assorbito."
                else
                    echo "## inbox — branch \`${branch}\`"
                    echo ""
                    echo "> As-is di uno sviluppo, non di prod: vale **solo lavorando su \`${branch}\`**, e per chi sta su prod non ha nessuna precedenza sulla doc consolidata."
                fi
                echo ""
                current_branch="$branch"
            fi
            echo "- \`${fname}\` — ${voce}"
        done
    fi
} > "$OUTPUT_FILE"

echo "[build-index] wrote: ${OUTPUT_FILE#"$PROJECT_ROOT"/}"
[[ $MISSING -gt 0 ]] && echo "[build-index] ${MISSING} file(s) skipped (no TLDR)" >&2

if (( OVERCAP > 0 )); then
    echo "[build-index] FAIL: ${OVERCAP} TLDR oltre il cap ${LW_DOC_TLDR_CAP} — riscrivili come ancora (contratto doc)" >&2
    exit 2
fi
exit 0
