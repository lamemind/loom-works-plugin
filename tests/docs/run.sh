#!/usr/bin/env bash

# =============================================================================
# tests/docs/run.sh — banco delle primitive bash del sistema doc v2
# Usage: tests/docs/run.sh
# =============================================================================
#
# Un repo git COSTRUITO, non una copia: meta' delle primitive legge git
# (CREATED dal commit di aggiunta, la guardia dal working tree) e un banco su
# cartella nuda misurerebbe solo i rami di fallback. Le fixture si committano
# UNA PER VOLTA con GIT_AUTHOR_DATE/GIT_COMMITTER_DATE forzate — e' cio' che
# rende deterministica ogni misura derivata dall'eta'. L'ordine dei commit e'
# deliberatamente NON alfabetico, o l'asserzione sull'ordine a coda passerebbe
# anche con un sort sul nome.
#
# Le asserzioni sull'eta' non sono MAI sul numero: AGE_DAYS dipende dal giorno
# del run, quindi si asserisce su CREATED (fissato dalla data del commit) e
# sull'ordine delle righe — la colonna AGE_DAYS si taglia prima del diff.
#
# Confronto per diff contro expected/ PIU' exit code catturato a parte: una
# guardia puo' stampare l'elenco giusto e uscire col codice sbagliato, ed e'
# l'errore che i chiamanti poi ereditano.
#
# Su rosso la cartella di lavoro RESTA, col path stampato: una dir cancellata
# e' una diagnosi che ricomincia da zero. Su verde si cancella.
# =============================================================================

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${TESTS_DIR}/../.." && pwd)"
SD="${PLUGIN_ROOT}/scripts/docs"
FX="${TESTS_DIR}/fixtures"
EXP="${TESTS_DIR}/expected"

WORK="$(mktemp -d /tmp/loom-doc-tests.XXXXXX)"
A="${WORK}/proj-a"        # repo curato: metrics / index / links / guard
B="${WORK}/proj-b"        # repo per new + doc vuota
C="${WORK}/proj-c"        # repo con inbox interamente untracked (guard -uall)
D="${WORK}/proj-d"        # repo senza inbox indicizzabile (index)
NG="${WORK}/non-git"      # cartella non-git (guard exit 1)
TMPD="${WORK}/scratch"    # copie fuori repo per parse / marker / registro
OUT="${WORK}/out"         # stdout/stderr catturati
mkdir -p "$A" "$B" "$C" "$D" "${NG}/docs" "$TMPD" "$OUT"

PASS=0; FAIL=0

ok() { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
ko() { FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$1"; [[ -n "${2:-}" ]] && printf '     %s\n' "$2"; }

assert_exit() {  # <name> <atteso> <avuto>
    if [[ "$3" -eq "$2" ]]; then ok "$1"; else ko "$1" "exit atteso $2, avuto $3"; fi
}
assert_diff() {  # <name> <actual> <expected> — i tab di coda (campi TSV vuoti) si
    # normalizzano su entrambi i lati: un expected con whitespace invisibile in coda
    # non sopravvive agli editor, e il dato che conta e' nei campi pieni
    sed 's/\t*$//' "$2" > "${WORK}/norm-actual"
    sed 's/\t*$//' "$3" > "${WORK}/norm-expected"
    if diff -u "${WORK}/norm-expected" "${WORK}/norm-actual" > "${WORK}/last-diff" 2>&1; then ok "$1"
    else ko "$1" "diff (atteso vs avuto):"; sed 's/^/     /' "${WORK}/last-diff"; fi
}
assert_same() {  # <name> <file-a> <file-b> — byte-identici
    if cmp -s "$2" "$3"; then ok "$1"; else ko "$1" "i file differiscono: $2 vs $3"; fi
}
assert_grep() {  # <name> <file> <ERE>
    if grep -qE "$3" "$2"; then ok "$1"; else ko "$1" "pattern atteso assente: $3"; fi
}
assert_absent() {  # <name> <file> <ERE>
    if grep -qE "$3" "$2"; then ko "$1" "pattern presente e non atteso: $3"; else ok "$1"; fi
}
assert_empty() {  # <name> <file>
    if [[ -s "$2" ]]; then ko "$1" "output atteso vuoto, avuto: $(head -3 "$2")"; else ok "$1"; fi
}

mk_repo() { git -C "$1" init -q && git -C "$1" config user.name tester && git -C "$1" config user.email tester@local; }

git_c() {  # <repo> <rel> <epoch> — add + commit a data forzata
    git -C "$1" add -- "$2" && \
    GIT_AUTHOR_DATE="@$3 +0000" GIT_COMMITTER_DATE="@$3 +0000" \
        git -C "$1" commit -qm "add $2"
}

# =============================================================================
# Repo A — costruzione
# =============================================================================
mkdir -p "$A/docs/inbox" "$A/docs/reference"
mk_repo "$A"

echo "# Progetto banco" > "$A/CLAUDE.md"
git_c "$A" CLAUDE.md 1767139200                       # 2025-12-31

cp "$FX"/reference/*.md "$A/docs/reference/"

# grande.md: sopra soglia di split (>15000 char), generato — un file cosi' non
# vale un posto fra le fixture
{
    echo "# Pagina grande"
    echo
    echo "> **TLDR**: fixture sopra la soglia di split — contenuto ripetuto fino a superare il tetto."
    echo
    for i in $(seq 1 160); do
        echo "Riga di riempimento ${i}: testo che esiste solo per superare la soglia di split della misura, senza nessun contenuto informativo."
    done
} > "$A/docs/reference/grande.md"

# tldr-lungo.md: TLDR oltre il cap (>600 char), corpo fra merge e split
{
    echo "# Pagina col TLDR oltre il cap"
    echo
    printf '> **TLDR**: '
    for i in $(seq 1 40); do printf 'perimetro di ricerca ripetuto %s volte per superare il cap del riassunto; ' "$i"; done
    echo
    echo
    for i in $(seq 1 30); do
        echo "Riga di corpo ${i}: contenuto sufficiente a stare sopra il pavimento di merge."
    done
} > "$A/docs/reference/tldr-lungo.md"

for f in normale senza-tldr assumed-knowledge cita citato grande tldr-lungo; do
    git_c "$A" "docs/reference/${f}.md" 1767139200
done

# inbox: ordine dei commit NON alfabetico, epoch crescenti un giorno alla volta
cp "$FX"/inbox/*.md "$A/docs/inbox/"
git_c "$A" docs/inbox/sweep-deck.md            1767225600   # 2026-01-01
git_c "$A" docs/inbox/T121-branch-drainable.md 1767312000   # 2026-01-02
git_c "$A" docs/inbox/T109-cache-anthropic.md  1767398400   # 2026-01-03
git_c "$A" docs/inbox/align-merge-compass.md   1767484800   # 2026-01-04
git_c "$A" docs/inbox/T112-indexed-notldr.md   1767571200   # 2026-01-05
git_c "$A" docs/inbox/T110-miste.md            1767657600   # 2026-01-06
git_c "$A" docs/inbox/T120-branched.md         1767744000   # 2026-01-07
git_c "$A" docs/inbox/malformato-riga4.md      1767830400   # 2026-01-08
git_c "$A" docs/inbox/malformato-assente.md    1767916800   # 2026-01-09
git_c "$A" docs/inbox/T111-router-check.md     1768003200   # 2026-01-10
git_c "$A" docs/inbox/T109-cache-verdetti.md   1768089600   # 2026-01-11
git_c "$A" docs/inbox/T109-cache-completo.md   1768176000   # 2026-01-12

# =============================================================================
# build-index (repo A)
# =============================================================================
PROJECT_ROOT="$A" "$SD/build-index.sh" --docs-root docs \
    > "$OUT/index-a.out" 2> "$OUT/index-a.err"
assert_exit "index: exit 2 con indice scritto (TLDR oltre cap)" 2 $?
[[ -f "$A/docs/reference/INDEX.md" ]] && ok "index: INDEX.md scritto" || ko "index: INDEX.md scritto" "file assente"
assert_grep "index: OVER-CAP segnalato su stderr" "$OUT/index-a.err" 'OVER-CAP.*tldr-lungo'
assert_grep "index: WARN no TLDR su senza-tldr" "$OUT/index-a.err" 'no TLDR.*senza-tldr'
assert_diff "index: INDEX.md conforme all'atteso" "$A/docs/reference/INDEX.md" "$EXP/index-a.md"
git_c "$A" docs/reference/INDEX.md 1768262400

# =============================================================================
# doc-metrics — modo principale (repo A)
# =============================================================================
PROJECT_ROOT="$A" "$SD/doc-metrics.sh" --docs-root docs --format tsv \
    > "$OUT/metrics-main.tsv" 2> "$OUT/metrics-main.err"
assert_exit "metrics: exit 0 modo principale" 0 $?
assert_grep "metrics: SPLIT su grande.md"        "$OUT/metrics-main.tsv" $'grande\\.md\t[0-9]+\t[0-9]+\t.*SPLIT'
assert_grep "metrics: TLDR>CAP su tldr-lungo"    "$OUT/metrics-main.tsv" $'tldr-lungo\\.md\t.*TLDR>CAP'
assert_grep "metrics: NOTLDR su senza-tldr"      "$OUT/metrics-main.tsv" $'senza-tldr\\.md\t.*NOTLDR'
assert_absent "metrics: NESSUN NOTLDR sull'inbox senza TLDR" "$OUT/metrics-main.tsv" $'T112-indexed-notldr\\.md\t.*NOTLDR'
assert_grep "metrics: INBOX su T112-indexed-notldr" "$OUT/metrics-main.tsv" $'T112-indexed-notldr\\.md\t.*INBOX'
assert_grep "metrics: GEN esclusivo su INDEX.md" "$OUT/metrics-main.tsv" $'INDEX\\.md\t[0-9]+\t[0-9]+\tGEN$'
# CONFIG: niente SPLIT/MERGE?, ma TLDR calcolato (colonna > 0)
ak_row="$(grep -P 'assumed-knowledge\.md\t' "$OUT/metrics-main.tsv")"
if [[ "$ak_row" =~ CONFIG ]] && [[ ! "$ak_row" =~ MERGE ]] && [[ ! "$ak_row" =~ SPLIT ]]; then
    ok "metrics: CONFIG senza SPLIT/MERGE? su assumed-knowledge"
else
    ko "metrics: CONFIG senza SPLIT/MERGE? su assumed-knowledge" "riga: $ak_row"
fi
ak_tldr="$(cut -f3 <<< "$ak_row")"
if [[ "$ak_tldr" =~ ^[0-9]+$ && "$ak_tldr" -gt 0 ]]; then
    ok "metrics: TLDR calcolato su assumed-knowledge (CONFIG non esclusivo)"
else
    ko "metrics: TLDR calcolato su assumed-knowledge (CONFIG non esclusivo)" "TLDR=$ak_tldr"
fi
# la riga # soglie: NON compare in TSV senza override
assert_absent "metrics: TSV senza riga soglie (no override)" "$OUT/metrics-main.tsv" '^# soglie:'

# modo testo: apre SEMPRE con la riga # soglie:, senza (OVERRIDE)
PROJECT_ROOT="$A" "$SD/doc-metrics.sh" --docs-root docs > "$OUT/metrics-main.txt" 2>/dev/null
head -1 "$OUT/metrics-main.txt" > "$OUT/metrics-main-l1"
assert_grep "metrics: modo testo apre con # soglie:" "$OUT/metrics-main-l1" '^# soglie: split=[0-9]+ merge=[0-9]+ tldr=[0-9]+ regroup=[0-9]+$'

# override: dichiarato in ENTRAMBI i formati, e la fixture sotto soglia diventa SPLIT
LOOM_DOC_THRESHOLDS_OVERRIDE="split=1000" PROJECT_ROOT="$A" "$SD/doc-metrics.sh" --docs-root docs --format tsv \
    > "$OUT/metrics-override.tsv" 2>/dev/null
head -1 "$OUT/metrics-override.tsv" > "$OUT/metrics-override-l1"
assert_grep "metrics: override dichiarato in TSV" "$OUT/metrics-override-l1" '^# soglie: split=1000 .*\(OVERRIDE\)$'
assert_grep "metrics: normale.md SPLIT sotto override" "$OUT/metrics-override.tsv" $'normale\\.md\t.*SPLIT'
LOOM_DOC_THRESHOLDS_OVERRIDE="split=1000" PROJECT_ROOT="$A" "$SD/doc-metrics.sh" --docs-root docs \
    > "$OUT/metrics-override.txt" 2>/dev/null
head -1 "$OUT/metrics-override.txt" > "$OUT/metrics-override-txt-l1"
assert_grep "metrics: override dichiarato in testo" "$OUT/metrics-override-txt-l1" '^# soglie: split=1000 .*\(OVERRIDE\)$'
# override con TLDR cap stretto: assumed-knowledge prende TLDR>CAP restando CONFIG
LOOM_DOC_THRESHOLDS_OVERRIDE="tldr=10" PROJECT_ROOT="$A" "$SD/doc-metrics.sh" --docs-root docs --format tsv \
    > "$OUT/metrics-tldr10.tsv" 2>/dev/null
assert_grep "metrics: TLDR>CAP calcolato anche su CONFIG" "$OUT/metrics-tldr10.tsv" $'assumed-knowledge\\.md\t.*TLDR>CAP.*CONFIG'

# =============================================================================
# doc-metrics — modo --inbox (repo A)
# =============================================================================
PROJECT_ROOT="$A" "$SD/doc-metrics.sh" --docs-root docs --inbox --format tsv \
    > "$OUT/inbox-full.tsv" 2> "$OUT/inbox-full.err"
assert_exit "metrics inbox: exit 0 con malformati in coda" 0 $?
cut --complement -f10 "$OUT/inbox-full.tsv" > "$OUT/inbox-full-noage.tsv"
assert_diff "metrics inbox: coda completa (senza AGE_DAYS)" "$OUT/inbox-full-noage.tsv" "$EXP/metrics-inbox.tsv"
assert_grep "metrics inbox: WARN malformato su stderr" "$OUT/inbox-full.err" 'malformato-riga4'
assert_grep "metrics inbox: WARN sul sub-bullet router-check" "$OUT/inbox-full.err" 'T111-router-check'

PROJECT_ROOT="$A" "$SD/doc-metrics.sh" --docs-root docs --inbox --drainable --format tsv \
    > "$OUT/inbox-drainable.tsv" 2>/dev/null
assert_exit "metrics inbox: exit 0 --drainable" 0 $?
cut --complement -f10 "$OUT/inbox-drainable.tsv" > "$OUT/inbox-drainable-noage.tsv"
assert_diff "metrics inbox: coda --drainable" "$OUT/inbox-drainable-noage.tsv" "$EXP/metrics-inbox-drainable.tsv"
assert_absent "metrics inbox: branch+drainable ESCLUSO dal drain" "$OUT/inbox-drainable.tsv" 'T121-branch-drainable'
assert_absent "metrics inbox: malformato ESCLUSO dal drain" "$OUT/inbox-drainable.tsv" 'malformato'

PROJECT_ROOT="$A" "$SD/doc-metrics.sh" --docs-root docs --inbox --natura derivazione --format tsv \
    > "$OUT/inbox-derivazione.tsv" 2>/dev/null
n_rows="$(grep -c $'\tderivazione\t' "$OUT/inbox-derivazione.tsv")"
if [[ "$n_rows" -eq 1 ]] && grep -q 'align-merge-compass' "$OUT/inbox-derivazione.tsv" \
    && [[ "$(grep -c $'^docs/' "$OUT/inbox-derivazione.tsv")" -eq 1 ]]; then
    ok "metrics inbox: --natura derivazione filtra"
else
    ko "metrics inbox: --natura derivazione filtra" "$(cat "$OUT/inbox-derivazione.tsv")"
fi
PROJECT_ROOT="$A" "$SD/doc-metrics.sh" --docs-root docs --inbox --natura sweep --format tsv \
    > "$OUT/inbox-sweep.tsv" 2>/dev/null
if [[ "$(grep -c $'^docs/' "$OUT/inbox-sweep.tsv")" -eq 1 ]] && grep -q 'sweep-deck' "$OUT/inbox-sweep.tsv"; then
    ok "metrics inbox: --natura sweep filtra"
else
    ko "metrics inbox: --natura sweep filtra" "$(cat "$OUT/inbox-sweep.tsv")"
fi

# fallback per file mai committato: CREATED da stat, quindi coda ultima riga
cp "$FX/inbox/T112-indexed-notldr.md" "$A/docs/inbox/mai-committato.md"
PROJECT_ROOT="$A" "$SD/doc-metrics.sh" --docs-root docs --inbox --format tsv \
    > "$OUT/inbox-untracked.tsv" 2>/dev/null
last_path="$(tail -1 "$OUT/inbox-untracked.tsv" | cut -f1)"
if [[ "$last_path" == "docs/inbox/mai-committato.md" ]]; then
    ok "metrics inbox: file mai committato in coda (fallback stat)"
else
    ko "metrics inbox: file mai committato in coda (fallback stat)" "ultima riga: $last_path"
fi
rm "$A/docs/inbox/mai-committato.md"

# =============================================================================
# check-doc-links (repo A)
# =============================================================================
PROJECT_ROOT="$A" "$SD/check-doc-links.sh" --docs-root docs --format tsv \
    > "$OUT/links.tsv" 2>/dev/null
assert_exit "links: exit 2 su NOSECTION" 2 $?
assert_grep "links: NOSECTION sulla sezione fantasma" "$OUT/links.tsv" $'^NOSECTION\tdocs/reference/cita.md\t'
assert_absent "links: inbox fuori perimetro (router → non e' DANGLING)" "$OUT/links.tsv" 'prompt-caching'
n_findings="$(grep -cP '^(DANGLING|NOSECTION)\t' "$OUT/links.tsv")"
if [[ "$n_findings" -eq 1 ]]; then ok "links: un solo finding"; else ko "links: un solo finding" "trovati: $n_findings"; fi

# =============================================================================
# doc-guard (repo A pulito, poi sporco; repo C untracked; NG non-git)
# =============================================================================
PROJECT_ROOT="$A" "$SD/doc-guard.sh" worktree --docs-root docs > "$OUT/guard-clean.out" 2>&1
assert_exit "guard: tree pulito → 0" 0 $?
assert_empty "guard: output vuoto su pulito" "$OUT/guard-clean.out"

echo "riga in piu'" >> "$A/docs/inbox/T110-miste.md"
PROJECT_ROOT="$A" "$SD/doc-guard.sh" worktree --docs-root docs > "$OUT/guard-dirty.out" 2>&1
assert_exit "guard: file modificato in inbox → 2" 2 $?
assert_grep "guard: il path modificato e' nell'elenco" "$OUT/guard-dirty.out" 'docs/inbox/T110-miste\.md'
git -C "$A" checkout -q -- docs/inbox/T110-miste.md

mkdir -p "$C/docs/inbox" "$C/docs/reference"
mk_repo "$C"
echo x > "$C/seed"; git_c "$C" seed 1767225600
cp "$FX/inbox/T110-miste.md" "$C/docs/inbox/a.md"
cp "$FX/inbox/sweep-deck.md" "$C/docs/inbox/b.md"
PROJECT_ROOT="$C" "$SD/doc-guard.sh" worktree --docs-root docs > "$OUT/guard-untracked.out" 2>&1
assert_exit "guard: inbox untracked → 2" 2 $?
if grep -q 'docs/inbox/a\.md' "$OUT/guard-untracked.out" && grep -q 'docs/inbox/b\.md' "$OUT/guard-untracked.out"; then
    ok "guard: -uall elenca i singoli file, non la cartella"
else
    ko "guard: -uall elenca i singoli file, non la cartella" "$(cat "$OUT/guard-untracked.out")"
fi

PROJECT_ROOT="$NG" "$SD/doc-guard.sh" worktree --docs-root docs > "$OUT/guard-nongit.out" 2>&1
assert_exit "guard: cartella non-git → 1" 1 $?

# =============================================================================
# Repo D — build-index senza inbox indicizzabile
# =============================================================================
mkdir -p "$D/docs/reference" "$D/docs/inbox"
mk_repo "$D"
cp "$FX/reference/normale.md" "$D/docs/reference/"
cp "$FX/inbox/align-merge-compass.md" "$D/docs/inbox/"   # mai indicizzabile
git -C "$D" add -A && GIT_AUTHOR_DATE="@1767225600 +0000" GIT_COMMITTER_DATE="@1767225600 +0000" git -C "$D" commit -qm seed
PROJECT_ROOT="$D" "$SD/build-index.sh" --docs-root docs > "$OUT/index-d.out" 2>/dev/null
assert_exit "index: exit 0 senza violazioni" 0 $?
assert_absent "index: nessuna sezione inbox senza indicizzabili" "$D/docs/reference/INDEX.md" '## inbox'
assert_absent "index: nessuna riga di precedenza orfana" "$D/docs/reference/INDEX.md" 'Precedenza'

# =============================================================================
# Repo B — doc vuota, errori d'uso, inbox.sh new
# =============================================================================
mkdir -p "$B/docs"
mk_repo "$B"

PROJECT_ROOT="$B" "$SD/doc-metrics.sh" --docs-root docs --format tsv > "$OUT/empty.tsv" 2>/dev/null
assert_exit "metrics: doc vuota TSV → exit 0" 0 $?
assert_empty "metrics: doc vuota TSV → output vuoto" "$OUT/empty.tsv"

PROJECT_ROOT="$B" "$SD/doc-metrics.sh" --docs-root docs --bogus > "$OUT/badarg.out" 2>/dev/null
assert_exit "metrics: argomento ignoto → exit 2" 2 $?
assert_empty "metrics: argomento ignoto → stdout vuoto" "$OUT/badarg.out"
PROJECT_ROOT="$B" "$SD/doc-metrics.sh" --docs-root docs --natura sweep > "$OUT/badarg2.out" 2>/dev/null
assert_exit "metrics: --natura senza --inbox → exit 2" 2 $?
assert_empty "metrics: --natura senza --inbox → stdout vuoto" "$OUT/badarg2.out"

# --- new: nozioni con default di titolo ----------------------------------------
printf '%s\n' "prima nozione di prova" "seconda nozione di prova" "terza nozione di prova" | \
    PROJECT_ROOT="$B" "$SD/inbox.sh" new --docs-root docs --slug cache-test --natura nozioni \
        --cappello T200 --tldr "tre nozioni di prova" --indexed --drainable > "$OUT/new1.out" 2>&1
assert_exit "new: nozioni → exit 0" 0 $?
assert_grep "new: INBOX_PATH in output" "$OUT/new1.out" '^INBOX_PATH=.*/docs/inbox/T200-cache-test\.md$'
assert_diff "new: file conforme all'atteso" "$B/docs/inbox/T200-cache-test.md" "$EXP/new-nozioni.md"
PROJECT_ROOT="$B" "$SD/inbox.sh" parse --file "$B/docs/inbox/T200-cache-test.md" >/dev/null 2>&1
assert_exit "new→parse: l'anello si chiude (exit 0)" 0 $?

# stessa invocazione due volte → suffisso -2, il primo intatto
printf '%s\n' "prima nozione di prova" "seconda nozione di prova" "terza nozione di prova" | \
    PROJECT_ROOT="$B" "$SD/inbox.sh" new --docs-root docs --slug cache-test --natura nozioni \
        --cappello T200 --tldr "tre nozioni di prova" --indexed --drainable > "$OUT/new2.out" 2>&1
assert_exit "new: collisione → exit 0" 0 $?
assert_grep "new: collisione → suffisso -2" "$OUT/new2.out" 'T200-cache-test-2\.md$'
assert_diff "new: il primo file resta intatto" "$B/docs/inbox/T200-cache-test.md" "$EXP/new-nozioni.md"

# senza cappello → <slug>.md
printf '%s\n' "nozione senza cappello" | \
    PROJECT_ROOT="$B" "$SD/inbox.sh" new --docs-root docs --slug ordini-liberi --natura nozioni \
        > "$OUT/new3.out" 2>&1
assert_exit "new: senza cappello → exit 0" 0 $?
assert_grep "new: nome <slug>.md" "$OUT/new3.out" '/docs/inbox/ordini-liberi\.md$'
head -1 "$B/docs/inbox/ordini-liberi.md" > "$OUT/new3-l1"
assert_grep "new: titolo default dallo slug" "$OUT/new3-l1" '^# ordini liberi$'

# derivazione con range → layout conforme
printf '%s\n' "Riallinea la doc di compass al merge del matcher." | \
    PROJECT_ROOT="$B" "$SD/inbox.sh" new --docs-root docs --slug align-compass --natura derivazione \
        --drainable --ancora "range:a1b2c3..d4e5f6" --ancora "path:loom-compass/" > "$OUT/new4.out" 2>&1
assert_exit "new: derivazione → exit 0" 0 $?
assert_diff "new: derivazione conforme all'attesa" "$B/docs/inbox/align-compass.md" "$EXP/new-derivazione.md"

# sweep senza ancore → legittimo (l'opposto della derivazione)
printf '%s\n' "Riscrivi i titoli della doc del deck perche' siano trovabili dal sintomo." | \
    PROJECT_ROOT="$B" "$SD/inbox.sh" new --docs-root docs --slug sweep-titoli --natura sweep \
        --drainable > "$OUT/new5.out" 2>&1
assert_exit "new: sweep senza ancore → exit 0" 0 $?
PROJECT_ROOT="$B" "$SD/inbox.sh" parse --file "$B/docs/inbox/sweep-titoli.md" >/dev/null 2>&1
assert_exit "new: lo sweep nudo e' conforme (parse 0)" 0 $?

# i rifiuti: exit 1 e NESSUN file creato
count_before="$(find "$B/docs/inbox" -name '*.md' | wc -l)"
printf 'x\n' | PROJECT_ROOT="$B" "$SD/inbox.sh" new --docs-root docs --slug k1 --natura derivazione \
    --indexed --ancora "range:a..b" >/dev/null 2>&1
assert_exit "new: --indexed su derivazione → exit 1" 1 $?
printf 'x\n' | PROJECT_ROOT="$B" "$SD/inbox.sh" new --docs-root docs --slug k2 --natura nozioni \
    --ancora "range:a..b" >/dev/null 2>&1
assert_exit "new: --ancora su nozioni → exit 1" 1 $?
printf 'x\n' | PROJECT_ROOT="$B" "$SD/inbox.sh" new --docs-root docs --slug k3 --natura derivazione \
    --ancora "path:x/" >/dev/null 2>&1
assert_exit "new: derivazione senza range → exit 1" 1 $?
printf 'a\n\nb\n' | PROJECT_ROOT="$B" "$SD/inbox.sh" new --docs-root docs --slug k4 --natura nozioni \
    >/dev/null 2>&1
assert_exit "new: riga vuota fra le nozioni → exit 1" 1 $?
count_after="$(find "$B/docs/inbox" -name '*.md' | wc -l)"
if [[ "$count_before" -eq "$count_after" ]]; then
    ok "new: i rifiuti non creano nessun file"
else
    ko "new: i rifiuti non creano nessun file" "prima: $count_before, dopo: $count_after"
fi

# =============================================================================
# inbox.sh parse (copie in TMPD, fuori da ogni repo)
# =============================================================================
cp "$FX"/inbox/*.md "$TMPD/"

"$SD/inbox.sh" parse --file "$TMPD/T109-cache-verdetti.md" --format tsv > "$OUT/parse-verdetti.tsv" 2>&1
assert_exit "parse: verdetti-router → exit 0" 0 $?
assert_diff "parse: verdetti-router TSV" "$OUT/parse-verdetti.tsv" "$EXP/parse-verdetti.tsv"

"$SD/inbox.sh" parse --file "$TMPD/T110-miste.md" --format tsv > "$OUT/parse-miste.tsv" 2>&1
assert_exit "parse: miste → exit 0" 0 $?
assert_diff "parse: miste TSV (aperte con rotta vs nude vs chiuse)" "$OUT/parse-miste.tsv" "$EXP/parse-miste.tsv"

"$SD/inbox.sh" parse --file "$TMPD/T109-cache-completo.md" --format text > "$OUT/parse-completo.txt" 2>&1
assert_exit "parse: completo text → exit 0" 0 $?
assert_diff "parse: resa text della fixture completa" "$OUT/parse-completo.txt" "$EXP/parse-completo.txt"

for m in malformato-riga4 malformato-assente T111-router-check; do
    "$SD/inbox.sh" parse --file "$TMPD/${m}.md" --format tsv > "$OUT/parse-${m}.out" 2>&1
    assert_exit "parse: ${m} → exit 2" 2 $?
    n_lines="$(wc -l < "$OUT/parse-${m}.out")"
    if [[ "$n_lines" -eq 1 ]] && grep -qP '^MALFORMATO\t' "$OUT/parse-${m}.out"; then
        ok "parse: ${m} → solo la riga MALFORMATO"
    else
        ko "parse: ${m} → solo la riga MALFORMATO" "$(cat "$OUT/parse-${m}.out")"
    fi
done
assert_grep "parse: ragione distinta (riga 4)"       "$OUT/parse-malformato-riga4.out"  'fuori dalla riga 3'
assert_grep "parse: ragione distinta (assente)"      "$OUT/parse-malformato-assente.out" 'marker assente'
assert_grep "parse: ragione distinta (router ✔️)"    "$OUT/parse-T111-router-check.out"  'attore-glifo'

"$SD/inbox.sh" parse --file "$TMPD/non-esiste.md" >/dev/null 2>&1
assert_exit "parse: file inesistente → exit 1, non 2" 1 $?

# =============================================================================
# inbox.sh marker (copie in TMPD)
# =============================================================================
cp "$TMPD/T120-branched.md" "$TMPD/T120-pre.md"
"$SD/inbox.sh" marker --file "$TMPD/T120-branched.md" --unset branch --set drainable > /dev/null 2>&1
assert_exit "marker: sblocco → exit 0" 0 $?
n_changed="$(diff "$TMPD/T120-pre.md" "$TMPD/T120-branched.md" | grep -c '^<')"
if [[ "$n_changed" -eq 1 ]]; then
    ok "marker: esattamente una riga cambiata"
else
    ko "marker: esattamente una riga cambiata" "righe cambiate: $n_changed"
fi
sed -n '3p' "$TMPD/T120-branched.md" > "$OUT/marker-l3"
assert_grep "marker: riga 3 in ordine canonico" "$OUT/marker-l3" '^> \*\*INBOX\*\*: nozioni · indexed · drainable$'

cp "$TMPD/T120-branched.md" "$TMPD/T120-pre2.md"
"$SD/inbox.sh" marker --file "$TMPD/T120-branched.md" --set fuori-vocabolario > /dev/null 2>&1
assert_exit "marker: token fuori vocabolario → exit 1" 1 $?
assert_same "marker: file byte-identico dopo il rifiuto" "$TMPD/T120-pre2.md" "$TMPD/T120-branched.md"

# =============================================================================
# inbox.sh registro (copie in TMPD) — l'anello coi golden
# =============================================================================
cp "$FX/inbox/T109-cache-anthropic.md" "$TMPD/registro.md"
"$SD/inbox.sh" registro --file "$TMPD/registro.md" --attore router \
    < "$FX/envelope-router.json" > /dev/null 2>&1
assert_exit "registro: envelope router → exit 0" 0 $?
assert_same "registro: router produce ESATTAMENTE il golden verdetti" \
    "$TMPD/registro.md" "$FX/inbox/T109-cache-verdetti.md"

"$SD/inbox.sh" registro --file "$TMPD/registro.md" --attore writer \
    < "$FX/envelope-writer.json" > /dev/null 2>&1
assert_exit "registro: envelope writer → exit 0" 0 $?
assert_same "registro: writer produce ESATTAMENTE il golden completo" \
    "$TMPD/registro.md" "$FX/inbox/T109-cache-completo.md"

"$SD/inbox.sh" parse --file "$TMPD/registro.md" --format tsv > "$OUT/registro-parse.tsv" 2>&1
n_aperte="$(grep -cP '^NOZIONE\t\S+\taperta' "$OUT/registro-parse.tsv")"
if [[ "$n_aperte" -eq 0 ]]; then
    ok "registro→parse: zero aperte dopo il ciclo completo"
else
    ko "registro→parse: zero aperte dopo il ciclo completo" "aperte: $n_aperte"
fi

cp "$FX/inbox/T109-cache-anthropic.md" "$TMPD/registro-err.md"
echo '{"verdetti": [{"id": "n99", "verdetto": "rotta", "target": "x.md", "evidenza": "e"}]}' | \
    "$SD/inbox.sh" registro --file "$TMPD/registro-err.md" --attore router > /dev/null 2>&1
assert_exit "registro: id assente dal file → exit 1" 1 $?
assert_same "registro: file byte-identico dopo il rifiuto" \
    "$TMPD/registro-err.md" "$FX/inbox/T109-cache-anthropic.md"

echo '{"verdetti": [{"id": "n1", "verdetto": "drop"}]}' | \
    "$SD/inbox.sh" registro --file "$TMPD/registro-err.md" --attore router > /dev/null 2>&1
assert_exit "registro: non-azione senza motivo → exit 1" 1 $?
assert_same "registro: nessuna scrittura parziale" \
    "$TMPD/registro-err.md" "$FX/inbox/T109-cache-anthropic.md"

# =============================================================================
# Esito
# =============================================================================
echo
echo "── ${PASS} ok · ${FAIL} fail ──"
if [[ "$FAIL" -eq 0 ]]; then
    rm -rf "$WORK"
    echo "verde — cartella di lavoro rimossa"
    exit 0
else
    echo "rosso — la cartella di lavoro RESTA per la diagnosi: ${WORK}"
    exit 1
fi
