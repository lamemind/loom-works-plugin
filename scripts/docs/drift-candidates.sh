#!/usr/bin/env bash

# =============================================================================
# drift-candidates.sh — quali file doc citano i path che hai appena toccato
# Usage: drift-candidates.sh [--docs-root <name>] [--format text|tsv] <path>...
#        <path>... da stdin se non passati come argomenti (uno per riga)
# =============================================================================
#
# Rilevamento MECCANICO della sentinella di drift: un file doc che nomina un
# sorgente appena modificato è candidato a essere diventato falso. È un grep,
# quindi non chiede all'umano di ricordarsene — ed è precisamente il suo limite:
# un comportamento cambiato senza che nessun nome cambi non produce nessun
# candidato. Per quello resta la sentinella manuale, che il chiamante mette a
# mano.
#
# I PATH LI PASSA IL CHIAMANTE, non li deduce lo script da un `git diff`. In
# detached il working tree porta anche i file delle altre sessioni, e un diff
# letto qui li rastrellerebbe dentro: la lista dei path toccati la conosce solo
# chi ha lavorato.
#
# PERIMETRO DI RICERCA: tutta la docs-root tranne `tasks/` e `tasks.md` (record
# datati, non doc), `inbox/` (nozioni non ancora collocate: non possono driftare,
# non sono ancora atterrate da nessuna parte), `INDEX.md` (rigenerato, mai
# corretto a mano) e `current-task.md` (symlink). Copre quindi sia `reference/`
# (offline) sia i file di progetto @-importati (online), dove il drift costa a
# ogni sessione invece che a ogni apertura.
#
# TOKEN DI RICERCA, due per path toccato — la doc cita un sorgente col nome, non
# col path da repo root:
#   strong  `<parent>/<basename>`, o il solo `<parent>` quando il basename è
#           un nome-indice (SKILL.md, index.ts, __init__.py, …) che da solo
#           matcherebbe qualunque cosa
#   weak    `<basename>` nudo, saltato sui nomi-indice per la stessa ragione
# Un match weak non è meno vero, è meno specifico: `lib.sh` compare in doc che
# parlano di altri `lib.sh`. La colonna sta lì per far triare il chiamante, non
# per filtrare al suo posto.
#
# Env: PROJECT_ROOT (default: auto-detect), LOOM_DOCS_ROOT (default: docs)
# Exit: 0 sempre, candidati o no — è una misura. Chi decide è il chiamante.
# =============================================================================

set -uo pipefail

DOCS_ROOT_ARG=""
FORMAT="text"
PATHS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --docs-root) DOCS_ROOT_ARG="$2"; shift 2 ;;
        --format)    FORMAT="$2"; shift 2 ;;
        -*)          echo "unknown arg: $1" >&2; exit 2 ;;
        *)           PATHS+=("$1"); shift ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"

PROJECT_ROOT="$(lw_find_project_root)"
[[ -n "$DOCS_ROOT_ARG" ]] && LOOM_DOCS_ROOT="$DOCS_ROOT_ARG"
DOCS_ROOT="$(lw_docs_root)"
DOCS_DIR="${PROJECT_ROOT}/${DOCS_ROOT}"

if [[ ${#PATHS[@]} -eq 0 ]] && [[ ! -t 0 ]]; then
    while IFS= read -r line; do
        [[ -n "$line" ]] && PATHS+=("$line")
    done
fi

if [[ ${#PATHS[@]} -eq 0 ]]; then
    echo "[drift-candidates] nessun path in ingresso — niente da misurare" >&2
    exit 0
fi

[[ -d "$DOCS_DIR" ]] || { echo "[drift-candidates] docs-root assente: $DOCS_DIR" >&2; exit 0; }

# Nomi che identificano il modulo attraverso la cartella, non attraverso se stessi.
is_index_name() {
    case "$1" in
        SKILL.md|README.md|CLAUDE.md|index.ts|index.tsx|index.js|index.jsx|\
        __init__.py|mod.rs|lib.rs|main.rs|package.json|Makefile) return 0 ;;
        *) return 1 ;;
    esac
}

DOC_FILES=()
while IFS= read -r -d '' f; do DOC_FILES+=("$f"); done < <(
    find "$DOCS_DIR" -type f -name '*.md' \
        -not -path "${DOCS_DIR}/tasks/*" \
        -not -path "${DOCS_DIR}/inbox/*" \
        -not -name 'current-task.md' \
        -not -name 'tasks.md' \
        -not -name 'INDEX.md' -print0 | sort -z)

[[ ${#DOC_FILES[@]} -gt 0 ]] || { echo "[drift-candidates] nessun file doc nel perimetro" >&2; exit 0; }

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

for p in "${PATHS[@]}"; do
    rel="${p#"$PROJECT_ROOT"/}"
    rel="${rel#./}"
    base="$(basename "$rel")"
    parent="$(basename "$(dirname "$rel")")"

    tokens=()
    if is_index_name "$base"; then
        [[ "$parent" != "." && -n "$parent" ]] && tokens+=("strong:${parent}")
    else
        [[ "$parent" != "." && -n "$parent" ]] && tokens+=("strong:${parent}/${base}")
        tokens+=("weak:${base}")
        # Lo stem: la doc cita `doc-router`, non `doc-router.md`. Sotto i 4 char
        # aggancia prose intere (`lib`, `cli`), quindi non si emette.
        stem="${base%.*}"
        [[ "$stem" != "$base" && ${#stem} -ge 4 ]] && tokens+=("weak:${stem}")
    fi

    for tok in "${tokens[@]}"; do
        strength="${tok%%:*}"
        needle="${tok#*:}"
        while IFS= read -r doc; do
            [[ -n "$doc" ]] || continue
            printf '%s\t%s\t%s\t%s\n' "${doc#"$PROJECT_ROOT"/}" "$strength" "$needle" "$rel" >> "$TMP"
        done < <(grep -lF -e "$needle" -- "${DOC_FILES[@]}" 2>/dev/null)
    done
done

# Un doc che matcha strong e weak sullo stesso path resta una riga sola: vince strong.
DEDUP="$(sort -t$'\t' -k1,1 -k2,2 -k4,4 -u "$TMP" \
    | awk -F'\t' '{k=$1 FS $4} !(k in seen) {seen[k]=1; print}')"

n="$(printf '%s' "$DEDUP" | grep -c . || true)"

if [[ "$FORMAT" == "tsv" ]]; then
    printf 'DOC\tSTRENGTH\tTOKEN\tTOUCHED\n'
    [[ -n "$DEDUP" ]] && printf '%s\n' "$DEDUP"
    exit 0
fi

echo "[drift-candidates] docs-root: ${DOCS_ROOT}  ·  path toccati: ${#PATHS[@]}  ·  candidati: ${n}"
echo
if (( n == 0 )); then
    echo "Nessun file doc cita i path toccati."
    echo "→ il grep non vede un comportamento cambiato senza che nessun nome cambi:"
    echo "  se è quel caso, la sentinella va messa a mano."
    exit 0
fi
printf '%-56s %-8s %-28s %s\n' "DOC" "MATCH" "TOKEN" "TOUCHED"
printf '%s\n' "$DEDUP" | while IFS=$'\t' read -r d s t p; do
    printf '%-56s %-8s %-28s %s\n' "$d" "$s" "$t" "$p"
done
echo
echo "→ candidati, non verdetti: apri i doc con match strong prima degli altri."

exit 0
