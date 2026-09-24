#!/usr/bin/env bash

# =============================================================================
# triage.sh — l'unico script che sa scrivere e contare gli scenari di triage
# Usage:
#   triage.sh scenario --slug <slug> --uscita subito|task|scarto --chi umano|agente
#                      --momento flusso|posteriori --skill <nome>
#                      [--progetto <id>] [--sessione <id>]
#                      [--ancora <path>]... [--no-commit]
#                      [--segnalazione <testo>] [--perche <testo>]
#                      [< riga 1 = la segnalazione, righe dopo = il perché dello scarto]
#   triage.sh conta    [--dal <YYYY-MM-DD[ HH:MM]>] [--sessione <id>]
# =============================================================================
#
# Stato e requisiti rinviati: factory · T12 §Custodia — un limite del triage si
# segnala lì, non si apre una task qui.
#
# Questa e' la v0 di una feature progettata in factory: cio' che non fa e' scritto
# nel custode col segnale che lo renderebbe dovuto. Chi urta un limite usando gli
# scenari non ricostruisce da se' cosa manca e non apre una task in questo repo:
# il piano di crescita sta in un posto solo, e la riga sopra dice quale. Sta
# nell'artefatto e non nella doc perche' la doc e' as-is e non ammette id di task,
# e non in un task file perche' clean-tasks lo purga.
#
# Uno SCENARIO e' la decisione presa su una segnalazione del report di fine skill:
# la segnalazione alla lettera, l'uscita (subito|task|scarto), chi l'ha presa.
# Formato del record, sede e regole: ${CLAUDE_PLUGIN_ROOT}/docs/triage-format.md.
#
# Sede: {docs_root}/triage/, un file per record, il nome del file E' l'id
# (YYYY-MM-DD-HHMM-<slug>). Un file per record e non un file unico perche' chi
# scrive e' una sessione detached: un file condiviso entrerebbe intero nel commit
# della prima sessione che lo tocca, record altrui compresi.
#
# LA SEGNALAZIONE ARRIVA SU STDIN, riga 1; le righe dopo sono il perché dello
# scarto. Un heredoc col delimitatore fra apici e' l'unico canale che porta un
# testo arbitrario intatto — fra virgolette doppie la shell eseguirebbe i backtick,
# fra apici singoli ogni apostrofo va spezzato a mano. Riga 1 e' scritta byte per
# byte nella riga 1 del record: e' la chiave con cui il transcript si accoppia allo
# scenario. `--segnalazione` e `--perche` restano per chi chiama da uno script;
# con `--segnalazione` lo stdin non si legge affatto.
#
# CONTRATTO ASIMMETRICO — l'agente non scarta: uno scarto con --chi agente e' un
# rifiuto, prima di ogni scrittura. Fra le tre uscite e' l'unico errore che nessuno
# recupera: una task in piu' si cancella, un subito sbagliato si ripristina con un
# diff, uno scarto sbagliato e' un segnale perso.
#
# NESSUN DEFAULT: nessun flag scrive un record per una segnalazione non decisa.
# Uno scenario e' sempre una risposta vera; il recupero delle segnalazioni senza
# risposta e' un'operazione a posteriori (--momento posteriori), non del flusso.
#
# SCARTO → REGISTRO ADR. Sequenza fissa: valida tutto (anche il perché, e che ne'
# triage/<id>.md ne' adr/<id>.md esistano) → `adr.sh scarta --no-commit` con lo
# stesso slug e lo stesso istante → scenario col campo ADR preso dall'output di
# adr.sh → un commit solo coi due file. La validazione precede la chiamata: su un
# input sbagliato non si scrive niente, ne' lo scenario ne' il record ADR.
#
# APPEND-ONLY: un path che esiste gia' e' un rifiuto (exit 2). Una decisione che
# ne ribalta un'altra e' un record nuovo; i due si accoppiano per Sessione + riga 1.
#
# Exit code per sottocomando:
#   scenario 0 scenario scritto (e record ADR, sullo scarto)
#            1 input malformato, scarto con chi = agente, ancora inesistente,
#              progetto o sessione non risolvibili — NESSUNA scrittura
#            2 scenario o record ADR gia' esistenti con lo stesso id — NESSUNA
#              scrittura
#   conta    0 tabella stampata (anche a zero record: 0 e' un numero, non un verdetto)
#            1 errore d'uso
#
# Nelle famiglie di exit code del repo `2` e' sempre un VERDETTO e `1` un errore:
# chi chiama sa se riprovare con altri argomenti o con un altro slug.
#
# Env letto:
#   CLAUDE_CODE_SESSION_ID — fonte di Sessione (override: --sessione)
#   LOOM_TRIAGE_NOW        — epoch che sostituisce `now` (solo banco di test);
#                            passato ad adr.sh come LOOM_ADR_NOW, cosi' la coppia
#                            scenario + record ADR ha lo stesso id
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"

ADR_SH="${SCRIPT_DIR}/adr.sh"
ROOT="$(lw_find_project_root)"
DOCS_ROOT="$(lw_docs_root)"
TRIAGE_DIR="${ROOT}/${DOCS_ROOT}/triage"
TRIAGE_REL="${DOCS_ROOT}/triage"
ADR_DIR="${ROOT}/${DOCS_ROOT}/adr"
ADR_REL="${DOCS_ROOT}/adr"

# `die` di lib.sh esce sempre 1 e suona il TTS: qui l'exit code e' il contratto,
# e un errore d'uso non e' un evento da annunciare a voce.
fail() {  # <exit> <messaggio>
    local rc="$1"; shift
    echo "[triage] ERROR: $*" >&2
    exit "$rc"
}

# =============================================================================
# scenario
# =============================================================================
cmd_scenario() {
    local slug="" uscita="" chi="" momento="" skill="" progetto="" sessione=""
    local segnalazione="" perche="" no_commit=0 seg_flag=0 perche_flag=0
    local -a ancore=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --slug)         slug="${2:-}"; shift 2 ;;
            --uscita)       uscita="${2:-}"; shift 2 ;;
            --chi)          chi="${2:-}"; shift 2 ;;
            --momento)      momento="${2:-}"; shift 2 ;;
            --skill)        skill="${2:-}"; shift 2 ;;
            --progetto)     progetto="${2:-}"; shift 2 ;;
            --sessione)     sessione="${2:-}"; shift 2 ;;
            --ancora)       ancore+=("${2:-}"); shift 2 ;;
            --segnalazione) segnalazione="${2:-}"; seg_flag=1; shift 2 ;;
            --perche)       perche="${2:-}"; perche_flag=1; shift 2 ;;
            --no-commit)    no_commit=1; shift ;;
            # Nessun --default: la segnalazione non decisa non produce un record.
            *) fail 1 "argomento ignoto: $1" ;;
        esac
    done

    # --- uscita e chi: prima di tutto, e' il contratto asimmetrico ------------
    case "$uscita" in
        subito|task|scarto) ;;
        "") fail 1 "--uscita obbligatoria (subito|task|scarto) — senza default: una segnalazione non decisa non produce uno scenario" ;;
        *)  fail 1 "--uscita deve essere subito|task|scarto (ricevuto: '${uscita}')" ;;
    esac
    case "$chi" in
        umano|agente) ;;
        "") fail 1 "--chi obbligatorio (umano|agente) — senza default: separa il corpus dell'umano dal campione delle decisioni dell'agente" ;;
        *)  fail 1 "--chi deve essere umano|agente (ricevuto: '${chi}')" ;;
    esac
    if [[ "$uscita" == scarto && "$chi" == agente ]]; then
        fail 1 "l'agente non scarta: uno scarto sbagliato e' un segnale perso che nessuno recupera — riporta la segnalazione e lascia la decisione all'umano"
    fi

    # --- momento, skill, slug -------------------------------------------------
    case "$momento" in
        flusso|posteriori) ;;
        "") fail 1 "--momento obbligatorio (flusso|posteriori) — senza default: nel flusso «subito» e' operativo, a posteriori e' solo un esito" ;;
        *)  fail 1 "--momento deve essere flusso|posteriori (ricevuto: '${momento}')" ;;
    esac
    [[ -n "$skill" ]] || fail 1 "--skill obbligatoria: il nome della skill del report"
    [[ "$skill" =~ ^[a-z0-9][a-z0-9-]*$ ]] \
        || fail 1 "skill fuori formato: '${skill}' (atteso [a-z0-9-])"
    [[ -n "$slug" ]] || fail 1 "--slug obbligatorio — lo slug lo da' chi scrive, e sullo scarto nomina anche il record ADR"
    [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] \
        || fail 1 "slug fuori formato: '${slug}' (atteso [a-z0-9-], iniziale alfanumerica)"

    # --- progetto e sessione: flag, poi ambiente; assenti = rifiuto -----------
    if [[ -z "$progetto" ]]; then
        local cfg="${ROOT}/.claude/loom-works.json"
        [[ -f "$cfg" ]] && progetto="$(jq -r '.id // empty' "$cfg" 2>/dev/null)"
    fi
    [[ -n "$progetto" ]] \
        || fail 1 "progetto non risolvibile: nessun --progetto e nessun id in .claude/loom-works.json"
    [[ "$progetto" =~ ^[A-Za-z0-9._-]+$ ]] \
        || fail 1 "progetto fuori formato: '${progetto}'"
    [[ -n "$sessione" ]] || sessione="${CLAUDE_CODE_SESSION_ID:-}"
    [[ -n "$sessione" ]] \
        || fail 1 "sessione non risolvibile: nessun --sessione e CLAUDE_CODE_SESSION_ID assente — un valore di comodo renderebbe invisibile l'ambiente che non la porta"
    [[ "$sessione" =~ ^[A-Za-z0-9._:-]+$ ]] \
        || fail 1 "sessione fuori formato: '${sessione}'"

    # --- segnalazione e perché: flag, oppure stdin ----------------------------
    # Grammatica di stdin fissa: riga 1 = la segnalazione, il resto = il perché.
    # Si legge solo se --segnalazione manca: con due canali per lo stesso campo
    # non si saprebbe quale vince.
    if (( ! seg_flag )) && [[ ! -t 0 ]]; then
        local input
        input="$(cat)"
        if [[ "$input" == *$'\n'* ]]; then
            segnalazione="${input%%$'\n'*}"
            local resto="${input#*$'\n'}"
            if [[ -n "${resto//[[:space:]]/}" ]]; then
                (( perche_flag )) && fail 1 "perché passato due volte: su stdin dopo la riga 1 e con --perche"
                perche="$resto"
            fi
        else
            segnalazione="$input"
        fi
    fi
    [[ -n "$segnalazione" ]] \
        || fail 1 "segnalazione obbligatoria: riga 1 di stdin (heredoc fra apici) o --segnalazione"
    [[ "$segnalazione" == *$'\n'* ]] \
        && fail 1 "la segnalazione sta su UNA riga: e' la riga 1 del record, citata alla lettera"

    # trim delle righe vuote di testa e coda del perché
    while [[ "$perche" == $'\n'* ]]; do perche="${perche#$'\n'}"; done
    while [[ "$perche" == *$'\n' ]]; do perche="${perche%$'\n'}"; done

    # --- perché e ancore: solo sullo scarto -----------------------------------
    # Il record di subito e task non ha un campo dove metterli: accettarli li
    # perderebbe in silenzio.
    if [[ "$uscita" == scarto ]]; then
        [[ -n "${perche//[[:space:]]/}" ]] \
            || fail 1 "lo scarto vuole il perché: righe di stdin dopo la segnalazione, o --perche — uno scarto senza motivo non e' uno scarto, e' un rinvio"
        [[ ${#ancore[@]} -gt 0 ]] \
            || fail 1 "lo scarto vuole almeno un --ancora: il record ADR senza un path non e' raggiungibile da chi cerca"
    else
        [[ -n "${perche//[[:space:]]/}" ]] \
            && fail 1 "il perché vale solo con --uscita scarto: lo scenario di '${uscita}' non ha dove scriverlo"
        [[ ${#ancore[@]} -gt 0 ]] \
            && fail 1 "--ancora vale solo con --uscita scarto: lo scenario di '${uscita}' non ha dove scriverla"
    fi

    # --- id e path ------------------------------------------------------------
    local now="${LOOM_TRIAGE_NOW:-$(date +%s)}"
    local rec_id rec_data rec_file rec_rel
    rec_id="$(date -d "@${now}" '+%Y-%m-%d-%H%M' 2>/dev/null)" \
        || fail 1 "data non derivabile da LOOM_TRIAGE_NOW='${now}'"
    rec_id="${rec_id}-${slug}"
    rec_data="$(date -d "@${now}" '+%Y-%m-%d %H:%M')"
    rec_file="${TRIAGE_DIR}/${rec_id}.md"
    rec_rel="${TRIAGE_REL}/${rec_id}.md"

    # L'INVARIANTE: un record esistente non si riscrive — e sullo scarto vale anche
    # per il record ADR che porterebbe lo stesso id.
    [[ -e "$rec_file" ]] \
        && fail 2 "scenario gia' esistente: ${rec_rel} — uno scenario non si riscrive, scegli un altro slug"
    if [[ "$uscita" == scarto && -e "${ADR_DIR}/${rec_id}.md" ]]; then
        fail 2 "record ADR gia' esistente con lo stesso id: ${ADR_REL}/${rec_id}.md — scegli un altro slug"
    fi

    # --- scarto: prima il record ADR ------------------------------------------
    local adr_id="" adr_rel="" adr_out adr_rc
    if [[ "$uscita" == scarto ]]; then
        local -a adr_args=(scarta --slug "$slug" --chi "$chi" --segnalazione "$segnalazione"
                           --perche "$perche" --no-commit)
        local a
        for a in "${ancore[@]}"; do adr_args+=(--ancora "$a"); done
        adr_out="$(LOOM_ADR_NOW="$now" "$ADR_SH" "${adr_args[@]}" < /dev/null 2>&1)"
        adr_rc=$?
        if (( adr_rc != 0 )); then
            printf '%s\n' "$adr_out" >&2
            fail "$adr_rc" "adr.sh scarta ha rifiutato lo scarto: nessuno scenario scritto"
        fi
        adr_rel="$(sed -n 's/^-> record scritto: //p' <<< "$adr_out" | head -1)"
        adr_id="$(basename "$adr_rel" .md)"
        if [[ -z "$adr_rel" || ! -f "${ROOT}/${adr_rel}" ]]; then
            fail 1 "adr.sh non ha dichiarato il record scritto (output: ${adr_out})"
        fi
    fi

    # --- scrittura dello scenario ---------------------------------------------
    if ! mkdir -p "$TRIAGE_DIR" || ! {
        printf '# %s\n\n' "$segnalazione"
        printf -- '- **Uscita**: %s\n' "$uscita"
        printf -- '- **Chi**: %s\n' "$chi"
        printf -- '- **Momento**: %s\n' "$momento"
        printf -- '- **Skill**: %s\n' "$skill"
        printf -- '- **Progetto**: %s\n' "$progetto"
        printf -- '- **Sessione**: %s\n' "$sessione"
        printf -- '- **Data**: %s\n' "$rec_data"
        [[ -n "$adr_id" ]] && printf -- '- **ADR**: %s\n' "$adr_id"
        true
    } > "$rec_file"; then
        # Il record ADR e' appena nato, non committato, e senza il suo scenario
        # sarebbe uno scarto orfano: si toglie. L'immutabilita' riguarda un record
        # consegnato, non quello che questa stessa invocazione non ha finito.
        rm -f -- "$rec_file"
        [[ -n "$adr_rel" ]] && rm -f -- "${ROOT}/${adr_rel}"
        fail 1 "scrittura fallita: ${rec_rel}"
    fi

    echo "-> scenario scritto: ${rec_rel}"
    [[ -n "$adr_rel" ]] && echo "-> record ADR: ${adr_rel}"

    # --- commit ---------------------------------------------------------------
    # Da se', con pathspec e senza push: il chiamante tipico e' il modello in chat,
    # in una sessione detached — uno scenario non committato puo' ancora sparire.
    # Chi batcha passa --no-commit e committa i path stampati sopra.
    if (( no_commit )); then
        echo "   (--no-commit: i file restano da committare)"
        return 0
    fi
    local msg_seg="$segnalazione"
    [[ ${#msg_seg} -gt 60 ]] && msg_seg="${msg_seg:0:57}..."
    local -a paths=("$rec_rel")
    [[ -n "$adr_rel" ]] && paths+=("$adr_rel")
    lw_git_add_n_commit "triage: ${uscita} — ${msg_seg}" "${paths[@]}" >/dev/null
    case $? in
        0) echo "   committato: ${paths[*]}" ;;
        2) echo "   (nessuna modifica da committare)" ;;
        *) echo "[triage] WARNING: commit fallito, i file restano sul disco: ${paths[*]}" >&2 ;;
    esac
    return 0
}

# =============================================================================
# conta
# =============================================================================
#
# Le misure del custode sono conteggi per campo e per data. Una tabella a tab,
# una riga per chiave, sempre le stesse righe anche a zero: chi misura legge una
# cella con `awk -F'\t' '$1=="scarto.agente"{print $2}'` senza sapere in anticipo
# quali combinazioni esistono. Con --dal si aggiunge la colonna dei record da
# quella data in poi — il conteggio «dall'ultima iterazione».
cmd_conta() {
    local dal="" sessione=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dal)      dal="${2:-}"; shift 2 ;;
            --sessione) sessione="${2:-}"; shift 2 ;;
            *) fail 1 "argomento ignoto: $1" ;;
        esac
    done
    if [[ -n "$dal" ]]; then
        [[ "$dal" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}(\ [0-9]{2}:[0-9]{2})?$ ]] \
            || fail 1 "--dal fuori formato: '${dal}' (atteso YYYY-MM-DD o 'YYYY-MM-DD HH:MM')"
    fi

    local -a records=()
    local f
    if [[ -d "$TRIAGE_DIR" ]]; then
        while IFS= read -r f; do records+=("$f"); done \
            < <(find "$TRIAGE_DIR" -maxdepth 1 -type f -name '*.md' | sort)
    fi

    # Il campo Data e' `YYYY-MM-DD HH:MM`: il confronto lessicografico con --dal
    # e' anche cronologico, e un --dal di soli giorni precede ogni ora di quel giorno.
    awk -v dal="$dal" -v sessione="$sessione" '
        function campo(riga,   v) { v = riga; sub(/^- \*\*[A-Za-z]+\*\*:[ \t]*/, "", v); return v }
        function chiudi() {
            if (!aperto) return
            aperto = 0
            if (sessione != "" && ses != sessione) return
            ok = (usc ~ /^(subito|task|scarto)$/ && chi ~ /^(umano|agente)$/ &&
                  mom ~ /^(flusso|posteriori)$/ && dat ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$/)
            conta("tot", ok, usc, chi, mom, dat)
            if (dal != "" && dat >= dal) conta("dal", ok, usc, chi, mom, dat)
        }
        function conta(k, ok, usc, chi, mom, dat) {
            if (!ok) { n[k, "malformati"]++; return }
            n[k, "scenari"]++; n[k, chi]++; n[k, usc "." chi]++; n[k, mom]++
            if (primo[k] == "" || dat < primo[k]) primo[k] = dat
            if (dat > ultimo[k]) ultimo[k] = dat
        }
        FNR == 1 { chiudi(); aperto = 1; usc = chi = mom = dat = ses = "" }
        /^- \*\*Uscita\*\*:/   { usc = campo($0) }
        /^- \*\*Chi\*\*:/      { chi = campo($0) }
        /^- \*\*Momento\*\*:/  { mom = campo($0) }
        /^- \*\*Data\*\*:/     { dat = campo($0) }
        /^- \*\*Sessione\*\*:/ { ses = campo($0) }
        END {
            chiudi()
            split("scenari umano agente subito.umano subito.agente task.umano task.agente scarto.umano scarto.agente flusso posteriori malformati", chiavi, " ")
            printf "chiave\ttotale"; if (dal != "") printf "\tdal %s", dal; printf "\n"
            for (i = 1; i <= 12; i++) {
                c = chiavi[i]
                printf "%s\t%d", c, n["tot", c]; if (dal != "") printf "\t%d", n["dal", c]; printf "\n"
            }
            printf "primo\t%s", (primo["tot"] == "" ? "-" : primo["tot"])
            if (dal != "") printf "\t%s", (primo["dal"] == "" ? "-" : primo["dal"]); printf "\n"
            printf "ultimo\t%s", (ultimo["tot"] == "" ? "-" : ultimo["tot"])
            if (dal != "") printf "\t%s", (ultimo["dal"] == "" ? "-" : ultimo["dal"]); printf "\n"
        }
    ' ${records[@]+"${records[@]}"} < /dev/null
    return 0
}

# =============================================================================
# dispatch
# =============================================================================
[[ $# -gt 0 ]] || fail 1 "sottocomando richiesto: scenario | conta"
SUB="$1"; shift
case "$SUB" in
    scenario) cmd_scenario "$@" ;;
    conta)    cmd_conta "$@" ;;
    *) fail 1 "sottocomando ignoto: ${SUB} (attesi: scenario, conta)" ;;
esac
