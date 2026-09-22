#!/usr/bin/env bash

# =============================================================================
# adr.sh — l'unico script che sa scrivere e interrogare il registro ADR
# Usage:
#   adr.sh scarta --slug <slug> --chi umano|agente --segnalazione <testo>
#                 --ancora <path> [--ancora <path>]...
#                 [--supera <id>[#<voce>]]... [--perche <testo>] [--no-commit]
#                 [< il perché su stdin, in alternativa a --perche]
#   adr.sh cerca  <ancora> [--superate]
# =============================================================================
#
# Il registro delle decisioni sta FUORI dal sistema documentale: la doc e' as-is
# e una decisione e' datata e motivata per costruzione. Formato del record, sede
# e regole di supersessione: ${CLAUDE_PLUGIN_ROOT}/docs/adr-format.md.
#
# Sede: {docs_root}/adr/, un file per record, il nome del file E' l'id
# (YYYY-MM-DD-HHMM-<slug>). Un file per record e non un file unico perche' in
# detached piu' sessioni committano nello stesso worktree: un file condiviso
# entrerebbe intero nel commit della prima sessione che lo tocca.
#
# IMMUTABILITA' — l'invariante e' una riga sola: il comando rifiuta un path che
# esiste gia' (exit 2). Una decisione superata si marca con un record NUOVO che
# nomina il vecchio in `Supera`; il vecchio resta leggibile dov'e'.
#
# Exit code per sottocomando:
#   scarta   0 record scritto
#            1 input malformato o ancora inesistente — NESSUNA scrittura
#            2 record gia' esistente — NESSUNA scrittura
#   cerca    0 almeno un record vivo trovato (elencato su stdout)
#            2 nessuno — e' il verdetto che l'agente legge prima di risollevare
#            1 errore d'uso
#
# Il `2` distingue il rifiuto di riscrittura dall'input rotto: nelle famiglie di
# exit code del repo `2` e' sempre un VERDETTO e `1` un errore. Chi chiama sa
# quindi se riprovare con altri argomenti o con un altro slug.
#
# Env letto:
#   LOOM_ADR_NOW — epoch che sostituisce `now` (solo banco di test: id e campo
#                  Data devono essere deterministici per asserire su un path)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"

ROOT="$(lw_find_project_root)"
ADR_DIR="${ROOT}/$(lw_docs_root)/adr"
ADR_REL="$(lw_docs_root)/adr"

# `die` di lib.sh esce sempre 1 e suona il TTS: qui l'exit code e' il contratto,
# e un errore d'uso non e' un evento da annunciare a voce.
fail() {  # <exit> <messaggio>
    local rc="$1"; shift
    echo "[adr] ERROR: $*" >&2
    exit "$rc"
}

# --- Normalizzazione di un'ancora ---------------------------------------------
#
# Stampa il path root-relative; return 1 se non esiste, 2 se sta fuori dal
# project root. Il path si verifica sul FILESYSTEM e non su `git ls-files`:
# e' cio' che il futuro rilevatore «path modificato dopo la data del record»
# leggera', accoppiando `test -e` a `git log --since`.
norm_ancora() {  # <path>
    local p="$1" abs
    if [[ "$p" == /* ]]; then
        abs="$p"
    elif [[ -e "${ROOT}/${p}" ]]; then
        abs="${ROOT}/${p}"
    else
        abs="${PWD}/${p}"
    fi
    abs="$(realpath -m -- "$abs" 2>/dev/null)" || return 1
    [[ -e "$abs" ]] || return 1
    case "$abs" in
        "$ROOT"/?*) printf '%s\n' "${abs#"${ROOT}/"}" ;;
        *) return 2 ;;
    esac
}

# =============================================================================
# scarta
# =============================================================================
cmd_scarta() {
    local slug="" chi="" segnalazione="" perche="" no_commit=0
    local -a ancore_raw=() supera_raw=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --slug)         slug="${2:-}"; shift 2 ;;
            --chi)          chi="${2:-}"; shift 2 ;;
            --segnalazione) segnalazione="${2:-}"; shift 2 ;;
            --ancora)       ancore_raw+=("${2:-}"); shift 2 ;;
            --supera)       supera_raw+=("${2:-}"); shift 2 ;;
            --perche)       perche="${2:-}"; shift 2 ;;
            --no-commit)    no_commit=1; shift ;;
            *) fail 1 "argomento ignoto: $1" ;;
        esac
    done

    # --- slug -----------------------------------------------------------------
    [[ -n "$slug" ]] || fail 1 "--slug obbligatorio — lo slug lo da' chi scrive, non si deriva dal testo: uno slug derivato non sarebbe prevedibile per chi deve citare il record in Supera"
    [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] \
        || fail 1 "slug fuori formato: '${slug}' (atteso [a-z0-9-], iniziale alfanumerica)"

    # --- chi ------------------------------------------------------------------
    # Senza default di proposito: lo scarto deciso da un agente e' esattamente
    # cio' che l'umano vuole poter rileggere a campione, e un default renderebbe
    # i due indistinguibili.
    case "$chi" in
        umano|agente) ;;
        "") fail 1 "--chi obbligatorio (umano|agente) — senza default: lo scarto dell'agente e' cio' che l'umano campiona" ;;
        *)  fail 1 "--chi deve essere umano|agente (ricevuto: '${chi}')" ;;
    esac

    # --- segnalazione ---------------------------------------------------------
    [[ -n "$segnalazione" ]] || fail 1 "--segnalazione obbligatoria"
    [[ "$segnalazione" == *$'\n'* ]] \
        && fail 1 "la segnalazione sta su UNA riga: e' cio' che l'agente confronta con quello che sta per risollevare"

    # --- perché: flag o stdin -------------------------------------------------
    if [[ -z "$perche" && ! -t 0 ]]; then
        perche="$(cat)"
    fi
    # trim delle righe vuote di testa e coda (la command substitution mangia gia'
    # i newline finali, ma --perche e un heredoc possono portarne di testa)
    while [[ "$perche" == $'\n'* ]]; do perche="${perche#$'\n'}"; done
    while [[ "$perche" == *$'\n' ]]; do perche="${perche%$'\n'}"; done
    [[ -n "$perche" ]] \
        || fail 1 "il perché e' obbligatorio: passalo con --perche o su stdin — uno scarto senza motivo non e' uno scarto, e' un rinvio"

    # --- ancore ---------------------------------------------------------------
    [[ ${#ancore_raw[@]} -gt 0 ]] || fail 1 "--ancora obbligatoria (almeno una): senza un path il record non e' raggiungibile da chi cerca"
    local -a ancore=()
    local a norm rc
    for a in "${ancore_raw[@]}"; do
        norm="$(norm_ancora "$a")"; rc=$?
        case "$rc" in
            0) ancore+=("$norm") ;;
            2) fail 1 "ancora fuori dal project root (${ROOT}): ${a}" ;;
            *) fail 1 "ancora inesistente: ${a} — un path che non c'e' non e' un'ancora" ;;
        esac
    done

    # --- supera ---------------------------------------------------------------
    # Ogni <id> deve esistere in adr/: un Supera verso un id inesistente e' un
    # refuso che nasconderebbe niente per sempre, in silenzio. Il frammento dopo
    # '#' NON si valida — il registro non ha ancora un parser di voci, e un
    # vincolo scritto adesso sulla loro forma sarebbe una premessa non misurata.
    local -a supera=()
    local s v id
    for s in ${supera_raw[@]+"${supera_raw[@]}"}; do
        while IFS= read -r v; do
            v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
            [[ -z "$v" ]] && continue
            id="${v%%#*}"
            [[ -n "$id" ]] || fail 1 "--supera senza id: '${v}'"
            [[ -f "${ADR_DIR}/${id}.md" ]] \
                || fail 1 "--supera nomina un record inesistente: ${id} (atteso ${ADR_REL}/${id}.md)"
            supera+=("$v")
        done < <(tr ',' '\n' <<< "$s")
    done

    # --- id e path ------------------------------------------------------------
    local now="${LOOM_ADR_NOW:-$(date +%s)}"
    local rec_id rec_data rec_file rec_rel
    rec_id="$(date -d "@${now}" '+%Y-%m-%d-%H%M' 2>/dev/null)" \
        || fail 1 "data non derivabile da LOOM_ADR_NOW='${now}'"
    rec_id="${rec_id}-${slug}"
    rec_data="$(date -d "@${now}" '+%Y-%m-%d %H:%M')"
    rec_file="${ADR_DIR}/${rec_id}.md"
    rec_rel="${ADR_REL}/${rec_id}.md"

    # L'INVARIANTE, in una riga: un record esistente non si riscrive.
    [[ -e "$rec_file" ]] && fail 2 "record gia' esistente: ${rec_rel} — un record non si modifica, una decisione superata si marca con un record nuovo che la nomina in Supera"

    mkdir -p "$ADR_DIR" || fail 1 "non riesco a creare ${ADR_REL}"

    # --- scrittura ------------------------------------------------------------
    # Il join si fa a mano e non con IFS + ${arr[*]}: un separatore di campo
    # globale riscriverebbe anche un path che contiene una virgola.
    local campo_ancore="" campo_supera="" x
    for x in "${ancore[@]}"; do campo_ancore+="${campo_ancore:+, }${x}"; done
    for x in ${supera[@]+"${supera[@]}"}; do campo_supera+="${campo_supera:+, }${x}"; done

    {
        printf '# %s\n\n' "$segnalazione"
        printf -- '- **Tipo**: scarto\n'
        printf -- '- **Data**: %s\n' "$rec_data"
        printf -- '- **Chi**: %s\n' "$chi"
        printf -- '- **Ancore**: %s\n' "$campo_ancore"
        [[ -n "$campo_supera" ]] && printf -- '- **Supera**: %s\n' "$campo_supera"
        printf '\n## Perché\n\n%s\n' "$perche"
    } > "$rec_file" || fail 1 "scrittura fallita: ${rec_rel}"

    echo "-> record scritto: ${rec_rel}"

    # --- commit ---------------------------------------------------------------
    # Committa da se', con pathspec e senza push: il chiamante tipico e' il
    # modello in chat, in una sessione detached dove nessun altro commit
    # nominera' quel file — un record non committato e' uno scarto che puo'
    # ancora sparire. Chi batcha (una skill che chiude con un commit suo) passa
    # --no-commit.
    if (( no_commit )); then
        echo "   (--no-commit: il file resta da committare)"
        return 0
    fi
    local msg_seg="$segnalazione"
    [[ ${#msg_seg} -gt 60 ]] && msg_seg="${msg_seg:0:57}..."
    lw_git_add_n_commit "adr: scarto — ${msg_seg}" "$rec_rel" >/dev/null
    case $? in
        0) echo "   committato: ${rec_rel}" ;;
        2) echo "   (nessuna modifica da committare)" ;;
        *) echo "[adr] WARNING: commit fallito, il record resta sul disco: ${rec_rel}" >&2 ;;
    esac
    return 0
}

# =============================================================================
# cerca
# =============================================================================
#
# Match TESTUALE sul record intero — segnalazione, header e perché. Una regola
# sola copre path, keyword e id task, che stanno gia' dentro il testo: un campo
# ancora tipizzato in piu' sarebbe una seconda sorgente per la stessa ricerca, e
# le due divergerebbero al primo record scritto a mano.
#
# Un id task si cerca a PAROLA INTERA — `T16` non trova `T161` — come in
# resolve-task.sh --children. Tutto il resto e' sottostringa case-insensitive.
cmd_cerca() {
    local query="" mostra_superate=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --superate) mostra_superate=1; shift ;;
            -*) fail 1 "argomento ignoto: $1" ;;
            *) [[ -n "$query" ]] && fail 1 "una sola ancora per volta (ricevuto anche: $1)"
               query="$1"; shift ;;
        esac
    done
    [[ -n "$query" ]] || fail 1 "ancora richiesta: adr.sh cerca <ancora> [--superate]"

    if [[ ! -d "$ADR_DIR" ]]; then
        echo "[adr] registro vuoto: ${ADR_REL} non esiste" >&2
        return 2
    fi

    local -a records=()
    local f
    while IFS= read -r f; do records+=("$f"); done \
        < <(find "$ADR_DIR" -maxdepth 1 -type f -name '*.md' | sort)
    if [[ ${#records[@]} -eq 0 ]]; then
        echo "[adr] registro vuoto: nessun record in ${ADR_REL}" >&2
        return 2
    fi

    # --- mappa della supersessione -------------------------------------------
    # Si costruisce sul registro INTERO, non sui soli match: un record superato
    # da uno che la query non trova resta superato.
    local -A sup_intero=() sup_voci=()
    local rid campo v tid frag
    for f in "${records[@]}"; do
        campo="$(sed -n 's/^- \*\*Supera\*\*:[[:space:]]*//p' "$f" | head -1)"
        [[ -n "$campo" ]] || continue
        rid="$(basename "$f" .md)"
        while IFS= read -r v; do
            v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
            [[ -z "$v" ]] && continue
            tid="${v%%#*}"; frag=""
            [[ "$v" == *#* ]] && frag="${v#*#}"
            if [[ -z "$frag" ]]; then
                sup_intero["$tid"]="${sup_intero[$tid]:+${sup_intero[$tid]}, }${rid}"
            else
                sup_voci["$tid"]="${sup_voci[$tid]:+${sup_voci[$tid]}, }${frag}"
            fi
        done < <(tr ',' '\n' <<< "$campo")
    done

    # --- selezione ------------------------------------------------------------
    local -a grep_opts
    if [[ "$query" =~ ^T[0-9]+$ ]]; then
        grep_opts=(-q -w -F --)
    else
        grep_opts=(-q -i -F --)
    fi

    local trovati=0 nascosti=0 id titolo chi data ancore
    for f in "${records[@]}"; do
        grep "${grep_opts[@]}" "$query" "$f" || continue
        id="$(basename "$f" .md)"

        # Superato INTERO -> fuori dalla query. Superato per VOCE -> resta, con
        # l'annotazione: nascondere un record intero perche' un altro ne supera
        # una voce sola sarebbe nascondere cio' che e' ancora vivo.
        if [[ -n "${sup_intero[$id]:-}" ]] && (( ! mostra_superate )); then
            nascosti=$((nascosti+1))
            continue
        fi

        titolo="$(sed -n '1s/^#[[:space:]]*//p' "$f")"
        chi="$(sed -n 's/^- \*\*Chi\*\*:[[:space:]]*//p' "$f" | head -1)"
        data="$(sed -n 's/^- \*\*Data\*\*:[[:space:]]*//p' "$f" | head -1)"
        ancore="$(sed -n 's/^- \*\*Ancore\*\*:[[:space:]]*//p' "$f" | head -1)"

        printf '%s · %s · %s' "$id" "${chi:-?}" "${data:-?}"
        [[ -n "${sup_intero[$id]:-}" ]] && printf '   [SUPERATO da %s]' "${sup_intero[$id]}"
        printf '\n'
        printf '  %s\n' "$titolo"
        [[ -n "$ancore" ]] && printf '  ancore: %s\n' "$ancore"
        # L'annotazione stampa i FRAMMENTI trovati nei Supera altrui, non il testo
        # della voce: non richiede un parser di voci, e resta vera quando i record
        # con voci arriveranno.
        [[ -n "${sup_voci[$id]:-}" ]] && printf '  voci superate: %s\n' "${sup_voci[$id]}"
        printf '  file: %s/%s.md\n\n' "$ADR_REL" "$id"
        trovati=$((trovati+1))
    done

    if (( trovati == 0 )); then
        # `nascosti` vale "0" quando non ce ne sono, e "0" e' una stringa non
        # vuota: il ramo si sceglie sul NUMERO, non sulla presenza della variabile.
        if (( nascosti > 0 )); then
            echo "[adr] nessun record vivo per '${query}' (${nascosti} superati, nascosti — rilancia con --superate)" >&2
        else
            echo "[adr] nessun record per '${query}'" >&2
        fi
        return 2
    fi
    (( nascosti > 0 )) && echo "[adr] ${nascosti} record superati non mostrati (--superate per vederli)" >&2
    return 0
}

# =============================================================================
# dispatch
# =============================================================================
[[ $# -gt 0 ]] || fail 1 "sottocomando richiesto: scarta | cerca"
SUB="$1"; shift
case "$SUB" in
    scarta) cmd_scarta "$@" ;;
    cerca)  cmd_cerca "$@" ;;
    *) fail 1 "sottocomando ignoto: ${SUB} (attesi: scarta, cerca)" ;;
esac
