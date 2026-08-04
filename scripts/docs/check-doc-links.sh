#!/usr/bin/env bash

# =============================================================================
# check-doc-links.sh — riferimenti appesi nella doc: file spariti e § inesistenti
# Usage: check-doc-links.sh [--docs-root <name>] [--dir <path>] [--also <path>]...
#                          [--format text|tsv]
# =============================================================================
#
# Enumera OGNI riferimento a un file .md dentro la doc (piu' CLAUDE.md) e lo verifica
# su due livelli:
#
#   DANGLING   il file puntato non esiste
#   NOSECTION  il file esiste, ma la sezione citata con § non c'e'
#
# Il secondo livello e' il motivo per cui questo non e' un `grep <vecchio-path>`:
# dopo uno split i riferimenti si aggiustano a mano, e una § che non esiste piu' e'
# drift NUOVO, prodotto dalla bonifica stessa — invisibile a un grep sul path, che
# dopo la riscrittura risulta pulito.
#
# Cosa NON fa: non decide a quale frammento vada rimappato un riferimento. Quello lo
# sa solo chi ha fatto lo split, e viaggia nel blocco SPLIT_MAP che doc-writer ritorna.
# Qui si enumera, li' si mappa.
#
# Risoluzione di un path: prima relativo alla cartella del file che lo cita, poi
# relativo a project root — la doc usa entrambe le forme. Ignorati: URL e path che
# contengono un'interpolazione (`${CLAUDE_PLUGIN_ROOT}/...`), che non sono
# riferimenti risolvibili staticamente.
#
# Scansionati: {docs_root}/**/*.md (esclusi tasks/ e current-task.md, che sono
# runtime) + CLAUDE.md. `--also <file|dir>` aggiunge perimetri (es. i SKILL.md di un
# plugin che citano path di progetto), ripetibile.
#
# Env: PROJECT_ROOT, LOOM_DOCS_ROOT
# Exit: 0 = nessun riferimento appeso · 2 = VERDETTO (ce ne sono, elencati)
#       1 = errore duro (cartella doc assente)
# =============================================================================

set -uo pipefail

DIR=""
FORMAT="text"
ALSO=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --docs-root) LOOM_DOCS_ROOT="$2"; export LOOM_DOCS_ROOT; shift 2 ;;
        --dir)       DIR="$2"; shift 2 ;;
        --also)      ALSO+=("$2"); shift 2 ;;
        --format)    FORMAT="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"

PROJECT_ROOT="$(lw_find_project_root)"
[[ -z "$DIR" ]] && DIR="${PROJECT_ROOT}/$(lw_docs_root)"
[[ "$DIR" != /* ]] && DIR="${PROJECT_ROOT}/${DIR}"
[[ -d "$DIR" ]] || { echo "[doc-links] ERROR: dir not found: $DIR" >&2; exit 1; }

# --- Perimetro di scansione ---------------------------------------------------
FILES=()
while IFS= read -r -d '' f; do
    rel="${f#"$PROJECT_ROOT"/}"
    # tasks/ e current-task.md sono runtime; INDEX.md e' generato — i suoi riferimenti
    # sono copie dei TLDR, gia' verificati nel file d'origine: segnalarli li raddoppia.
    case "$rel" in */tasks/*|*/current-task.md|*/INDEX.md) continue ;; esac
    FILES+=("$f")
done < <(find "$DIR" -type f -name '*.md' -print0 | sort -z)

[[ -f "${PROJECT_ROOT}/CLAUDE.md" ]] && FILES+=("${PROJECT_ROOT}/CLAUDE.md")

for extra in ${ALSO[@]+"${ALSO[@]}"}; do
    [[ "$extra" != /* ]] && extra="${PROJECT_ROOT}/${extra}"
    if [[ -d "$extra" ]]; then
        while IFS= read -r -d '' f; do FILES+=("$f"); done \
            < <(find "$extra" -type f -name '*.md' -print0 | sort -z)
    elif [[ -f "$extra" ]]; then
        FILES+=("$extra")
    fi
done

[[ ${#FILES[@]} -gt 0 ]] || { echo "[doc-links] nessun file da scansionare"; exit 0; }

# --- Scansione ----------------------------------------------------------------
REPORT="$(awk -v ROOT="$PROJECT_ROOT" '
function normpath(p,   n, parts, out, i, k) {
    n = split(p, parts, "/")
    k = 0
    for (i = 1; i <= n; i++) {
        if (parts[i] == "" && i > 1) continue
        if (parts[i] == ".") continue
        if (parts[i] == ".." && k > 0 && out[k] != "..") { k--; continue }
        out[++k] = parts[i]
    }
    p = out[1]
    for (i = 2; i <= k; i++) p = p "/" out[i]
    return p
}
function exists(f,   r, junk) {
    if (f in EX) return EX[f]
    r = (getline junk < f)
    close(f)
    EX[f] = (r >= 0) ? 1 : 0
    return EX[f]
}
# normalizza un titolo/una § per il confronto: minuscolo, via marcatori inline
# (backtick, asterischi, virgolette) e spazi collassati. I marcatori si tolgono
# OVUNQUE, non solo in coda: un heading "`ctrl`: quali combo" viene citato come
# "§CTRL" senza backtick, e il confronto fallirebbe su un carattere di markup.
function norm(s) {
    s = tolower(s)
    gsub(/[`*_"]/, "", s)
    gsub(/^[ \t#]+/, "", s)
    gsub(/[ \t]+/, " ", s)
    gsub(/^[ \t]+|[ \t.,;:)]+$/, "", s)
    return s
}
# Dove finisce il testo di una §. Non ha delimitatore di chiusura: "§Rollup di stato),
# non un canale separato" cita un heading e prosegue in prosa. Si taglia al primo
# terminatore, e il confronto per PREFISSO (nei due versi) assorbe l errore residuo —
# tagliare troppo presto resta un match, tagliare troppo tardi no.
function cut_section(s,   i, best, cands, n, j, pos) {
    n = split(") ( , ; :", cands, " ")
    best = length(s) + 1
    for (j = 1; j <= n; j++) {
        pos = index(s, cands[j])
        if (pos > 0 && pos < best) best = pos
    }
    if (match(s, /\.($| )/))   { if (RSTART < best) best = RSTART }
    if (match(s, / [-—–] /))   { if (RSTART < best) best = RSTART }
    return substr(s, 1, best - 1)
}
function load_heads(f,   line, n) {
    if (f in NH) return
    n = 0
    while ((getline line < f) > 0) {
        if (line ~ /^#+[ \t]/)
            H[f, ++n] = norm(line)
        # Anche i titoletti in grassetto a inizio riga contano come sezione: il
        # contratto doc prescrive "H2 da una riga -> **Titolo.** testo", quindi una §
        # puo legittimamente puntare a uno di quelli. Senza, la convenzione del
        # contratto produrrebbe un finding a ogni citazione.
        else if (match(line, /^\*\*[^*]+\*\*/))
            H[f, ++n] = norm(substr(line, RSTART + 2, RLENGTH - 4))
    }
    close(f)
    NH[f] = n
}
function section_ok(f, sec,   i, h, s) {
    load_heads(f)
    s = norm(sec)
    if (length(s) < 3) return 1
    for (i = 1; i <= NH[f]; i++) {
        h = H[f, i]
        if (length(h) < 3) continue
        if (substr(s, 1, length(h)) == h) return 1
        if (substr(h, 1, length(s)) == s) return 1
    }
    return 0
}
function heads_hint(f,   i, out, h) {
    out = ""
    for (i = 2; i <= NH[f] && i <= 5; i++) {          # da 2: la 1 e il titolo del file
        h = H[f, i]
        if (length(h) > 38) h = substr(h, 1, 38) "…"
        out = out (out == "" ? "" : " · ") h
    }
    if (NH[f] > 5) out = out " · (+" (NH[f] - 5) ")"
    return out
}
FNR == 1 { dir = FILENAME; sub(/\/[^\/]*$/, "", dir) }
{
    rest = $0; before = ""
    while (match(rest, /[A-Za-z0-9_.@\/-]*\.md/)) {
        tok  = substr(rest, RSTART, RLENGTH)
        before = before substr(rest, 1, RSTART - 1)
        tail = substr(rest, RSTART + RLENGTH)

        skip = 0
        if (before ~ /https?:\/\/[^ )]*$/) skip = 1        # URL
        if (before ~ /[}$]$/)              skip = 1        # ${VAR}/path.md
        if (length(tok) < 4)               skip = 1
        # Un basename NUDO (tasks.md, SKILL.md) e una MENZIONE, non un riferimento:
        # la prosa nomina un file per concetto, senza dire dove sta, e verificarlo
        # come path produce solo rumore. Riferimento = almeno una barra nel token.
        if (tok !~ /\//)                   skip = 1

        if (!skip) {
            # Un path si prova prima relativo al file che lo cita, poi a project root:
            # la doc usa entrambe le forme. Se nessuna delle due esiste, si RIPORTA
            # quella che l autore intendeva — dir-relativa se il token inizia per '.',
            # altrimenti root-relativa — o il messaggio manda a cercare nel posto sbagliato.
            p = tok; sub(/^@/, "", p)
            if (p ~ /^\//)                        abs = normpath(p)
            else if (exists(normpath(dir "/" p))) abs = normpath(dir "/" p)
            else if (p ~ /^\./)                   abs = normpath(dir "/" p)
            else                                  abs = normpath(ROOT "/" p)

            rel = abs; sub("^" ROOT "/", "", rel)
            src = FILENAME; sub("^" ROOT "/", "", src)

            sec = ""
            ipos = index(tail, "§")
            if (ipos > 0) {
                gap = substr(tail, 1, ipos - 1)
                if (gap ~ /^[`)\],. ]*$/ && length(gap) <= 3)
                    sec = cut_section(substr(tail, ipos + length("§")))
            }

            if (rel ~ /(^|\/)tasks\//) { before = before tok; rest = tail; continue }

            total++
            if (!exists(abs))
                printf "DANGLING\t%s\t%d\t%s\t%s\n", src, FNR, rel, sec
            else if (sec != "" && !section_ok(abs, sec))
                printf "NOSECTION\t%s\t%d\t%s\t%s\t%s\n", src, FNR, rel, sec, heads_hint(abs)
            else
                ok++
        }
        before = before tok
        rest = tail
    }
}
END { printf "SUMMARY\t%d\t%d\n", total, ok }
' "${FILES[@]}")"

# --- Output -------------------------------------------------------------------
summary="$(grep -P '^SUMMARY\t' <<< "$REPORT" | tail -1)"
total="$(cut -f2 <<< "$summary")"; ok="$(cut -f3 <<< "$summary")"
problems="$(grep -Pv '^SUMMARY\t' <<< "$REPORT" | grep -c . )"
n_dangling="$(grep -cP '^DANGLING\t' <<< "$REPORT")"
n_nosection="$(grep -cP '^NOSECTION\t' <<< "$REPORT")"

if [[ "$FORMAT" == "tsv" ]]; then
    printf 'STATUS\tFROM\tLINE\tTARGET\tSECTION\tHEADINGS\n'
    grep -Pv '^SUMMARY\t' <<< "$REPORT"
else
    echo "[doc-links] file: ${#FILES[@]}  ·  riferimenti: ${total:-0}  ·  ok: ${ok:-0}  ·  appesi: ${n_dangling} file + ${n_nosection} sezioni"
    echo
    while IFS=$'\t' read -r st from line target sec hint; do
        [[ -z "$st" ]] && continue
        if [[ "$st" == "DANGLING" ]]; then
            printf 'DANGLING   %s:%s\n             → %s%s\n' "$from" "$line" "$target" "${sec:+ §$sec}"
        else
            printf 'NOSECTION  %s:%s\n             → %s §%s\n             heading presenti: %s\n' \
                "$from" "$line" "$target" "$sec" "$hint"
        fi
    done < <(grep -Pv '^SUMMARY\t' <<< "$REPORT")
fi

(( problems > 0 )) && exit 2
exit 0
