#!/bin/bash

# =============================================================================
# lib-config.sh - Primitive config progetto (file + registry dconf)
# Sourced da register.sh / refresh.sh / project-config.sh
# =============================================================================
#
# Modello: runtime/project/project-config-architecture.md
#   - File config .claude/loom-works.json  = source of truth CONFIG (portabile)
#   - Registry dconf /org/lamemind/loom/    = source of truth RUNTIME (macchina-locale)
#   - label DERIVATA "{emoji} {name}", mai scritta nel file. `owner` resta nel
#     file e nel registry come metadato organizzativo, ma nessun consumer lo legge.
#   - nessun profilo Ptyxis: chi apre una tab del progetto la lancia sul profilo
#     di default, e la chiave del canale stato è l'`id` del progetto
#
# Modello surface (ridisegno T32-reopen):
#   - TRACKED (rigide): claude, deck → mappa `surfaces` bool. Match finestra + stato.
#   - LAUNCH (custom): lista `launch` di voci {emoji, label?, command}. Comando shell
#     arbitrario con cwd=project root; fire-once, niente match/stato. Rimpiazza il
#     vecchio enum bool codium/idea (non più hardcoded).
#
# Fornisce:
#   File:      cfg_file_path, cfg_validate, cfg_field, cfg_enabled_surfaces,
#              cfg_launch_count, cfg_label
#   Blocchi:   cfg_validate_blocks (taskFields, hooks), cfg_reserved_task_keys
#   GVariant:  gv_str (quote), gv_unwrap (unwrap)
#   Registry:  reg_available, reg_project_path, reg_set, reg_get, reg_list_projects,
#              reg_write_surfaces, reg_write_launch, reg_pull
# =============================================================================

_LIBCFG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# lib.sh: die(), git wrappers, project-root detection
# shellcheck source=/dev/null
source "${_LIBCFG_DIR}/../utils/lib.sh"

REG_ROOT="/org/lamemind/loom"
REG_PROJECTS="${REG_ROOT}/projects"

# ---- GVariant string helpers -------------------------------------------------
#
# Un valore stringa dconf è un GVariant single/double-quoted. Emoji/owner/name
# non contengono apici in condizioni normali → single-quote. Se il valore
# contiene un apice singolo (es. un command di `launch[]` con un argomento
# quotato), si passa a double-quote con escape, il formato che dconf stesso usa.

gv_str() {  # <raw-string> → literal GVariant quotato
    local s="$1"
    if [[ "$s" == *\'* ]]; then
        s="${s//\\/\\\\}"   # backslash prima
        s="${s//\"/\\\"}"   # poi double-quote
        printf '"%s"' "$s"
    else
        printf "'%s'" "$s"
    fi
}

gv_unwrap() {  # <dconf-read-output> → raw string (inverso esatto di gv_str)
    local v="$1"
    if [[ "$v" == \'*\' ]]; then
        v="${v#\'}"; v="${v%\'}"
    elif [[ "$v" == \"*\" ]]; then
        v="${v#\"}"; v="${v%\"}"
        # Ordine inverso a gv_str, altrimenti un `gv_str "$(gv_unwrap …)"` (ciclo
        # read-modify-write) ri-escaperebbe ciò che è già escapato e i backslash
        # raddoppierebbero a ogni passaggio. Solo il ramo double-quote: quello
        # single-quote non escapa nulla neanche in scrittura.
        v="${v//\\\"/\"}"
        v="${v//\\\\/\\}"
    fi
    printf '%s' "$v"
}

# ---- File config .claude/loom-works.json ------------------------------------

cfg_file_path() {  # <project-dir> → path del file config
    echo "${1%/}/.claude/loom-works.json"
}

cfg_validate() {  # <json-file> → 0 valido, 1 invalido (messaggio su stderr)
    local f="$1"
    [[ -f "$f" ]] || { echo "config non trovato: $f" >&2; return 1; }
    command -v jq >/dev/null 2>&1 || { echo "jq assente (validazione impossibile)" >&2; return 1; }
    # surfaces = mappa TRACKED (claude/deck) → bool. launch (opzionale) = array di
    # voci custom {emoji(req), label(opt), command(req)}. label opzionale: fallback=command.
    jq -e '
        (.id|type)=="string" and ((.id|length)>0) and
        (.emoji|type)=="string" and
        (.owner|type)=="string" and
        (.name|type)=="string" and
        (.surfaces|type)=="object" and
        ((.launch // []) | (type=="array") and all(.[];
            ((.emoji|type)=="string") and ((.emoji|length)>0) and
            ((.command|type)=="string") and ((.command|length)>0)))
    ' "$f" >/dev/null 2>&1 || { echo "config invalido (schema): $f" >&2; return 1; }
    # defaultSurface (opzionale): enum chiuso claude|deck|terminal. Check SEPARATO dal
    # blocco jq sopra per poter nominare il valore incriminato — un typo qui sarebbe
    # altrimenti muto (il consumer degrada a terminal senza dire perché).
    # NOTA: si valida solo il DOMINIO, non la coerenza con `surfaces`. Nominare una
    # surface disabilitata NON invalida la config (disabilitarla è legittimo, e un
    # fail qui farebbe skippare l'intero progetto in refresh.sh): degrada il consumer.
    local ds; ds="$(jq -r '.defaultSurface // empty' "$f")"
    case "$ds" in
        ''|claude|deck|terminal) ;;
        *) echo "config invalido: defaultSurface='$ds' fuori enum (claude|deck|terminal): $f" >&2; return 1 ;;
    esac
    # order (opzionale): intero (gap-by-10). Check separato per nominare il valore:
    # un non-intero scritto in dconf produrrebbe un tipo GVariant diverso (double)
    # e un parse ambiguo lato consumer.
    if ! jq -e '(.order == null) or ((.order|type)=="number" and (.order == (.order|floor)))' "$f" >/dev/null 2>&1; then
        echo "config invalido: order=$(jq -c '.order' "$f") non è un intero: $f" >&2; return 1
    fi
    # taskFields e hooks (opzionali): stessi controlli del lettore delle skill.
    cfg_validate_blocks "$f" || return 1
}

# ---- Blocchi taskFields e hooks ----------------------------------------------
#
# Due chiamanti, una sola funzione: `cfg_validate` (init e refresh) e il lettore
# delle skill `scripts/config/project-config.sh` (ogni create-task, run-task,
# checkpoint-task). La guardia sta anche nel lettore perché `cfg_validate` da
# sola non basta: `register.sh` esce prima di validare quando dconf manca, quindi
# su Windows non gira mai, e un blocco sbagliato arriverebbe alle skill intatto.
#
# Le chiavi RISERVATE di taskFields sono le righe `- **<k>**:` dell'header del
# template del task file, non una lista scritta qui: un campo fisso aggiunto al
# template diventa riservato da sé. Il confronto non distingue maiuscole. La
# ragione è il parser dell'header del deck (`parseTaskDetail`), che tiene la
# prima occorrenza di una chiave: un `Size` custom scritto prima del campo fisso
# ne prenderebbe il posto. Per lo stesso motivo una chiave dichiarata due volte
# è rifiutata.
#
# L'esistenza delle skill negli hook NON si controlla: una skill può stare nel
# progetto, in ~/.claude/skills/ o in un plugin, e il file system del progetto
# mostra solo il primo caso. Si scopre all'invocazione, dove una skill assente
# vale come una che fallisce.
#
# Le regex di `pattern` sono nel dialetto di jq (test(), Oniguruma, dove `\d`
# funziona): la funzione controlla che compilino, perché una regex rotta
# farebbe fallire create-task alla prima risposta invece che qui.

_CFG_TASK_TEMPLATE="${_LIBCFG_DIR}/../../templates/task-template.md"

cfg_reserved_task_keys() {  # → chiavi fisse dell'header del template, separate da '|'
    local line out="" re='^-[[:space:]]*\*\*([^*]+)\*\*:'
    [[ -f "$_CFG_TASK_TEMPLATE" ]] || {
        echo "template del task file non trovato: ${_CFG_TASK_TEMPLATE} (chiavi riservate non derivabili)" >&2
        return 1
    }
    # Ciclo bash e non sed: su Windows ogni sottoprocesso costa ~150 ms, e questa
    # funzione gira a ogni invocazione del lettore. L'header finisce al primo `## `.
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ "$line" == '## '* ]] && break
        [[ "$line" =~ $re ]] && out+="${out:+|}${BASH_REMATCH[1]}"
    done < "$_CFG_TASK_TEMPLATE"
    printf '%s' "$out"
}

# Un messaggio per riga, vuoto se i blocchi sono validi o assenti. `null` vale
# assente, come `.launch // []` sopra.
_CFG_BLOCKS_JQ='
if type != "object" then "il file non è un oggetto JSON" else
($reserved | split("|") | map(ascii_downcase)) as $res
| (
    if (.taskFields // null) == null then empty
    elif (.taskFields | type) != "array" then "taskFields=\(.taskFields | tojson) non è una lista"
    else
      ( .taskFields | to_entries[] | .key as $i | .value as $v | "taskFields[\($i)]" as $at
        | if ($v | type) != "object" then "\($at)=\($v | tojson) non è un oggetto"
          else
            ( $v | keys_unsorted[] | select(IN("key", "ask", "pattern", "inherit") | not)
              | "\($at): proprietà sconosciuta \($q)\(.)\($q) (ammesse: key, ask, pattern, inherit)" ),
            ( if ($v.key | type) != "string" or $v.key == "" then "\($at): voce senza key"
              elif ($v.key | test("^[^*:|\\s]([^*:|\\r\\n]*[^*:|\\s])?$") | not)
                then "\($at).key=\($q)\($v.key)\($q) non vale come chiave di header (niente * : | a capo, né spazi in testa o in coda)"
              elif ($v.key | ascii_downcase | IN($res[]))
                then "\($at).key=\($q)\($v.key)\($q) è un campo fisso del task file (riservato)"
              else empty end ),
            ( if ($v | has("ask")) and ($v.ask | type) != "string"
                then "\($at).ask=\($v.ask | tojson) non è un testo" else empty end ),
            ( if ($v | has("pattern") | not) then empty
              elif ($v.pattern | type) != "string" then "\($at).pattern=\($v.pattern | tojson) non è un testo"
              elif ($v.pattern | test("[\\r\\n]")) then "\($at).pattern contiene un a capo: un campo di header sta su una riga"
              elif (try ("" | test($v.pattern) | false) catch true)
                then "\($at).pattern=\($q)\($v.pattern)\($q) non è una regex valida (dialetto jq, Oniguruma)"
              else empty end ),
            ( if ($v | has("inherit")) and ($v.inherit | type) != "boolean"
                then "\($at).inherit=\($v.inherit | tojson) non è un booleano" else empty end )
          end ),
      ( [ .taskFields[] | objects | .key | strings | select(. != "") ]
        | group_by(ascii_downcase)[] | select(length > 1)
        | "taskFields: key \($q)\(.[0])\($q) dichiarata \(length) volte" )
    end
  ),
  (
    if (.hooks // null) == null then empty
    elif (.hooks | type) != "object" then "hooks=\(.hooks | tojson) non è un oggetto"
    else
      .hooks | to_entries[] | .key as $ev | .value as $l
      | if ($ev | IN("deliverableDone", "taskDone") | not)
          then "hooks.\($ev): evento sconosciuto (ammessi: deliverableDone, taskDone)"
        elif ($l | type) != "array" or ($l | all(type == "string" and test("^\\S+$")) | not)
          then "hooks.\($ev)=\($l | tojson) non è una lista di nomi di skill (stringhe non vuote, senza spazi)"
        else empty end
    end
  )
end
'

cfg_validate_blocks() {  # <json-file> → 0 validi o assenti, 1 invalidi (un messaggio per riga su stderr)
    local f="$1" reserved errs line
    command -v jq >/dev/null 2>&1 || { echo "jq assente (validazione di taskFields/hooks impossibile): $f" >&2; return 1; }
    reserved="$(cfg_reserved_task_keys)" || return 1
    errs="$(jq -r --arg reserved "$reserved" --arg q "'" "$_CFG_BLOCKS_JQ" "$f" 2>/dev/null)" \
        || { echo "config non leggibile (JSON malformato): $f" >&2; return 1; }
    [[ -z "$errs" ]] && return 0
    # jq nativo di Windows scrive CRLF: il \r va tolto riga per riga.
    while IFS= read -r line; do
        line="${line%$'\r'}"
        [[ -n "$line" ]] && echo "config invalido: ${line}: $f" >&2
    done <<< "$errs"
    return 1
}

cfg_field() {  # <json-file> <top-level-field> → valore scalare
    jq -r --arg k "$2" '.[$k] // empty' "$1"
}

cfg_enabled_surfaces() {  # <json-file> → kind TRACKED abilitati, uno per riga
    jq -r '.surfaces // {} | to_entries[] | select(.value==true) | .key' "$1"
}

cfg_launch_count() {  # <json-file> → numero di voci launch
    jq '(.launch // []) | length' "$1"
}

cfg_label() {  # <emoji> <name> → label derivata
    printf '%s %s' "$1" "$2"
}

# ---- Registry dconf /org/lamemind/loom/ -------------------------------------

reg_available() { command -v dconf >/dev/null 2>&1; }

reg_project_path() { echo "${REG_PROJECTS}/$1"; }

reg_set() {  # <id> <key> <gvariant-value-già-quotato>
    dconf write "$(reg_project_path "$1")/$2" "$3"
}

reg_get() {  # <id> <key> → raw string
    gv_unwrap "$(dconf read "$(reg_project_path "$1")/$2" 2>/dev/null || echo '')"
}

reg_list_projects() {  # id registrati, uno per riga
    dconf list "${REG_PROJECTS}/" 2>/dev/null | sed 's:/$::' | sed '/^$/d'
}

reg_write_surfaces() {  # <id> <kind...> → scrive array GVariant 'as' delle surface abilitate
    local id="$1"; shift
    local path; path="$(reg_project_path "$id")/surfaces"
    if [[ $# -eq 0 ]]; then
        dconf write "$path" "@as []"
        return 0
    fi
    local arr="[" first=1 k
    for k in "$@"; do
        [[ $first -eq 1 ]] && first=0 || arr+=", "
        arr+="$(gv_str "$k")"
    done
    arr+="]"
    dconf write "$path" "$arr"
}

# Scrive le surface LAUNCH nel registry come sottoalbero indicizzato launch/<i>/{emoji,label,command}.
# Reset del sottoalbero prima di riscrivere → nessuna entry stale se il numero di voci cala.
# label: fallback a command se assente nel file (default: la voce si chiama come il comando).
reg_write_launch() {  # <id> <json-file>
    local id="$1" f="$2"
    local base; base="$(reg_project_path "$id")/launch"
    dconf reset -f "${base}/" 2>/dev/null || true
    local n i emoji label command
    n="$(cfg_launch_count "$f")"
    for (( i=0; i<n; i++ )); do
        emoji="$(jq -r --argjson i "$i" '.launch[$i].emoji' "$f")"
        label="$(jq -r --argjson i "$i" '.launch[$i].label // .launch[$i].command' "$f")"
        command="$(jq -r --argjson i "$i" '.launch[$i].command' "$f")"
        dconf write "${base}/${i}/emoji"   "$(gv_str "$emoji")"
        dconf write "${base}/${i}/label"   "$(gv_str "$label")"
        dconf write "${base}/${i}/command" "$(gv_str "$command")"
    done
}

# Pull: legge il file config di <project-dir> e scrive il registry. Usa l'id
# DAL FILE (non dalla dir). Echoes l'id su stdout. Base comune di register/refresh.
reg_pull() {  # <project-dir> → id (o 1 su config invalido)
    local dir f id emoji owner name
    dir="${1%/}"
    f="$(cfg_file_path "$dir")"
    cfg_validate "$f" || return 1
    id="$(cfg_field "$f" id)"
    emoji="$(cfg_field "$f" emoji)"
    owner="$(cfg_field "$f" owner)"
    name="$(cfg_field "$f" name)"
    reg_set "$id" emoji "$(gv_str "$emoji")"
    reg_set "$id" owner "$(gv_str "$owner")"
    reg_set "$id" name  "$(gv_str "$name")"
    reg_set "$id" dir   "$(gv_str "$dir")"
    local -a surfaces
    mapfile -t surfaces < <(cfg_enabled_surfaces "$f")
    reg_write_surfaces "$id" "${surfaces[@]}"
    reg_write_launch "$id" "$f"
    # docsRoot (opzionale): sottocartella che contiene tasks.md. Fatto PER-PROGETTO
    # cross-membro → derivato nel registry, così deck/compass lo leggono senza toccare
    # i settings di Claude. Presente nel file → scrive; assente → reset (no stale).
    local docsroot; docsroot="$(cfg_field "$f" docsRoot)"
    if [[ -n "$docsroot" ]]; then
        reg_set "$id" docsRoot "$(gv_str "$docsroot")"
    else
        dconf reset "$(reg_project_path "$id")/docsRoot" 2>/dev/null || true
    fi
    # defaultSurface (opzionale): surface aperta dal bottone-nome in compass.
    # Assente → reset, così il consumer applica il suo default (terminal) e non
    # resta agganciato a un valore vecchio dopo che è stato tolto dal file.
    local defsurface; defsurface="$(cfg_field "$f" defaultSurface)"
    if [[ -n "$defsurface" ]]; then
        reg_set "$id" defaultSurface "$(gv_str "$defsurface")"
    else
        dconf reset "$(reg_project_path "$id")/defaultSurface" 2>/dev/null || true
    fi
    # order (opzionale): posizione nel blocco loom di compass. Intero non quotato
    # → dconf lo tipizza int32. Assente → reset (no stale), il consumer mette il
    # progetto in coda alfabetica.
    local order; order="$(cfg_field "$f" order)"
    if [[ -n "$order" ]]; then
        reg_set "$id" order "$order"
    else
        dconf reset "$(reg_project_path "$id")/order" 2>/dev/null || true
    fi
    echo "$id"
}
