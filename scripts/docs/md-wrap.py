#!/usr/bin/env python3
"""
md-wrap — classifica e srotola l'hard-wrap nei file markdown.

Due modi:
  --scan   classifica ogni file in WRAP / misto / libero, con la colonna di wrap
           rilevata e il rapporto di righe di continuazione. Read-only, TSV su
           stdout, una riga per file non 'libero'.
  --apply  srotola in place: ogni riga di continuazione viene ricongiunta alla
           precedente con uno spazio. Salva una copia integrale prima di scrivere
           e verifica il risultato col confronto normalizzato.

Il riconoscimento non guarda il massimo di riga (una singola riga lunga farebbe
passare per libero un file wrappato al 78%): guarda le righe di continuazione,
cioe' righe che dentro un blocco non aprono un nuovo costrutto.

Una continuazione candidata diventa una rottura di wrap confermata solo se la
prima parola della riga successiva NON sarebbe entrata nella colonna rilevata:
e' cio' che distingue un a-capo automatico da un a-capo voluto.

Dipendenza runtime: python3. E' l'unico artefatto Python del plugin — tutto il
resto di scripts/ e' bash. Un consumer che lo invoca su una macchina senza
interprete non riceve un errore di questo script ma un fallimento di spawn, e
deve restare muto invece di rompersi.
"""

import argparse
import os
import re
import shutil
import sys
import unicodedata

# ---------------------------------------------------------------------------
# Riconoscimento della struttura del markdown
# ---------------------------------------------------------------------------

FENCE_RE = re.compile(r'^\s{0,3}(```|~~~)')
TABLE_RE = re.compile(r'^\s{0,3}\|')
HEADING_RE = re.compile(r'^\s{0,3}#{1,6}\s')
QUOTE_RE = re.compile(r'^\s{0,3}>')
HTML_RE = re.compile(r'^\s{0,3}<')
HRULE_RE = re.compile(r'^\s{0,3}([-*_])\s*(\1\s*){2,}$')
LIST_RE = re.compile(r'^\s*([-*+]|\d+[.)])(\s|$)')
# etichette che aprono una riga per scelta, mai per a-capo automatico
LABEL_RE = re.compile(r'^\s*(Ancora|Ancora primaria|Nota|Fonte|Evidenza|Verdetto|Target|Rotta)\s*:')
BOX_DRAWING = set('─│├└┌┐┘┴┬┼╭╮╯╰━┃┏┓┗┛━→←↑↓')

# La colonna di wrap plausibile sta in questa finestra: sopra il tetto una riga
# e' prosa libera, non un a-capo messo a occhio.
MAX_PLAUSIBLE_COLUMN = 110
MIN_PLAUSIBLE_COLUMN = 60
# Sotto questo numero di candidate la colonna rilevata non e' affidabile.
MIN_CANDIDATES_FOR_COLUMN = 3
# Chi va a capo a occhio non centra sempre lo stesso punto: la colonna e' una
# banda, non una linea. Senza questa tolleranza una rottura anticipata di pochi
# caratteri passa per voluta e la riga resta spezzata.
RAGGED_TOLERANCE = 8

PROSE, SKIP, BLANK = 'prose', 'skip', 'blank'


def starts_with_emoji(line):
    """Solo simboli non-ASCII: il backtick e' categoria Sk e non apre niente."""
    stripped = line.lstrip()
    if not stripped:
        return False
    first = stripped[0]
    if ord(first) < 128:
        return False
    return unicodedata.category(first) == 'So'


def opens_construct(line):
    """La riga apre qualcosa di suo — non puo' essere la coda di quella prima."""
    return bool(
        LIST_RE.match(line)
        or LABEL_RE.match(line)
        or starts_with_emoji(line)
    )


def classify_lines(lines):
    """Assegna a ogni riga uno fra PROSE / SKIP / BLANK."""
    kinds = []
    in_fence = False
    fence_marker = None
    in_front_matter = lines and lines[0].rstrip('\n') == '---'
    front_matter_closed = False

    for index, raw in enumerate(lines):
        line = raw.rstrip('\n')

        if in_front_matter and not front_matter_closed:
            kinds.append(SKIP)
            if index > 0 and line.strip() == '---':
                front_matter_closed = True
            continue

        fence_match = FENCE_RE.match(line)
        if fence_match:
            marker = fence_match.group(1)
            if not in_fence:
                in_fence, fence_marker = True, marker
            elif marker == fence_marker:
                in_fence, fence_marker = False, None
            kinds.append(SKIP)
            continue

        if in_fence:
            kinds.append(SKIP)
            continue

        if not line.strip():
            kinds.append(BLANK)
            continue

        indent = len(line) - len(line.lstrip(' '))
        if (
            indent >= 4
            or TABLE_RE.match(line)
            or HEADING_RE.match(line)
            or QUOTE_RE.match(line)
            or HTML_RE.match(line)
            or HRULE_RE.match(line)
            or any(char in BOX_DRAWING for char in line)
        ):
            kinds.append(SKIP)
            continue

        kinds.append(PROSE)

    return kinds


def find_candidates(lines, kinds):
    """Indici delle righe che potrebbero essere la coda della riga precedente."""
    candidates = []
    for index in range(1, len(lines)):
        if kinds[index] != PROSE or kinds[index - 1] != PROSE:
            continue
        line = lines[index].rstrip('\n')
        previous = lines[index - 1].rstrip('\n')
        if opens_construct(line):
            continue
        # due spazi in coda o un backslash sono un a-capo dichiarato dal markdown
        if previous.endswith('  ') or previous.endswith('\\'):
            continue
        if len(line) - len(line.lstrip(' ')) >= 4:
            continue
        candidates.append(index)
    return candidates


def detect_column(lines, candidates):
    """La colonna di wrap, stimata sulle righe che hanno una coda.

    Non il massimo: una sola riga piu' lunga della banda reale alza la soglia e
    spegne le giunzioni intorno a se'. E' lo stesso difetto del massimo di riga
    che rende inaffidabile il riconoscimento, spostato di un livello.
    """
    lengths = [
        len(lines[index - 1].rstrip('\n').rstrip())
        for index in candidates
    ]
    plausible = sorted(
        length for length in lengths
        if MIN_PLAUSIBLE_COLUMN <= length <= MAX_PLAUSIBLE_COLUMN
    )
    if len(plausible) < MIN_CANDIDATES_FOR_COLUMN:
        return None
    position = min(int(len(plausible) * 0.90), len(plausible) - 1)
    return plausible[position]


def first_word(line):
    stripped = line.strip()
    return stripped.split(' ', 1)[0] if stripped else ''


def confirmed_breaks(lines, candidates, column):
    """Le candidate la cui rottura e' spiegata dalla colonna, e solo quelle."""
    if column is None:
        return []
    confirmed = []
    floor = column - RAGGED_TOLERANCE
    for index in candidates:
        previous = lines[index - 1].rstrip('\n').rstrip()
        word = first_word(lines[index])
        if not word:
            continue
        if len(previous) + 1 + len(word) > floor:
            confirmed.append(index)
    return confirmed


def analyze(path):
    with open(path, encoding='utf-8') as handle:
        lines = handle.readlines()

    kinds = classify_lines(lines)
    prose_count = sum(1 for kind in kinds if kind == PROSE)
    candidates = find_candidates(lines, kinds)
    column = detect_column(lines, candidates)
    breaks = confirmed_breaks(lines, candidates, column)

    ratio = len(breaks) / prose_count if prose_count else 0.0
    if ratio >= 0.45:
        verdict = 'WRAP'
    elif ratio >= 0.08:
        verdict = 'misto'
    else:
        verdict = 'libero'

    return {
        'path': path,
        'verdict': verdict,
        'column': column,
        'ratio': ratio,
        'prose': prose_count,
        'breaks': breaks,
        'lines': lines,
    }


# ---------------------------------------------------------------------------
# Riscrittura
# ---------------------------------------------------------------------------

def unwrap(lines, breaks):
    """Ricongiunge ogni riga di continuazione alla precedente con uno spazio."""
    to_join = set(breaks)
    output = []
    for index, raw in enumerate(lines):
        if index in to_join and output:
            tail = raw.rstrip('\n').strip()
            output[-1] = output[-1].rstrip('\n').rstrip() + ' ' + tail + '\n'
        else:
            output.append(raw)
    return output


MAX_PASSES = 6


def unwrap_to_fixpoint(lines, column):
    """Srotola finche' non resta niente da unire, a colonna ferma.

    Una giunzione allunga la riga precedente e rende visibile la continuazione
    successiva, che al primo giro non lo era: serve iterare. La colonna resta
    quella misurata sull'originale — ristimarla su un file gia' mezzo srotolato
    da un valore falso, che unirebbe righe corte scritte una per riga apposta.
    """
    if column is None:
        return lines, 0
    joined = 0
    for _ in range(MAX_PASSES):
        kinds = classify_lines(lines)
        breaks = confirmed_breaks(lines, find_candidates(lines, kinds), column)
        if not breaks:
            break
        lines = unwrap(lines, breaks)
        joined += len(breaks)
    return lines, joined


def normalized(text):
    """Il confronto che deve reggere: solo whitespace puo' essere cambiato."""
    return re.sub(r'\s+', ' ', text).strip()


# ---------------------------------------------------------------------------
# Raccolta dei file
# ---------------------------------------------------------------------------

# Elenco chiuso di nomi di directory, universali per costruzione: dipendenze,
# metadati di VCS, artefatti di build e cache di tool. Non esiste un canale
# per-progetto (ne' un file ignore, ne' un campo di config, ne' una regola sulla
# forma del nome): lo scanner e' distribuito col plugin e gira su ogni progetto,
# quindi un'esclusione che nomina la cartella di UN repo qui sarebbe un pezzo di
# quel repo dentro un artefatto di tutti. Cio' che un progetto vorrebbe togliere
# in piu' resta nel conteggio finche' un dato misurato non dimostra che pesa.
EXCLUDED_DIRS = frozenset({
    'node_modules',
    'vendor',
    '.git',
    '.hg',
    '.svn',
    '.venv',
    'venv',
    '__pycache__',
    '.mypy_cache',
    '.pytest_cache',
    '.tox',
    '.next',
    '.nuxt',
    '.cache',
    'dist',
    'build',
    'target',
    'coverage',
})


def collect(root):
    """Ogni .md sotto root, saltando le directory dell'elenco chiuso."""
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [name for name in dirnames if name not in EXCLUDED_DIRS]
        for name in sorted(filenames):
            if name.endswith('.md'):
                found.append(os.path.join(dirpath, name))
    return sorted(found)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', default='.')
    parser.add_argument('--scan', action='store_true')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--backup', help='cartella dove copiare i file prima di scriverli')
    parser.add_argument('--only', help='sostringa di path da includere')
    args = parser.parse_args()

    root = os.path.abspath(args.root)
    if not os.path.isdir(root):
        print(f'ERRORE\troot inesistente: {root}', file=sys.stderr)
        return 1

    paths = collect(root)
    if args.only:
        paths = [p for p in paths if args.only in p]

    if args.apply and not args.backup:
        parser.error('--apply richiede --backup')

    tally = {'WRAP': 0, 'misto': 0, 'libero': 0}
    touched, reverted = [], []

    for path in paths:
        try:
            report = analyze(path)
        except (UnicodeDecodeError, OSError) as error:
            print(f'ERRORE\t{os.path.relpath(path, root)}\t{error}', file=sys.stderr)
            continue

        tally[report['verdict']] += 1
        relative = os.path.relpath(path, root)

        if args.scan and report['verdict'] != 'libero':
            print(
                f"{report['verdict']}\t{relative}\t"
                f"col={report['column']}\tratio={report['ratio']:.2f}\t"
                f"breaks={len(report['breaks'])}\tprose={report['prose']}"
            )

        if args.apply and report['breaks']:
            original = ''.join(report['lines'])
            rewritten_lines, joined = unwrap_to_fixpoint(
                report['lines'], report['column']
            )
            rewritten = ''.join(rewritten_lines)
            report['breaks'] = range(joined)

            if normalized(original) != normalized(rewritten):
                reverted.append(relative)
                print(f'REVERT\t{relative}\tconfronto normalizzato fallito', file=sys.stderr)
                continue

            backup_path = os.path.join(args.backup, relative)
            os.makedirs(os.path.dirname(backup_path), exist_ok=True)
            shutil.copy2(path, backup_path)
            with open(path, 'w', encoding='utf-8') as handle:
                handle.write(rewritten)
            touched.append((relative, len(report['breaks'])))

    print(
        f"\nSUMMARY files={len(paths)} "
        f"WRAP={tally['WRAP']} misto={tally['misto']} libero={tally['libero']}",
        file=sys.stderr,
    )
    if args.apply:
        joins = sum(count for _, count in touched)
        print(
            f"APPLIED files={len(touched)} joins={joins} reverted={len(reverted)}",
            file=sys.stderr,
        )
    return 0


if __name__ == '__main__':
    sys.exit(main())
