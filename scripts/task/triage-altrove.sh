#!/usr/bin/env bash

# =============================================================================
# triage-altrove.sh — un'uscita di triage eseguita in un altro progetto:
#                     da quale cartella parte la sessione figlia, e il gate sul suo ritorno
# Usage:
#   triage-altrove.sh risolvi  <nome>
#   triage-altrove.sh prima    --dest <dir> --atteso commit|task
#   triage-altrove.sh verifica --dest <dir> --prima <sha> --atteso commit|task
#                              [--hash <sha>]...
# =============================================================================
#
# Stato e requisiti rinviati: factory · T12 §Custodia — un limite del triage si segnala lì, non si apre una task qui.
#
# Una segnalazione decisa nel report di un progetto puo' riguardarne un altro. Chi
# la esegue e' una sessione figlia, `claude -p` lanciata nella cartella del
# destinatario: carica CLAUDE.md, settings, skill e regole di commit del
# destinatario, e scrive il progetto che possiede il confine invece del chiamante
# che lo aggira da Bash. Il lancio sta nel body delle skill; questo script fa le
# due cose deterministiche che lo circondano. Regola e formato:
# ${CLAUDE_PLUGIN_ROOT}/docs/triage-format.md §L'uscita eseguita in un altro progetto.
#
# RISOLVI — dal nome che porta la segnalazione (o che l'umano dice) alla cartella,
# sul registry dei progetti: prima per `id`, poi per nome della cartella. Servono
# entrambe le chiavi perche' non coincidono sempre (`selectio-legacy` sta in
# `selectio-v2_legacy`), e l'umano e le segnalazioni usano l'una o l'altra. Un
# risultato solo stampa la cartella; nessuno o piu' d'uno e' un verdetto — chi
# chiama chiede all'umano e non lancia. Il registry e' dconf, cioe' coupling di
# macchina: sta qui, e le skill non lo nominano.
#
# PRIMA — fotografa `HEAD` del destinatario prima del lancio e controlla che
# l'uscita lì possa partire: un commit vuole un repo git con almeno un commit, una
# task vuole anche `{docs_root}/tasks.md` del destinatario, perche' senza lista
# task non c'e' dove aprirla.
#
# VERIFICA — il ritorno del figlio e' self-report: prosa con un hash corto dentro.
# Il gate non parte dal racconto, legge l'intervallo `<prima>..HEAD` del
# destinatario: `commit` e' verde con almeno un commit nuovo, `task` se un commit
# dell'intervallo aggiunge un task file `T<N>-*.md` sotto la docs-root e
# `tasks.md` in HEAD porta la riga di quell'id — l'id si ricava dal file aggiunto.
# Un gate che partisse dall'hash dichiarato sarebbe verde anche su un commit
# vecchio citato da un figlio che non ha fatto niente. Il dichiarato serve da
# SELETTORE: ogni --hash deve stare nell'intervallo, e quando c'e' il gate guarda
# solo quei commit — restringe il caso debole, una sessione parallela che committa
# nel destinatario nel frattempo. Per la stessa ragione due figli sullo stesso
# destinatario girano in sequenza: condividono l'intervallo e il contatore degli id.
#
# `--atteso` dice cosa l'esecuzione produce, non l'uscita: «subito» e' `commit`,
# «task» aperta con create-task e' `task`, «task» che nelle parole dell'umano
# aggiunge un DLV a una task esistente e' `commit`.
#
# Exit code per sottocomando:
#   risolvi  0 una cartella, stampata · 2 nessuna o piu' d'una, o registrata ma
#              assente — si chiede all'umano · 1 errore d'uso o registry assente
#   prima    0 sha di HEAD stampato · 2 l'uscita lì non puo' partire · 1 errore d'uso
#   verifica 0 verde · 2 rosso · 1 errore d'uso
#
# Env letto:
#   LOOM_TRIAGE_REGISTRY — file `id<TAB>dir`, una riga per progetto, al posto di
#                          dconf (solo banco di test)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config/lib-config.sh
source "${SCRIPT_DIR}/../config/lib-config.sh"

fail() {  # <exit> <messaggio>
    local rc="$1"; shift
    echo "[triage-altrove] ERROR: $*" >&2
    exit "$rc"
}

# Il registry come righe `id<TAB>dir`, da dconf o dal file di banco.
registry() {
    if [[ -n "${LOOM_TRIAGE_REGISTRY:-}" ]]; then
        [[ -f "$LOOM_TRIAGE_REGISTRY" ]] || fail 1 "LOOM_TRIAGE_REGISTRY punta a un file assente: ${LOOM_TRIAGE_REGISTRY}"
        grep -v '^[[:space:]]*$' "$LOOM_TRIAGE_REGISTRY"
        return 0
    fi
    reg_available || fail 1 "registry dei progetti non disponibile (dconf assente): la cartella del destinatario va chiesta all'umano"
    local id
    while IFS= read -r id; do
        printf '%s\t%s\n' "$id" "$(reg_get "$id" dir)"
    done < <(reg_list_projects)
}

# docs-root del destinatario: il suo file config, mai l'ambiente del chiamante.
dest_docs_root() {  # <dir>
    ( unset LOOM_DOCS_ROOT; PROJECT_ROOT="$1" lw_docs_root )
}

# --dest: una cartella che e' la radice di un repo git con almeno un commit.
check_dest() {  # <dir>
    local dest="$1" top
    [[ -n "$dest" ]] || fail 1 "--dest obbligatorio: la cartella del progetto destinazione"
    [[ -d "$dest" ]] || fail 2 "destinazione assente: ${dest}"
    top="$(git -C "$dest" rev-parse --show-toplevel 2>/dev/null)" \
        || fail 2 "destinazione fuori da un repo git: ${dest}"
    [[ "$(cd "$dest" && pwd -P)" == "$(cd "$top" && pwd -P)" ]] \
        || fail 2 "la destinazione non e' la radice del suo repo (${top}): la sessione figlia parte dalla radice"
    git -C "$dest" rev-parse --verify -q HEAD >/dev/null \
        || fail 2 "il repo destinazione non ha commit: non c'e' un HEAD da fotografare"
}

check_atteso() {  # <atteso>
    case "$1" in
        commit|task) ;;
        "") fail 1 "--atteso obbligatorio (commit|task)" ;;
        *)  fail 1 "--atteso deve essere commit|task (ricevuto: '$1')" ;;
    esac
}

# =============================================================================
cmd_risolvi() {
    [[ $# -eq 1 && -n "$1" ]] || fail 1 "uso: risolvi <nome> — l'id del progetto o il nome della sua cartella"
    local nome="$1" righe trovati
    righe="$(registry)" || exit $?
    # Prima l'id; solo se nessun id combacia, il nome della cartella.
    trovati="$(awk -F'\t' -v n="$nome" '$1 == n { print $2 }' <<< "$righe")"
    if [[ -z "$trovati" ]]; then
        trovati="$(awk -F'\t' -v n="$nome" '{ k = $2; sub(/\/+$/, "", k); sub(/.*\//, "", k) } k == n { print $2 }' <<< "$righe")"
    fi
    local quanti=0
    [[ -n "$trovati" ]] && quanti="$(grep -c . <<< "$trovati")"
    if (( quanti == 0 )); then
        echo "[triage-altrove] nessun progetto registrato con id o cartella '${nome}' — chiedi la cartella all'umano" >&2
        exit 2
    fi
    if (( quanti > 1 )); then
        echo "[triage-altrove] '${nome}' combacia con ${quanti} progetti — chiedi all'umano quale:" >&2
        sed 's/^/  /' <<< "$trovati" >&2
        exit 2
    fi
    [[ -d "$trovati" ]] \
        || { echo "[triage-altrove] '${nome}' e' registrato in ${trovati}, che non esiste — chiedi all'umano" >&2; exit 2; }
    echo "$trovati"
}

# =============================================================================
cmd_prima() {
    local dest="" atteso=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dest)   dest="${2:-}"; shift 2 ;;
            --atteso) atteso="${2:-}"; shift 2 ;;
            *) fail 1 "argomento ignoto: $1" ;;
        esac
    done
    check_atteso "$atteso"
    check_dest "$dest"
    if [[ "$atteso" == task ]]; then
        local docs; docs="$(dest_docs_root "$dest")"
        [[ -f "${dest}/${docs}/tasks.md" ]] \
            || fail 2 "il destinatario non ha una lista task (${docs}/tasks.md): una task lì non ha dove aprirsi"
    fi
    git -C "$dest" rev-parse HEAD
}

# =============================================================================
cmd_verifica() {
    local dest="" prima="" atteso=""
    local -a dichiarati=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dest)   dest="${2:-}"; shift 2 ;;
            --prima)  prima="${2:-}"; shift 2 ;;
            --atteso) atteso="${2:-}"; shift 2 ;;
            --hash)   dichiarati+=("${2:-}"); shift 2 ;;
            *) fail 1 "argomento ignoto: $1" ;;
        esac
    done
    check_atteso "$atteso"
    [[ -n "$prima" ]] || fail 1 "--prima obbligatorio: lo sha che \`prima\` ha stampato prima del lancio"
    [[ -d "$dest" ]] && git -C "$dest" rev-parse --verify -q HEAD >/dev/null \
        || fail 1 "destinazione non verificabile: ${dest:-<vuota>} non e' un repo git con commit"
    local base
    base="$(git -C "$dest" rev-parse --verify -q "${prima}^{commit}")" \
        || fail 1 "--prima non e' un commit del destinatario: ${prima}"

    rosso() { echo "ROSSO: $*"; exit 2; }

    git -C "$dest" merge-base --is-ancestor "$base" HEAD \
        || rosso "HEAD del destinatario non discende da ${prima:0:12}: la storia e' stata riscritta durante il lancio"
    local -a intervallo=()
    mapfile -t intervallo < <(git -C "$dest" rev-list --reverse "${base}..HEAD")
    (( ${#intervallo[@]} > 0 )) || rosso "nessun commit nuovo nel destinatario dopo ${prima:0:12}"

    # Il dichiarato restringe, non sostituisce: ogni hash deve stare nell'intervallo.
    local -a esaminati=()
    local h sha c
    if (( ${#dichiarati[@]} > 0 )); then
        for h in "${dichiarati[@]}"; do
            sha="$(git -C "$dest" rev-parse --verify -q "${h}^{commit}")" \
                || rosso "il commit dichiarato ${h} non esiste nel destinatario"
            local dentro=0
            for c in "${intervallo[@]}"; do [[ "$c" == "$sha" ]] && { dentro=1; break; }; done
            (( dentro )) || rosso "il commit dichiarato ${h} non e' nato dopo il lancio (fuori da ${prima:0:12}..HEAD)"
            esaminati+=("$sha")
        done
    else
        esaminati=("${intervallo[@]}")
    fi
    for c in "${esaminati[@]}"; do
        echo "COMMIT ${c:0:12} $(git -C "$dest" log -1 --format=%s "$c")"
    done

    if [[ "$atteso" == task ]]; then
        local docs path id n=0
        docs="$(dest_docs_root "$dest")"
        while IFS= read -r path; do
            [[ "$path" =~ ^"${docs}"/tasks/(T[0-9]+)-[^/]+\.md$ ]] || continue
            id="${BASH_REMATCH[1]}"
            n=$((n+1))
            git -C "$dest" cat-file -e "HEAD:${path}" 2>/dev/null \
                || rosso "il task file ${path} e' stato aggiunto ma in HEAD non c'e' piu'"
            git -C "$dest" show "HEAD:${docs}/tasks.md" 2>/dev/null \
                | grep -qE "^\|[[:space:]]*${id}[[:space:]]*\|" \
                || rosso "la riga di ${id} manca in ${docs}/tasks.md (HEAD)"
            echo "TASK ${id} ${path}"
        done < <(for c in "${esaminati[@]}"; do
                     git -C "$dest" diff-tree --no-commit-id --name-only --diff-filter=A -r "$c"
                 done | sort -u)
        (( n > 0 )) || rosso "nessun task file ${docs}/tasks/T<N>-*.md aggiunto nei commit esaminati"
    fi
    echo "VERDE"
}

# =============================================================================
[[ $# -gt 0 ]] || fail 1 "sottocomando richiesto: risolvi | prima | verifica"
SUB="$1"; shift
case "$SUB" in
    risolvi)  cmd_risolvi "$@" ;;
    prima)    cmd_prima "$@" ;;
    verifica) cmd_verifica "$@" ;;
    *) fail 1 "sottocomando ignoto: ${SUB} (attesi: risolvi, prima, verifica)" ;;
esac
