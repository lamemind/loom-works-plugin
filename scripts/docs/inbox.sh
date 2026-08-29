#!/usr/bin/env bash

# =============================================================================
# inbox.sh — l'unico script che sa scrivere e leggere un file inbox
# Usage:
#   inbox.sh new      --docs-root <name> --slug <slug> --natura nozioni|derivazione|sweep
#                     [--cappello <id>] [--titolo <t>] [--tldr <t>]
#                     [--indexed] [--drainable] [--branch <nome>]
#                     [--ancora <chiave:valore>]...      # solo derivazione e sweep
#                     < nozioni (una per riga) | prosa (derivazione, sweep)
#   inbox.sh parse    --file <path> [--format text|tsv]
#   inbox.sh marker   --file <path> [--set <token>]... [--unset <token>]...
#   inbox.sh registro --file <path> --attore router|writer   < envelope JSON
# =============================================================================
#
# Quattro sottocomandi in un file solo: quattro script separati condividerebbero
# comunque le stesse regex, e un path solo e' cio' che i prompt devono ricordare.
# Grammatica: marker-formato-inbox-v2 (riga marker in riga 3, TLDR riga 4,
# nozioni `- **nN** — `, registro a sub-bullet).
#
# Exit code per sottocomando:
#   new       0 fatto · 1 errore duro (input mancante/incoerente, NESSUN file creato)
#   parse     0 conforme · 2 malformato (MALFORMATO<TAB><ragione>, nessun'altra
#             riga) · 1 file assente o errore d'uso    [famiglia guardia]
#   marker    0 fatto · 1 file malformato o token fuori vocabolario (no scrittura)
#   registro  0 fatto · 1 errore duro (id assente, campo obbligatorio mancante —
#             NESSUNA scrittura parziale: il file si riscrive intero o niente)
#
# Il parser e' order-agnostic sui token; la scrittura e' sempre in ordine
# canonico (natura · indexed · drainable · branch:<nome>) cosi' due file scritti
# da percorsi diversi restano diffabili.
#
# Nozione chiusa = sub-bullet `router ✖️`, `writer ✔️` o `writer ✖️`. I token di
# chiusura sono TRE: `router ✔️` non esiste — il router chiude solo le
# non-azioni, su una rotta lascia il `→` che NON chiude. Un sub-bullet con una
# coppia attore-glifo fuori dalle quattro producibili e' MALFORMATO, non
# ignorato: ignorarlo lascerebbe la nozione aperta per sempre e il sintomo
# arriverebbe lontanissimo dalla causa.
#
# Su derivazione e sweep le ancore sono annunciate da un separatore `---` e
# raccolte solo dopo di esso: senza, qualunque riga di prosa che apra con una
# minuscola seguita da due punti diventerebbe un'ancora fantasma. Un file che il
# separatore non ce l'ha si parsa con la regola vecchia — i file gia' scritti
# perderebbero altrimenti le proprie ancore.
#
# parse espone attore/verdetto/target dell'ULTIMO sub-bullet anche sulle nozioni
# aperte: e' cio' che rende ripartibile un drain morto a meta' — una aperta con
# `router →` va dritta al writer, una nuda al router. Campi solo sulle chiuse
# renderebbero i due stati indistinguibili.
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"
# shellcheck source=lib-doc.sh
source "${SCRIPT_DIR}/lib-doc.sh"

VS16=$'\uFE0F'

die() { echo "[inbox] ERROR: $*" >&2; exit 1; }

# strip del variation selector: i glifi ✔️/✖️ viaggiano con o senza VS16 a
# seconda dell'editor; la classificazione matcha sul carattere base
novs() { printf '%s' "${1//"$VS16"/}"; }

# --- Classificazione di un sub-bullet -----------------------------------------
# Ritorna via variabili globali: SUB_ATTORE, SUB_VERDETTO, SUB_TARGET, SUB_RESA
# Return: 0 valido · 1 coppia attore-glifo fuori dalle quattro producibili
classify_sub() {  # <contenuto dopo "  - ">
    local s; s="$(novs "$1")"
    SUB_ATTORE=""; SUB_VERDETTO=""; SUB_TARGET=""; SUB_RESA=""
    if [[ "$s" =~ ^router\ →\ (.+)$ ]]; then
        local rest="${BASH_REMATCH[1]}"
        SUB_ATTORE="router"; SUB_VERDETTO="rotta"
        SUB_TARGET="${rest%% — *}"
        SUB_RESA="router → ${SUB_TARGET}"
        return 0
    fi
    if [[ "$s" =~ ^router\ ✖\ ([^:]+):\ ?(.*)$ ]]; then
        SUB_ATTORE="router"; SUB_VERDETTO="${BASH_REMATCH[1]}"
        SUB_RESA="router ✖️ ${SUB_VERDETTO}"
        return 0
    fi
    if [[ "$s" =~ ^writer\ ✔\ (.+)$ ]]; then
        SUB_ATTORE="writer"; SUB_VERDETTO="scritta"
        SUB_RESA="writer ✔️ ${BASH_REMATCH[1]}"
        return 0
    fi
    if [[ "$s" =~ ^writer\ ✖\ drop:\ ?(.*)$ ]]; then
        SUB_ATTORE="writer"; SUB_VERDETTO="drop"
        SUB_RESA="writer ✖️ drop"
        return 0
    fi
    return 1
}

sub_is_chiusura() {  # <contenuto dopo "  - "> → 0 se chiude la nozione
    local s; s="$(novs "$1")"
    [[ "$s" == "router ✖ "* || "$s" == "writer ✔ "* || "$s" == "writer ✖ "* ]]
}

# --- Validazione della riga marker --------------------------------------------
# Ritorna via globali: MK_NATURA, MK_INDEXED (0/1), MK_DRAINABLE (0/1), MK_BRANCH
# Su errore: MK_REASON valorizzata, return 1.
read_marker() {  # <file>
    MK_NATURA=""; MK_INDEXED=0; MK_DRAINABLE=0; MK_BRANCH=""; MK_REASON=""
    local line3
    line3="$(sed -n '3p' "$1" 2>/dev/null)"
    if [[ ! "$line3" =~ ^\>\ \*\*INBOX\*\*:\ (.+)$ ]]; then
        if grep -qE '^> \*\*INBOX\*\*: ' "$1" 2>/dev/null; then
            local at
            at="$(grep -nE -m1 '^> \*\*INBOX\*\*: ' "$1" | cut -d: -f1)"
            MK_REASON="marker fuori dalla riga 3 (trovato in riga ${at})"
        else
            MK_REASON="marker assente"
        fi
        return 1
    fi
    local tokens="${BASH_REMATCH[1]}" tok n_nat=0
    while IFS= read -r tok; do
        [[ -z "$tok" ]] && continue
        case "$tok" in
            nozioni|derivazione|sweep)
                n_nat=$((n_nat+1)); MK_NATURA="$tok" ;;
            indexed)   MK_INDEXED=1 ;;
            drainable) MK_DRAINABLE=1 ;;
            branch:*)  MK_BRANCH="${tok#branch:}" ;;
            *) MK_REASON="token sconosciuto: ${tok}"; return 1 ;;
        esac
    done < <(sed 's/ · /\n/g' <<< "$tokens")
    if (( n_nat == 0 )); then MK_REASON="natura assente"; return 1; fi
    if (( n_nat > 1 ));  then MK_REASON="natura doppia"; return 1; fi
    return 0
}

marker_line() {  # <natura> <indexed 0/1> <drainable 0/1> <branch> → riga canonica
    local out="> **INBOX**: $1"
    (( $2 )) && out+=" · indexed"
    (( $3 )) && out+=" · drainable"
    [[ -n "$4" ]] && out+=" · branch:$4"
    printf '%s\n' "$out"
}

# =============================================================================
# new
# =============================================================================
cmd_new() {
    local docs_root="" slug="" natura="" cappello="" titolo="" tldr=""
    local indexed=0 drainable=0 branch=""
    local -a ancore=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --docs-root) docs_root="$2"; shift 2 ;;
            --slug)      slug="$2"; shift 2 ;;
            --natura)    natura="$2"; shift 2 ;;
            --cappello)  cappello="$2"; shift 2 ;;
            --titolo)    titolo="$2"; shift 2 ;;
            --tldr)      tldr="$2"; shift 2 ;;
            --indexed)   indexed=1; shift ;;
            --drainable) drainable=1; shift ;;
            --branch)    branch="$2"; shift 2 ;;
            --ancora)    ancore+=("$2"); shift 2 ;;
            *) die "argomento ignoto: $1" ;;
        esac
    done

    [[ -n "$docs_root" ]] || die "--docs-root obbligatorio"
    [[ -n "$slug" ]] || die "--slug obbligatorio"
    [[ "$slug" == */* ]] && die "slug non puo' contenere '/': ${slug}"
    case "$natura" in
        nozioni|derivazione|sweep) ;;
        *) die "--natura deve essere nozioni|derivazione|sweep (ricevuto: '${natura}')" ;;
    esac

    # Coerenza marker/ancore — verificata QUI e non altrove: e' il punto in cui
    # un file malformato smette di essere producibile.
    if [[ "$natura" != "nozioni" ]]; then
        (( indexed )) && die "indexed e' ammesso solo su natura nozioni"
        [[ -n "$tldr" ]] && die "--tldr e' ammesso solo su natura nozioni"
    else
        [[ ${#ancore[@]} -gt 0 ]] && die "--ancora e' ammesso solo su derivazione e sweep"
    fi
    local a has_range=0
    for a in ${ancore[@]+"${ancore[@]}"}; do
        [[ "$a" == *:* ]] || die "ancora senza ':': ${a}"
        [[ "${a%%:*}" == "range" ]] && has_range=1
    done
    if [[ "$natura" == "derivazione" && $has_range -eq 0 ]]; then
        die "una derivazione richiede l'ancora range: — senza un diff non c'e' niente da derivare, il caso e' uno sweep"
    fi

    # Contenuto da stdin
    local -a body=()
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        body+=("$line")
    done
    # trailing empty lines: si potano (un echo con newline finale e' legittimo)
    while [[ ${#body[@]} -gt 0 && -z "${body[-1]}" ]]; do
        unset 'body[-1]'
    done
    [[ ${#body[@]} -gt 0 ]] || die "stdin vuoto: niente da scrivere"

    if [[ "$natura" == "nozioni" ]]; then
        # una nozione per riga; una riga vuota in mezzo e' un errore duro, non
        # un caso da ricucire (garanzia di progetto: nessun hard-wrap nei .md)
        for line in "${body[@]}"; do
            [[ -z "$line" ]] && die "riga vuota dentro le nozioni su stdin"
        done
    fi

    # Titolo: default derivato dallo slug — la riga 1 non e' mai vuota
    if [[ -z "$titolo" ]]; then
        local spaced="${slug//-/ }"
        if [[ -n "$cappello" ]]; then titolo="${cappello} — ${spaced}"; else titolo="$spaced"; fi
    fi

    # Nome file: <cappello>-<slug>.md quando c'e', <slug>.md quando manca;
    # collisione → suffisso progressivo (un cappello che trasloca piu' volte
    # produce piu' file per costruzione)
    local project_root inbox_dir base name path n
    project_root="$(lw_find_project_root)"
    inbox_dir="${project_root}/${docs_root}/inbox"
    mkdir -p "$inbox_dir"
    if [[ -n "$cappello" ]]; then base="${cappello}-${slug}"; else base="$slug"; fi
    name="$base"; n=1
    while [[ -e "${inbox_dir}/${name}.md" ]]; do
        n=$((n+1)); name="${base}-${n}"
    done
    path="${inbox_dir}/${name}.md"

    {
        printf '# %s\n\n' "$titolo"
        marker_line "$natura" "$indexed" "$drainable" "$branch"
        [[ -n "$tldr" ]] && printf '> **TLDR**: %s\n' "$tldr"
        printf '\n'
        if [[ "$natura" == "nozioni" ]]; then
            local i=0
            for line in "${body[@]}"; do
                i=$((i+1))
                printf -- '- **n%d** — %s\n' "$i" "$line"
            done
        else
            printf '%s\n' "${body[@]}"
            if [[ ${#ancore[@]} -gt 0 ]]; then
                printf '\n%s\n' "$LW_DOC_ANCORE_SEP"
                for a in "${ancore[@]}"; do
                    printf '%s: %s\n' "${a%%:*}" "${a#*:}"
                done
            fi
        fi
    } > "$path"

    echo "INBOX_PATH=${path}"
    exit 0
}

# =============================================================================
# parse
# =============================================================================
cmd_parse() {
    local file="" format="text"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file)   file="$2"; shift 2 ;;
            --format) format="$2"; shift 2 ;;
            *) die "argomento ignoto: $1" ;;
        esac
    done
    [[ -n "$file" ]] || die "--file obbligatorio"
    [[ -f "$file" ]] || die "file assente: ${file}"
    case "$format" in text|tsv) ;; *) die "--format deve essere text|tsv" ;; esac

    if ! read_marker "$file"; then
        printf 'MALFORMATO\t%s\n' "$MK_REASON"
        exit 2
    fi

    local titolo tldr=""
    titolo="$(sed -n '1p' "$file")"; titolo="${titolo#\# }"
    tldr="$(doc_tldr "$file" 4)"

    # Prima passata: valida i sub-bullet (un malformato non emette NESSUNA riga
    # di dato), poi seconda passata per l'output.
    local line in_nozione=0
    while IFS= read -r line; do
        if [[ "$line" =~ $LW_DOC_RE_NOZIONE ]]; then
            in_nozione=1; continue
        fi
        if [[ "$in_nozione" -eq 1 && "$line" =~ ^\ \ -\ (.+)$ ]]; then
            if ! classify_sub "${BASH_REMATCH[1]}"; then
                printf 'MALFORMATO\tsub-bullet con coppia attore-glifo fuori dalle quattro producibili: %s\n' "$line"
                exit 2
            fi
            continue
        fi
        [[ "$line" =~ ^-\  || -z "$line" ]] || in_nozione=0
    done < "$file"

    # Riga del separatore delle ancore, se il file ne ha uno. Si prende
    # l'ULTIMA occorrenza: le ancore stanno sempre in coda al file, quindi un
    # `---` che compare prima appartiene alla prosa e non apre il blocco.
    local sep_line=0
    if [[ "$MK_NATURA" != "nozioni" ]]; then
        sep_line="$(awk -v sep="$LW_DOC_ANCORE_SEP" 'NR>3 && $0==sep { n=NR } END { print n+0 }' "$file")"
    fi

    # Seconda passata: raccolta dati
    local -a noz_id=() noz_stato=() noz_attore=() noz_verdetto=() noz_target=() noz_resa=()
    local -a anc_k=() anc_v=()
    local cur=-1 lineno=0
    while IFS= read -r line; do
        lineno=$((lineno+1))
        if [[ "$line" =~ $LW_DOC_RE_NOZIONE ]]; then
            noz_id+=("${BASH_REMATCH[1]}")
            noz_stato+=("aperta"); noz_attore+=(""); noz_verdetto+=(""); noz_target+=(""); noz_resa+=("")
            cur=$(( ${#noz_id[@]} - 1 ))
            continue
        fi
        if [[ $cur -ge 0 && "$line" =~ ^\ \ -\ (.+)$ ]]; then
            # BASH_REMATCH va fotografato subito: classify_sub esegue regex sue
            # e lo sovrascrive
            sub_content="${BASH_REMATCH[1]}"
            classify_sub "$sub_content"
            noz_attore[cur]="$SUB_ATTORE"
            noz_verdetto[cur]="$SUB_VERDETTO"
            noz_target[cur]="$SUB_TARGET"
            noz_resa[cur]="$SUB_RESA"
            sub_is_chiusura "$sub_content" && noz_stato[cur]="chiusa"
            continue
        fi
        if [[ "$MK_NATURA" != "nozioni" && $lineno -gt ${sep_line:-0} && $lineno -gt 3 \
              && "$line" =~ $LW_DOC_RE_ANCORA ]]; then
            anc_k+=("${BASH_REMATCH[1]}"); anc_v+=("${BASH_REMATCH[2]}")
        fi
    done < "$file"

    local i
    if [[ "$format" == "tsv" ]]; then
        printf 'TITOLO\t%s\n' "$titolo"
        printf 'MARKER\t%s\t%s\t%s\t%s\n' "$MK_NATURA" \
            "$( (( MK_INDEXED )) && echo indexed )" \
            "$( (( MK_DRAINABLE )) && echo drainable )" \
            "$MK_BRANCH"
        [[ -n "$tldr" ]] && printf 'TLDR\t%s\t%s\n' "$tldr" "${#tldr}"
        for i in "${!noz_id[@]}"; do
            printf 'NOZIONE\t%s\t%s\t%s\t%s\t%s\n' \
                "${noz_id[$i]}" "${noz_stato[$i]}" "${noz_attore[$i]}" "${noz_verdetto[$i]}" "${noz_target[$i]}"
        done
        for i in "${!anc_k[@]}"; do
            printf 'ANCORA\t%s\t%s\n' "${anc_k[$i]}" "${anc_v[$i]}"
        done
    else
        local hdr="$MK_NATURA"
        (( MK_INDEXED ))   && hdr+=" · indexed"
        (( MK_DRAINABLE )) && hdr+=" · drainable"
        [[ -n "$MK_BRANCH" ]] && hdr+=" · branch:${MK_BRANCH}"
        printf '%s  —  %s\n' "$hdr" "$titolo"
        [[ -n "$tldr" ]] && printf 'TLDR (%s char): %s\n' "${#tldr}" "$tldr"
        for i in "${!noz_id[@]}"; do
            printf '%-4s %-7s %s\n' "${noz_id[$i]}" "${noz_stato[$i]}" "${noz_resa[$i]:-—}"
        done
        for i in "${!anc_k[@]}"; do
            printf 'ancora %s: %s\n' "${anc_k[$i]}" "${anc_v[$i]}"
        done
    fi
    exit 0
}

# =============================================================================
# marker
# =============================================================================
cmd_marker() {
    local file=""
    local -a sets=() unsets=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file)  file="$2"; shift 2 ;;
            --set)   sets+=("$2"); shift 2 ;;
            --unset) unsets+=("$2"); shift 2 ;;
            *) die "argomento ignoto: $1" ;;
        esac
    done
    [[ -n "$file" ]] || die "--file obbligatorio"
    [[ -f "$file" ]] || die "file assente: ${file}"

    read_marker "$file" || die "file malformato: ${MK_REASON} — nessuna scrittura"

    local t
    for t in ${unsets[@]+"${unsets[@]}"}; do
        case "$t" in
            indexed)   MK_INDEXED=0 ;;
            drainable) MK_DRAINABLE=0 ;;
            branch)    MK_BRANCH="" ;;
            *) die "token fuori vocabolario per --unset: ${t} — nessuna scrittura" ;;
        esac
    done
    for t in ${sets[@]+"${sets[@]}"}; do
        case "$t" in
            indexed)   MK_INDEXED=1 ;;
            drainable) MK_DRAINABLE=1 ;;
            branch:?*) MK_BRANCH="${t#branch:}" ;;
            *) die "token fuori vocabolario per --set: ${t} — nessuna scrittura" ;;
        esac
    done

    # Riscrive SOLO la riga 3, mai un altro byte: con una primitiva che riscrive
    # una riga sola non c'e' modo di sbagliare l'invariante «lo sblocco non
    # tocca le nozioni».
    local new_line tmp
    new_line="$(marker_line "$MK_NATURA" "$MK_INDEXED" "$MK_DRAINABLE" "$MK_BRANCH")"
    tmp="$(mktemp)"
    awk -v nl="$new_line" 'NR==3 { print nl; next } { print }' "$file" > "$tmp" || { rm -f "$tmp"; die "riscrittura fallita"; }
    mv "$tmp" "$file"
    exit 0
}

# =============================================================================
# registro
# =============================================================================
cmd_registro() {
    local file="" attore=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file)   file="$2"; shift 2 ;;
            --attore) attore="$2"; shift 2 ;;
            *) die "argomento ignoto: $1" ;;
        esac
    done
    [[ -n "$file" ]] || die "--file obbligatorio"
    [[ -f "$file" ]] || die "file assente: ${file}"
    case "$attore" in router|writer) ;; *) die "--attore deve essere router|writer" ;; esac
    command -v jq >/dev/null 2>&1 || die "jq richiesto"

    local envelope
    envelope="$(cat)"
    [[ -n "$envelope" ]] || die "envelope vuoto su stdin"
    jq -e . >/dev/null 2>&1 <<< "$envelope" || die "envelope non e' JSON valido"

    # Id presenti nel file
    local -A file_ids=()
    local line
    while IFS= read -r line; do
        [[ "$line" =~ $LW_DOC_RE_NOZIONE ]] && file_ids["${BASH_REMATCH[1]}"]=1
    done < "$file"

    # Costruzione dei sub-bullet, TUTTA la validazione prima di ogni scrittura
    local -A inserts=()
    local id verdetto target evidenza motivo come esito row
    if [[ "$attore" == "router" ]]; then
        jq -e '.verdetti | type == "array"' >/dev/null 2>&1 <<< "$envelope" \
            || die "envelope del router senza campo verdetti"
        while IFS= read -r row; do
            id="$(jq -r '.id // empty' <<< "$row")"
            verdetto="$(jq -r '.verdetto // empty' <<< "$row")"
            target="$(jq -r '.target // empty' <<< "$row")"
            evidenza="$(jq -r '.evidenza // empty' <<< "$row")"
            motivo="$(jq -r '.motivo // empty' <<< "$row")"
            [[ -n "$id" ]] || die "verdetto senza id"
            [[ -n "${file_ids[$id]:-}" ]] || die "id assente dal file: ${id} — nessuna scrittura"
            case "$verdetto" in
                rotta)
                    [[ -n "$target" ]] || die "verdetto rotta senza target (id ${id}) — nessuna scrittura"
                    if [[ -n "$evidenza" ]]; then
                        inserts["$id"]+="  - router → ${target} — ${evidenza}"$'\n'
                    else
                        inserts["$id"]+="  - router → ${target}"$'\n'
                    fi ;;
                noto|"già scritto"|drop)
                    [[ -n "$motivo" ]] || die "non-azione '${verdetto}' senza motivo (id ${id}) — nessuna scrittura"
                    inserts["$id"]+="  - router ✖️ ${verdetto}: ${motivo}"$'\n' ;;
                *) die "verdetto fuori vocabolario: '${verdetto}' (id ${id})" ;;
            esac
        done < <(jq -c '.verdetti[]' <<< "$envelope")
    else
        jq -e '.esiti | type == "array"' >/dev/null 2>&1 <<< "$envelope" \
            || die "envelope del writer senza campo esiti"
        while IFS= read -r row; do
            id="$(jq -r '.id // empty' <<< "$row")"
            esito="$(jq -r '.esito // empty' <<< "$row")"
            come="$(jq -r '.come // empty' <<< "$row")"
            motivo="$(jq -r '.motivo // empty' <<< "$row")"
            [[ -n "$id" ]] || die "esito senza id"
            [[ -n "${file_ids[$id]:-}" ]] || die "id assente dal file: ${id} — nessuna scrittura"
            case "$esito" in
                scritta)
                    # `come` obbligatorio: un writer ✔️ nudo perderebbe l'unico
                    # dato che il writer possiede — quale operazione ha applicato
                    [[ -n "$come" ]] || die "esito scritta senza come (id ${id}) — nessuna scrittura"
                    inserts["$id"]+="  - writer ✔️ ${come}"$'\n' ;;
                drop)
                    [[ -n "$motivo" ]] || die "esito drop senza motivo (id ${id}) — nessuna scrittura"
                    inserts["$id"]+="  - writer ✖️ drop: ${motivo}"$'\n' ;;
                *) die "esito fuori vocabolario: '${esito}' (id ${id})" ;;
            esac
        done < <(jq -c '.esiti[]' <<< "$envelope")
    fi

    [[ ${#inserts[@]} -gt 0 ]] || die "envelope senza voci"

    # Riscrittura tutto-o-niente: appende ogni sub-bullet DOPO quelli esistenti
    # della sua nozione. Non riordina, non deduplica, non rimuove.
    local tmp cur=""
    tmp="$(mktemp)"
    {
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ $LW_DOC_RE_NOZIONE ]]; then
                if [[ -n "$cur" && -n "${inserts[$cur]:-}" ]]; then
                    printf '%s' "${inserts[$cur]}"; unset "inserts[$cur]"
                fi
                cur="${BASH_REMATCH[1]}"
            elif [[ -n "$cur" && ! "$line" =~ ^\ \ -\  ]]; then
                if [[ -n "${inserts[$cur]:-}" ]]; then
                    printf '%s' "${inserts[$cur]}"; unset "inserts[$cur]"
                fi
                cur=""
            fi
            printf '%s\n' "$line"
        done < "$file"
        if [[ -n "$cur" && -n "${inserts[$cur]:-}" ]]; then
            printf '%s' "${inserts[$cur]}"; unset "inserts[$cur]"
        fi
    } > "$tmp"
    mv "$tmp" "$file"
    exit 0
}

# =============================================================================
# dispatch
# =============================================================================
[[ $# -ge 1 ]] || die "sottocomando richiesto: new|parse|marker|registro"
sub="$1"; shift
case "$sub" in
    new)      cmd_new "$@" ;;
    parse)    cmd_parse "$@" ;;
    marker)   cmd_marker "$@" ;;
    registro) cmd_registro "$@" ;;
    *) die "sottocomando ignoto: ${sub}" ;;
esac
