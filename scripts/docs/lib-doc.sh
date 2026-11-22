#!/usr/bin/env bash

# =============================================================================
# lib-doc.sh — grammatica e soglia del sistema doc v2
# Usage: source "${SCRIPT_DIR}/lib-doc.sh"   (mai invocata direttamente)
# =============================================================================
#
# Proprietario UNICO di:
#   - la soglia di avviso sulle nozioni di un inbox (readonly, niente override
#     da CLI) e il parser dell'override di test LOOM_DOC_THRESHOLDS_OVERRIDE
#   - la regex del TLDR (doc_tldr, doc_tldr_var), condivisa fra i layer: riga 3 per reference/,
#     riga 4 per l'inbox — la riga e' un PARAMETRO, cosi' l'implementazione resta una
#   - il conteggio dei caratteri (doc_chars_var, doc_file_chars_var): code
#     point, indipendente dal locale della shell
#   - la precedenza di layer (doc_layer): inbox → online → offline → altro
#   - le regex del formato inbox (usate SOLO da inbox.sh)
#   - il perimetro escluso condiviso (doc_excluded): il runtime che non e' doc
#
# Ogni regex del formato vive qui e in nessun altro posto. Una primitiva che ha
# bisogno di leggere il formato inbox chiama `inbox.sh parse`, mai una propria
# regex: doc-metrics e build-index sono CONSUMER di inbox.sh, non secondi parser.
#
# Soglia: niente override da CLI. Resta un solo canale, per il banco di test:
# LOOM_DOC_THRESHOLDS_OVERRIDE ("inbox=N"). Una chiave diversa da `inbox` non
# cambia niente e lo dice su stderr.
# =============================================================================

# ---- Soglia ------------------------------------------------------------------
#
# Governa un avviso di checkpoint su un file inbox: sopra soglia il checkpoint
# stampa conteggio e soglia nella stessa riga, e prosegue.

LW_DOC_INBOX_NOZIONI=100

if [[ -n "${LOOM_DOC_THRESHOLDS_OVERRIDE:-}" ]]; then
    IFS=',' read -ra _lw_pairs <<< "$LOOM_DOC_THRESHOLDS_OVERRIDE"
    for _lw_pair in "${_lw_pairs[@]}"; do
        _lw_k="${_lw_pair%%=*}"; _lw_v="${_lw_pair#*=}"
        case "$_lw_k" in
            inbox)   LW_DOC_INBOX_NOZIONI="$_lw_v" ;;
            *) echo "[lib-doc] WARN override ignoto: ${_lw_k}" >&2 ;;
        esac
    done
    unset _lw_pairs _lw_pair _lw_k _lw_v
fi

readonly LW_DOC_INBOX_NOZIONI

# ---- TLDR --------------------------------------------------------------------
#
# L'unica implementazione dell'estrazione TLDR. La riga e' un parametro perche'
# le due sedi divergono in v2 — 3 per reference/, 4 per l'inbox — ed e' la
# ragione per cui la funzione deve essere una sola: due copie con due costanti
# diverse driftano al primo ritocco. Chiamanti: inbox.sh sulla riga 4, i lettori
# di reference/ sulla riga 3.
#
# Due forme, un'implementazione: `doc_tldr_var` assegna a una variabile del
# chiamante e non apre processi, `doc_tldr` stampa per chi lo cattura con `$(…)`.
# Dentro un ciclo sui file si usa la prima (§Lettura senza sottoprocessi). Nota:
# doc_tldr_var esegue una regex nella shell del chiamante, quindi sovrascrive il
# suo BASH_REMATCH — chi ne ha bisogno lo fotografa prima della chiamata.

doc_tldr_var() {  # <var> <file> <riga> → <var> = testo del TLDR (trim trailing), vuoto se assente
    local _dt_line _dt_t=""
    doc_line _dt_line "$2" "$3"
    if [[ "$_dt_line" =~ ^\>\ \*\*TLDR\*\*:\ (.+)$ ]]; then
        _dt_t="${BASH_REMATCH[1]}"
        _dt_t="${_dt_t%"${_dt_t##*[![:space:]]}"}"
    fi
    printf -v "$1" '%s' "$_dt_t"
}

doc_tldr() {  # <file> <riga> → stampa il TLDR (trim trailing), niente se assente
    local _dt_out
    doc_tldr_var _dt_out "$1" "$2"
    [[ -n "$_dt_out" ]] && printf '%s\n' "$_dt_out"
    return 0
}

# ---- Lettura senza sottoprocessi ---------------------------------------------
#
# In Git Bash su Windows ogni sostituzione di comando e' un fork emulato, piu'
# un exec se lancia un binario: costa decine di volte quello che costa su Linux,
# e un `$(sed -n 3p "$f")` dentro un ciclo sui file diventa il costo dominante
# dello script, non la lettura del file. Qui la riga si legge con
# `read` e si assegna con `printf -v` alla variabile che il chiamante nomina:
# nessun processo. I locali portano un prefisso perche' `printf -v` su un nome
# uguale a un locale scriverebbe il locale invece della variabile del chiamante.
#
# Fine riga CRLF: `read` tiene il `\r`, il `sed` di Git Bash legge in modo testo e
# lo toglie. Un checkout Windows con core.autocrlf=true e senza .gitattributes ha
# i file in CRLF, e una riga marker con il `\r` in coda fallirebbe su un token
# `drainable\r`. doc_line toglie quindi un `\r` prima del newline, come quel sed,
# e su Linux come su Windows: lo stesso file si legge allo stesso modo ovunque.

doc_line() {  # <var> <file> <riga> → <var> = riga N del file, vuota se assente (come `sed -n Np`)
    local _dl_line="" _dl_n=0
    if [[ -r "$2" ]]; then
        while (( _dl_n < $3 )) && IFS= read -r _dl_line; do
            _dl_n=$((_dl_n+1))
        done < "$2"
        # read fallisce sull'ultima riga senza newline finale ma la assegna:
        # se e' la riga N la si tiene, come fa sed, e senza toccarne un `\r`
        # (non e' un CRLF). Fallito prima, il file ha meno di N righe.
        if (( _dl_n == $3 )); then
            _dl_line="${_dl_line%$'\r'}"
        elif (( _dl_n + 1 < $3 )); then
            _dl_line=""
        fi
    fi
    printf -v "$1" '%s' "$_dl_line"
}

# ---- Conteggio dei caratteri -------------------------------------------------
#
# Ogni misura del sistema doc e' in caratteri, e un carattere qui e' un code
# point: il numero che `wc -m` da' su Linux con glibc in locale UTF-8. Ne' `${#v}`
# di bash ne' `wc -m` lo danno ovunque, perche' dipendono dal locale della shell
# che li esegue. In Git Bash su Windows con LANG, LC_CTYPE e LC_ALL vuote contano
# byte: una lettera accentata o una freccia vale 2-3, un'emoji 4, e un TLDR
# italiano di 494 caratteri ne misura 523. Con un locale UTF-8 contano unita'
# UTF-16, perche' in MSYS `wchar_t` e' a 16 bit: un'emoji fuori dal piano base
# vale 2. Nessun locale da' code point, quindi impostarlo negli script non basta.
#
# Il conteggio qui non chiede niente al locale: dentro la funzione LC_ALL=C fa
# vedere a bash i byte, si tolgono i byte di continuazione UTF-8 (0x80-0xBF) e si
# contano quelli che restano, perche' ogni carattere ha uno e un solo byte di
# testa. `local` restituisce al chiamante il suo locale all'uscita. Su testo
# UTF-8 valido il numero coincide con `wc -m` su Linux, anche sui `\r` di un file
# CRLF, che entrambi contano.
#
# Due forme, nessun processo (§Lettura senza sottoprocessi): `doc_chars_var` per
# una stringa, `doc_file_chars_var` per un file intero, letto con `read -d ''`,
# che a differenza di `$(…)` non perde i newline finali. Un file con un byte NUL
# si misura fino al NUL: la doc e' testo, e il NUL non ci compare.

_LW_DOC_UTF8_CONT=$'[\x80-\xbf]'
readonly _LW_DOC_UTF8_CONT

doc_chars_var() {  # <var> <stringa> → <var> = caratteri (code point UTF-8) della stringa
    local LC_ALL=C
    local _dc_s="${2//$_LW_DOC_UTF8_CONT/}"
    printf -v "$1" '%s' "${#_dc_s}"
}

doc_file_chars_var() {  # <var> <file> → <var> = caratteri (code point UTF-8) del file, 0 se illeggibile
    local LC_ALL=C
    local _dfc_t=""
    [[ -r "$2" ]] && { IFS= read -r -d '' _dfc_t < "$2" || true; }
    _dfc_t="${_dfc_t//$_LW_DOC_UTF8_CONT/}"
    printf -v "$1" '%s' "${#_dfc_t}"
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

# Riga intera della lista, come `grep -qxF`, ma senza processo: chi lo chiama lo
# fa una volta per file (§Lettura senza sottoprocessi).
doc_is_online() {  # <rel-to-project-root>
    [[ -z "$LW_DOC_ONLINE_LIST" ]] && return 1
    [[ $'\n'"$LW_DOC_ONLINE_LIST"$'\n' == *$'\n'"$1"$'\n'* ]]
}

# Due forme come per il TLDR: `doc_layer_var` assegna senza processi, `doc_layer`
# stampa per chi cattura con `$(…)`.
doc_layer_var() {  # <var> <rel-to-project-root> → <var> = inbox|online|offline|altro
    local _dly_layer
    if [[ "$2" == */inbox/* ]]; then
        _dly_layer="inbox"
    elif doc_is_online "$2"; then
        _dly_layer="online"
    elif [[ "$2" == */reference/* ]]; then
        _dly_layer="offline"
    else
        _dly_layer="altro"
    fi
    printf -v "$1" '%s' "$_dly_layer"
}

doc_layer() {  # <rel-to-project-root> → inbox|online|offline|altro
    local _dl_out
    doc_layer_var _dl_out "$1"
    echo "$_dl_out"
}

# ---- Perimetro escluso condiviso ---------------------------------------------
#
# SOLO cio' che ogni chiamante esclude: il runtime che non e' doc. Un'esclusione
# che vale per un chiamante solo e' una regola di quel chiamante e sta scritta
# li' — INDEX.md lo esclude solo build-index.sh, che lo rigenera.
#
# adr/ e' il registro delle decisioni (docs/adr-format.md): sta sotto la docs-root
# perche' e' stato di task, come tasks/, ma non e' doc — nessun layer e nessuna
# misura. Senza l'esclusione ogni record entrerebbe nelle misure di doc-metrics
# come un file di doc, con un layer che non ha.
#
# triage/ e' il file degli scenari di triage (docs/triage-format.md): stessa
# natura del registro ADR — record datati, citati alla lettera, append-only — e
# stessa ragione dell'esclusione.

doc_excluded() {  # <rel-path> → 0 se fuori dal perimetro doc
    case "$1" in
        */tasks/*|tasks/*|*/current-task.md|current-task.md) return 0 ;;
        */adr/*|adr/*) return 0 ;;
        */triage/*|triage/*) return 0 ;;
    esac
    return 1
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
