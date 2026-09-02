#!/usr/bin/env bash

# =============================================================================
# lib-doc.sh — grammatica e soglie del sistema doc v2
# Usage: source "${SCRIPT_DIR}/lib-doc.sh"   (mai invocata direttamente)
# =============================================================================
#
# Proprietario UNICO di:
#   - le soglie del contratto doc (readonly, niente override da CLI): le quattro
#     della topologia di reference/ piu' quella di avviso sulle nozioni di un inbox
#   - il parser dell'override di test LOOM_DOC_THRESHOLDS_OVERRIDE
#   - la regex del TLDR (doc_tldr), condivisa fra i layer: riga 3 per reference/,
#     riga 4 per l'inbox — la riga e' un PARAMETRO, cosi' l'implementazione resta una
#   - la precedenza di layer (doc_layer): inbox → online → offline → altro
#   - le regex del formato inbox (usate SOLO da inbox.sh)
#   - il perimetro escluso condiviso (doc_excluded): il runtime che non e' doc
#   - la lista dei file di configurazione dentro reference/ (doc_config_file),
#     condivisa fra doc-metrics.sh e tldr.sh
#
# Ogni regex del formato vive qui e in nessun altro posto. Una primitiva che ha
# bisogno di leggere il formato inbox chiama `inbox.sh parse`, mai una propria
# regex: doc-metrics e build-index sono CONSUMER di inbox.sh, non secondi parser.
#
# Soglie: niente override da CLI — in v1 un'invocazione con --split-threshold
# diverso faceva misurare lo script contro un numero e giudicare l'agent contro
# quello nel proprio prompt, senza che nessun passo lo rilevasse. Resta un solo
# canale, per il banco di test: LOOM_DOC_THRESHOLDS_OVERRIDE
# ("split=N,merge=N,tldr=N,regroup=N,inbox=N"). Quando e' settato, chi lo subisce
# APRE l'output con la riga `# soglie: ... (OVERRIDE)`: un override dichiarato e'
# una configurazione, uno silenzioso e' il difetto v1.
# =============================================================================

# ---- Soglie ------------------------------------------------------------------

LW_DOC_SPLIT=15000
LW_DOC_MERGE=3000
LW_DOC_TLDR_CAP=500
LW_DOC_REGROUP=60000
LW_DOC_INBOX_NOZIONI=100
LW_DOC_OVERRIDE=0

if [[ -n "${LOOM_DOC_THRESHOLDS_OVERRIDE:-}" ]]; then
    LW_DOC_OVERRIDE=1
    IFS=',' read -ra _lw_pairs <<< "$LOOM_DOC_THRESHOLDS_OVERRIDE"
    for _lw_pair in "${_lw_pairs[@]}"; do
        _lw_k="${_lw_pair%%=*}"; _lw_v="${_lw_pair#*=}"
        case "$_lw_k" in
            split)   LW_DOC_SPLIT="$_lw_v" ;;
            merge)   LW_DOC_MERGE="$_lw_v" ;;
            tldr)    LW_DOC_TLDR_CAP="$_lw_v" ;;
            regroup) LW_DOC_REGROUP="$_lw_v" ;;
            inbox)   LW_DOC_INBOX_NOZIONI="$_lw_v" ;;
            *) echo "[lib-doc] WARN override ignoto: ${_lw_k}" >&2 ;;
        esac
    done
    unset _lw_pairs _lw_pair _lw_k _lw_v
fi

readonly LW_DOC_SPLIT LW_DOC_MERGE LW_DOC_TLDR_CAP LW_DOC_REGROUP LW_DOC_OVERRIDE
readonly LW_DOC_INBOX_NOZIONI

# La riga che dichiara contro cosa e' stata presa una misura. Il modo testo la
# stampa sempre; il TSV solo sotto override (e' il marchio dell'override, non
# una cortesia di lettura).
#
# LW_DOC_INBOX_NOZIONI resta FUORI da questa riga: le quattro soglie sopra
# governano la topologia dei file di reference/ e le misura doc-metrics, mentre
# quella governa un avviso di checkpoint su un file inbox — un consumer diverso,
# che dichiara da se' il numero contro cui ha misurato dentro il proprio avviso.
doc_soglie_line() {
    local suffix=""
    (( LW_DOC_OVERRIDE )) && suffix=" (OVERRIDE)"
    printf '# soglie: split=%s merge=%s tldr=%s regroup=%s%s\n' \
        "$LW_DOC_SPLIT" "$LW_DOC_MERGE" "$LW_DOC_TLDR_CAP" "$LW_DOC_REGROUP" "$suffix"
}

# ---- TLDR --------------------------------------------------------------------
#
# L'unica implementazione dell'estrazione TLDR. La riga e' un parametro perche'
# le due sedi divergono in v2 — 3 per reference/, 4 per l'inbox — ed e' la
# ragione per cui la funzione deve essere una sola: due copie con due costanti
# diverse driftano al primo ritocco. Chiamanti: inbox.sh sulla riga 4, i lettori
# di reference/ sulla riga 3.

doc_tldr() {  # <file> <riga> → testo del TLDR (trim trailing), vuoto se assente
    local line
    line="$(sed -n "${2}p" "$1" 2>/dev/null)" || return 0
    [[ "$line" =~ ^\>\ \*\*TLDR\*\*:\ (.+)$ ]] || return 0
    local t="${BASH_REMATCH[1]}"
    printf '%s\n' "${t%"${t##*[![:space:]]}"}"
}

# ---- Layer -------------------------------------------------------------------
#
# Precedenza: inbox → online → offline → altro. Online si legge dagli @-import
# di primo livello di CLAUDE.md (un file online che ne @-importa altri non viene
# seguito); INDEX.md sta sotto reference/ ma e' online se @-importato.

LW_DOC_ONLINE_LIST=""

doc_load_online() {  # <project_root> — popola la lista degli @-import
    local claude_md="$1/CLAUDE.md"
    LW_DOC_ONLINE_LIST=""
    [[ -f "$claude_md" ]] || return 0
    LW_DOC_ONLINE_LIST="$(grep -oE '@[^ )]+\.md' "$claude_md" 2>/dev/null | sed 's/^@//' | sort -u)"
}

doc_is_online() {  # <rel-to-project-root>
    [[ -z "$LW_DOC_ONLINE_LIST" ]] && return 1
    grep -qxF "$1" <<< "$LW_DOC_ONLINE_LIST"
}

doc_layer() {  # <rel-to-project-root> → inbox|online|offline|altro
    local rel="$1"
    if [[ "$rel" == */inbox/* ]]; then
        echo "inbox"
    elif doc_is_online "$rel"; then
        echo "online"
    elif [[ "$rel" == */reference/* ]]; then
        echo "offline"
    else
        echo "altro"
    fi
}

# ---- Perimetro escluso condiviso ---------------------------------------------
#
# SOLO cio' che ogni chiamante esclude: il runtime che non e' doc. Un'esclusione
# che vale per un chiamante solo e' una regola di quel chiamante e sta scritta
# li' — INDEX.md lo esclude solo check-doc-links.

doc_excluded() {  # <rel-path> → 0 se fuori dal perimetro doc
    case "$1" in
        */tasks/*|tasks/*|*/current-task.md|current-task.md) return 0 ;;
    esac
    return 1
}

# ---- File di configurazione dentro reference/ --------------------------------
#
# Un file che sta sotto reference/ ma NON e' prosa: un elenco di coppie
# chiave-valore che altri attori del sistema doc leggono a un indirizzo fisso.
# Sta qui e non in doc-metrics.sh perche' i consumer sono due, e la lista deve
# essere una sola: doc-metrics ne sopprime SPLIT e MERGE? (una fusione per
# topologia gli farebbe perdere l'indirizzo fisso), tldr.sh lo tiene fuori dal
# produttore di TLDR.
#
# Il produttore lo esenta perche' e' vincolato all'estrazione letterale dal
# corpo, e su un file senza prosa non ha da cosa estrarre: misurato su
# assumed-knowledge.md, 2 candidati raccolti e una riga 3 di 38 caratteri —
# l'unico heading del file ricopiato — al posto dei 314 della riga scritta a
# mano, che dice cose che nel corpo non compaiono affatto (chi governa il
# verdetto `noto` del router, le regole di glossa del writer). Nessun estrattore
# vincolato al corpo puo' riprodurla: la sua riga 3 resta scritta a mano.
#
# Cio' che l'esenzione NON copre: i flag TLDR di doc-metrics (NOTLDR, TLDR>CAP)
# restano calcolati anche qui. Sopprimerli renderebbe invisibile la sparizione
# del TLDR proprio sul file che ogni giudizio apre.

doc_config_file() {  # <path, assoluto o relativo> → 0 se e' configurazione
    case "$1" in
        */reference/*|reference/*) ;;
        *) return 1 ;;
    esac
    [[ "$(basename -- "$1")" == "assumed-knowledge.md" ]]
}

# ---- Formato inbox (usate solo da inbox.sh) ----------------------------------

readonly LW_DOC_RE_MARKER='^> \*\*INBOX\*\*: (.+)$'
readonly LW_DOC_RE_NOZIONE='^- \*\*(n[0-9]+)\*\* — (.*)$'
readonly LW_DOC_RE_SUB='^  - (.+)$'
readonly LW_DOC_RE_ANCORA='^([a-z][a-z0-9_-]*): (.+)$'

# Separatore che annuncia il blocco delle ancore in derivazione e sweep. Serve
# perche' la regex sopra matcha qualunque riga `parola: valore`, quindi una riga
# di prosa che apre con una minuscola seguita da due punti — «registro: presente
# indicativo» — diventerebbe un'ancora che nessuno ha voluto. Col separatore il
# confine fra prosa e ancore e' esplicito invece che affidato a una convenzione
# tipografica invisibile a chi scrive prosa libera.
#
# Retro-compatibile per costruzione: un file senza separatore si parsa con la
# regola vecchia (ancore ovunque dopo la riga 3), o i file inbox gia' scritti
# perderebbero le loro ancore.
readonly LW_DOC_ANCORE_SEP='---'
