#!/usr/bin/env bash

# =============================================================================
# doc-partition.sh — partizione deterministica dei perimetri per il fan-out
# Usage: doc-partition.sh [--docs-root <name>] [--dir <path>] [--max-groups N]
#                        [--max-char N] [--prefix <base>] [--split-threshold N]
#                        [--merge-threshold N] [--tldr-cap N]
#                        [--format text|tsv]
# =============================================================================
#
# Consuma le misure di doc-metrics.sh e ne ricava i GRUPPI da dare a doc-auditor,
# uno per Task in fan-out. Il criterio e' fisso, non un giudizio del chiamante:
#
#   1. ogni file sopra soglia di split fa gruppo DA SOLO — e' il lavoro piu' pesante
#      (il taglio va proposto per perimetro) e un file e' atomico: non si spezza
#      fra due auditor nemmeno se sfora il tetto di peso
#   2. il resto si raggruppa PER CARTELLA: la cartella e' gia' un perimetro di
#      ricerca, chi cerca in reference/ non cerca in project/
#   3. i gruppi-cartella piu' LEGGERI si fondono finche' stanno nel cap di gruppi,
#      ma mai oltre il tetto di peso
#   4. un gruppo-cartella oltre il tetto di peso si spezza in chunk contigui
#
# DUE cap, che rispondono a due vincoli diversi e vanno tenuti distinti:
#
#   --max-groups (4)     quanti auditor per ONDATA. Il limite non e' il parallelismo,
#                        e' il registro: oltre 4 registri diventa illeggibile e il
#                        gate dei verdetti impraticabile.
#   --max-char (60000)   quanta doc legge UN auditor. Senza, "un gruppo per cartella"
#                        degenera: su un repo reale una reference/ da 23 file mette
#                        184.000 char in un solo perimetro e 289 in un altro — un
#                        auditor che legge mezzo repo audita peggio di quattro che
#                        ne leggono un quarto ciascuno.
#
# ONDATE: i due cap possono non chiudersi insieme (molti file sopra soglia, o una
# cartella grossa). Allora si emettono TUTTI i gruppi con la colonna WAVE gia'
# calcolata (<max-groups> gruppi per ondata) e `over-cap: si`. Il chiamante esegue
# un'ondata per messaggio. Mai un troncamento silenzioso.
#
# INDEX.md (flag GEN) e' escluso: e' un artefatto rigenerato, non si audita.
#
# Env: PROJECT_ROOT, LOOM_DOCS_ROOT — stessi di doc-metrics.sh
# Exit: 0 = partizione emessa · 1 = doc-metrics.sh fallito · 2 = argomento ignoto
# =============================================================================

set -uo pipefail

MAX_GROUPS=4
MAX_CHAR=60000
PREFIX_BASE="LINT"
FORMAT="text"
PASS_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --max-groups)       MAX_GROUPS="$2"; shift 2 ;;
        --max-char)         MAX_CHAR="$2"; shift 2 ;;
        --prefix)           PREFIX_BASE="$2"; shift 2 ;;
        --format)           FORMAT="$2"; shift 2 ;;
        --docs-root)        PASS_ARGS+=(--docs-root "$2"); shift 2 ;;
        --dir)              PASS_ARGS+=(--dir "$2"); shift 2 ;;
        --split-threshold)  PASS_ARGS+=(--split-threshold "$2"); shift 2 ;;
        --merge-threshold)  PASS_ARGS+=(--merge-threshold "$2"); shift 2 ;;
        --tldr-cap)         PASS_ARGS+=(--tldr-cap "$2"); shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

[[ "$MAX_GROUPS" =~ ^[1-9][0-9]*$ ]] || { echo "[doc-partition] ERROR: --max-groups non valido: $MAX_GROUPS" >&2; exit 2; }
[[ "$MAX_CHAR"   =~ ^[1-9][0-9]*$ ]] || { echo "[doc-partition] ERROR: --max-char non valido: $MAX_CHAR" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

METRICS="$("${SCRIPT_DIR}/doc-metrics.sh" ${PASS_ARGS[@]+"${PASS_ARGS[@]}"} --format tsv)" || {
    echo "[doc-partition] ERROR: doc-metrics.sh fallito" >&2; exit 1; }

# --- Ingestione misure --------------------------------------------------------
# NB: gli array si assegnano vuoti esplicitamente (`X=()`), non solo dichiarati.
# Sotto `set -u` bash 5.3 tratta ancora un array solo DICHIARATO come non assegnato:
# `${#X[@]}` aborta. Costa una riga ed evita un fallimento che si presenta solo sul
# caso limite (zero file sopra soglia), cioe' proprio su una doc gia' bonificata.
P=(); C=(); T=(); F=()
while IFS=$'\t' read -r p c t f; do
    [[ -z "$p" || "$p" == "PATH" ]] && continue
    [[ " $f " == *" GEN "* ]] && continue      # artefatto generato: mai auditato
    P+=("$p"); C+=("$c"); T+=("$t"); F+=("$f")
done <<< "$METRICS"

if [[ ${#P[@]} -eq 0 ]]; then
    echo "[doc-partition] nessun file doc da partizionare"
    echo "GROUPS: 0  ·  file: 0  ·  over-cap: no"
    exit 0
fi

# --- 1. Gruppi split: un file ciascuno, atomici -------------------------------
SG_IDX=(); SG_CHAR=(); SG_NAME=()
declare -A DIR_IDX DIR_CHAR
DIR_IDX=(); DIR_CHAR=()

for i in "${!P[@]}"; do
    if [[ " ${F[$i]} " == *" SPLIT "* ]]; then
        SG_IDX+=("$i ")
        SG_CHAR+=("${C[$i]}")
        SG_NAME+=("$(basename "${P[$i]}" .md)")
    else
        d="$(dirname "${P[$i]}")"
        DIR_IDX["$d"]="${DIR_IDX[$d]:-}$i "
        DIR_CHAR["$d"]=$(( ${DIR_CHAR[$d]:-0} + ${C[$i]} ))
    fi
done

# --- 2. Gruppi cartella, ordinati per peso decrescente ------------------------
DG_IDX=(); DG_CHAR=(); DG_DIRS=()
if [[ ${#DIR_CHAR[@]} -gt 0 ]]; then
    while IFS=$'\t' read -r ch d; do
        DG_IDX+=("${DIR_IDX[$d]}")
        DG_CHAR+=("$ch")
        DG_DIRS+=("$d")
    done < <(for d in "${!DIR_CHAR[@]}"; do printf '%s\t%s\n' "${DIR_CHAR[$d]}" "$d"; done \
             | sort -t$'\t' -k1,1nr -k2,2)
fi

dg_resort() {  # riordina i gruppi-cartella per peso desc, dopo una fusione
    (( ${#DG_IDX[@]} > 1 )) || return 0
    local -a _order _i _c _d
    mapfile -t _order < <(for k in "${!DG_CHAR[@]}"; do printf '%s\t%s\n' "${DG_CHAR[$k]}" "$k"; done \
                          | sort -t$'\t' -k1,1nr -k2,2n | cut -f2)
    _i=(); _c=(); _d=()
    for k in "${_order[@]}"; do _i+=("${DG_IDX[$k]}"); _c+=("${DG_CHAR[$k]}"); _d+=("${DG_DIRS[$k]}"); done
    DG_IDX=("${_i[@]}"); DG_CHAR=("${_c[@]}"); DG_DIRS=("${_d[@]}")
}

# --- 3. Fusione dei gruppi-cartella piu' leggeri, entro il tetto di peso -------
# Il conto da confrontare col cap e' quello EFFETTIVO, non il numero di cartelle:
# una cartella oltre il tetto di peso diventera' N chunk al passo 4. Contarla come
# 1 lascerebbe in piedi gruppi da 289 char accanto a una reference/ che si spezza
# in quattro — cioe' fonderebbe troppo poco proprio quando i gruppi sono gia' tanti.
n_split=${#SG_IDX[@]}

effective_groups() {
    local n="$n_split" k
    for k in "${!DG_CHAR[@]}"; do
        n=$(( n + (DG_CHAR[k] + MAX_CHAR - 1) / MAX_CHAR ))
    done
    echo "$n"
}

while (( ${#DG_IDX[@]} > 1 && $(effective_groups) > MAX_GROUPS )); do
    last=$(( ${#DG_IDX[@]} - 1 ))
    prev=$(( last - 1 ))
    # I due piu' leggeri sono in coda (lista ordinata desc). Se la loro somma sfora
    # il tetto di peso la fusione si ferma: meglio un gruppo in piu' (che il chiamante
    # esegue in un'ondata successiva) di un perimetro che nessun auditor legge bene.
    (( DG_CHAR[prev] + DG_CHAR[last] > MAX_CHAR )) && break
    DG_IDX[$prev]="${DG_IDX[$prev]}${DG_IDX[$last]}"
    DG_CHAR[$prev]=$(( DG_CHAR[prev] + DG_CHAR[last] ))
    DG_DIRS[$prev]="${DG_DIRS[$prev]} ${DG_DIRS[$last]}"
    unset 'DG_IDX[last]' 'DG_CHAR[last]' 'DG_DIRS[last]'
    dg_resort
done

# --- Nomi di gruppo (prefisso ID dei finding) ---------------------------------
# Split: token del basename accorpati finche' stanno in 16 char.
# Cartella: basename delle cartelle, max 2, altrimenti MISC.
# Collisione -> suffisso col numero di gruppo: l'ordine e' deterministico.

name_from_basename() {  # <basename>
    local base="$1" out="" tok cand
    local -a toks
    IFS='-' read -ra toks <<< "$base"
    for tok in "${toks[@]}"; do
        cand="${out:+$out-}$tok"
        (( ${#cand} > 16 )) && break
        out="$cand"
    done
    [[ -z "$out" ]] && out="${base:0:16}"
    tr '[:lower:]' '[:upper:]' <<< "$out" | tr -c 'A-Z0-9-\n' '-'
}

name_from_dirs() {  # "<dir> [<dir>...]"
    local -a names=()
    local d joined
    for d in $1; do names+=("$(basename "$d")"); done
    if (( ${#names[@]} > 2 )); then
        echo "MISC"
    else
        joined="$(IFS='-'; echo "${names[*]}")"
        tr '[:lower:]' '[:upper:]' <<< "$joined" | tr -c 'A-Z0-9-\n' '-'
    fi
}

G_IDX=(); G_CHAR=(); G_PREFIX=(); G_REASON=()
declare -A SEEN_NAME
SEEN_NAME=()

add_group() {  # <idx-list> <char> <name> <reason>
    local nm="${3%-}"
    if [[ -n "${SEEN_NAME[$nm]:-}" ]]; then
        nm="${nm}-$(( ${#G_IDX[@]} + 1 ))"
    fi
    SEEN_NAME["$nm"]=1
    G_IDX+=("$1"); G_CHAR+=("$2")
    G_PREFIX+=("${PREFIX_BASE}-${nm}")
    G_REASON+=("$4")
}

for k in "${!SG_IDX[@]}"; do
    add_group "${SG_IDX[$k]}" "${SG_CHAR[$k]}" \
              "$(name_from_basename "${SG_NAME[$k]}")" "sopra soglia split"
done

# --- 4. Chunk dei gruppi-cartella oltre il tetto di peso ----------------------
for k in "${!DG_IDX[@]}"; do
    dirs="${DG_DIRS[$k]}"
    n_dirs=$(wc -w <<< "$dirs")
    if (( n_dirs > 1 )); then label="cartelle accorpate (${dirs})"; else label="cartella ${dirs}"; fi
    base_name="$(name_from_dirs "$dirs")"

    if (( DG_CHAR[k] <= MAX_CHAR )); then
        add_group "${DG_IDX[$k]}" "${DG_CHAR[$k]}" "$base_name" "$label"
        continue
    fi

    # Chunk contigui: la lista e' gia' ordinata per peso desc (viene da doc-metrics),
    # quindi il riempimento greedy da' chunk di peso confrontabile senza bin-packing.
    n_chunks=$(( (DG_CHAR[k] + MAX_CHAR - 1) / MAX_CHAR ))
    chunk=""; chunk_char=0; chunk_n=1
    for i in ${DG_IDX[$k]}; do
        if (( chunk_char > 0 && chunk_char + C[i] > MAX_CHAR )); then
            add_group "$chunk" "$chunk_char" "${base_name%-}-${chunk_n}" \
                      "${label} — chunk ${chunk_n}/${n_chunks}"
            chunk=""; chunk_char=0; chunk_n=$(( chunk_n + 1 ))
        fi
        chunk="${chunk}${i} "; chunk_char=$(( chunk_char + C[i] ))
    done
    [[ -n "$chunk" ]] && add_group "$chunk" "$chunk_char" "${base_name%-}-${chunk_n}" \
                                   "${label} — chunk ${chunk_n}/${n_chunks}"
done

# --- Output -------------------------------------------------------------------
n_groups=${#G_IDX[@]}
n_waves=$(( (n_groups + MAX_GROUPS - 1) / MAX_GROUPS ))
over_cap="no"; (( n_groups > MAX_GROUPS )) && over_cap="si"

if [[ "$FORMAT" == "tsv" ]]; then
    printf 'WAVE\tGROUP\tPREFIX\tREASON\tPATH\tCHAR\tTLDR\tFLAGS\n'
    for g in "${!G_IDX[@]}"; do
        wave=$(( g / MAX_GROUPS + 1 ))
        for i in ${G_IDX[$g]}; do
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$wave" "$((g+1))" "${G_PREFIX[$g]}" "${G_REASON[$g]}" \
                "${P[$i]}" "${C[$i]}" "${T[$i]}" "${F[$i]}"
        done
    done
else
    echo "[doc-partition] gruppi: ${n_groups}  ·  file: ${#P[@]}  ·  cap ${MAX_GROUPS} gruppi / ${MAX_CHAR} char  ·  over-cap: ${over_cap}"
    (( n_waves > 1 )) && echo "  → ${n_waves} ondate da max ${MAX_GROUPS} gruppi: un'ondata per messaggio, il registro si consolida alla fine."
    echo
    for g in "${!G_IDX[@]}"; do
        wave=$(( g / MAX_GROUPS + 1 ))
        n_files=$(wc -w <<< "${G_IDX[$g]}")
        printf 'GROUP %d  [wave %d]  %s  ·  %s file  ·  %s char  ·  %s\n' \
            "$((g+1))" "$wave" "${G_PREFIX[$g]}" "$n_files" "${G_CHAR[$g]}" "${G_REASON[$g]}"
        for i in ${G_IDX[$g]}; do
            printf '    %-58s %8s  %s\n' "${P[$i]}" "${C[$i]}" "${F[$i]}"
        done
        echo
    done
fi

exit 0
