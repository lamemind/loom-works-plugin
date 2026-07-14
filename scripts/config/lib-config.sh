#!/bin/bash

# =============================================================================
# lib-config.sh - Primitive config progetto (file + registry dconf + profili)
# Sourced da register.sh / refresh.sh / materialize-profiles.sh
# =============================================================================
#
# Modello: runtime/project/project-config-architecture.md
#   - File config .claude/loom-works.json  = source of truth CONFIG (portabile)
#   - Registry dconf /org/lamemind/loom/    = source of truth RUNTIME (macchina-locale)
#   - label DERIVATA "{emoji} {owner} {name}", mai scritta nel file
#   - profili Ptyxis DERIVATI dal registry (materializzazione)
#
# Fornisce:
#   File:      cfg_file_path, cfg_validate, cfg_field, cfg_enabled_surfaces, cfg_label
#   GVariant:  gv_str (quote), gv_unwrap (unwrap)
#   Registry:  reg_available, reg_project_path, reg_set, reg_get, reg_list_projects,
#              reg_write_surfaces, reg_set_binding, reg_get_binding, reg_pull
#   Ptyxis:    ptx_available, ptx_list_uuids, ptx_label, ptx_profile_dir,
#              ptx_find_for_surface, ptx_generate_claude
# =============================================================================

_LIBCFG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# lib.sh: die(), git wrappers, project-root detection
# shellcheck source=/dev/null
source "${_LIBCFG_DIR}/../utils/lib.sh"

REG_ROOT="/org/lamemind/loom"
REG_PROJECTS="${REG_ROOT}/projects"

PTX_ROOT="/org/gnome/Ptyxis"
PTX_UUIDS="${PTX_ROOT}/profile-uuids"

# ---- GVariant string helpers -------------------------------------------------
#
# Un valore stringa dconf è un GVariant single/double-quoted. Emoji/owner/name
# non contengono apici in condizioni normali → single-quote. Se il valore
# contiene un apice singolo (es. custom-command con 'label'), si passa a
# double-quote con escape, replicando il formato che Ptyxis usa già.

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

gv_unwrap() {  # <dconf-read-output> → raw string (rimuove uno strato di quote)
    local v="$1"
    if [[ "$v" == \'*\' ]]; then
        v="${v#\'}"; v="${v%\'}"
    elif [[ "$v" == \"*\" ]]; then
        v="${v#\"}"; v="${v%\"}"
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
    jq -e '
        (.id|type)=="string" and ((.id|length)>0) and
        (.emoji|type)=="string" and
        (.owner|type)=="string" and
        (.name|type)=="string" and
        (.surfaces|type)=="object"
    ' "$f" >/dev/null 2>&1 || { echo "config invalido (schema): $f" >&2; return 1; }
}

cfg_field() {  # <json-file> <top-level-field> → valore scalare
    jq -r --arg k "$2" '.[$k] // empty' "$1"
}

cfg_enabled_surfaces() {  # <json-file> → kind abilitati, uno per riga
    jq -r '.surfaces // {} | to_entries[] | select(.value==true) | .key' "$1"
}

cfg_label() {  # <emoji> <owner> <name> → label derivata
    printf '%s %s %s' "$1" "$2" "$3"
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

reg_set_binding() {  # <id> <kind> <uuid>
    dconf write "$(reg_project_path "$1")/bindings/$2/profile" "$(gv_str "$3")"
}

reg_get_binding() {  # <id> <kind> → uuid o vuoto
    gv_unwrap "$(dconf read "$(reg_project_path "$1")/bindings/$2/profile" 2>/dev/null || echo '')"
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
    echo "$id"
}

# ---- Profili Ptyxis (materializzazione) -------------------------------------

ptx_available() {
    command -v dconf >/dev/null 2>&1 || return 1
    local u; u="$(dconf read "$PTX_UUIDS" 2>/dev/null || echo '')"
    [[ -n "$u" && "$u" != "@as []" && "$u" != "[]" ]]
}

ptx_list_uuids() {
    dconf read "$PTX_UUIDS" 2>/dev/null | tr -d "[]' " | tr ',' '\n' | sed '/^$/d'
}

ptx_norm_path() {
    local p="$1"; p="${p/#\~/$HOME}"
    realpath -m "$p" 2>/dev/null || echo "$p"
}

ptx_cmd() { dconf read "${PTX_ROOT}/Profiles/$1/custom-command" 2>/dev/null || echo ''; }

ptx_label() { gv_unwrap "$(dconf read "${PTX_ROOT}/Profiles/$1/label" 2>/dev/null || echo '')"; }

# Estrae il path dopo "cd " dal custom-command, normalizzato (gestisce ~ e quote).
ptx_profile_dir() {  # <uuid> → path o vuoto
    local cmd raw
    cmd="$(ptx_cmd "$1")"
    [[ -z "$cmd" ]] && return 0
    raw="$(echo "$cmd" | sed -nE 's/.*cd ([^&]+) &&.*/\1/p' | sed -E "s/^['\"]//; s/['\"[:space:]]+$//")"
    [[ -z "$raw" ]] && return 0
    ptx_norm_path "$raw"
}

# Trova l'UUID del profilo che serve <dir> per la surface <kind>.
# claude → custom-command con 'claude --name'; deck → custom-command/label deck.
ptx_find_for_surface() {  # <dir> <kind> → uuid o vuoto
    local dir="$1" kind="$2" target u pdir cmd
    target="$(ptx_norm_path "$dir")"
    while read -r u; do
        [[ -z "$u" ]] && continue
        pdir="$(ptx_profile_dir "$u")"
        [[ "$pdir" == "$target" ]] || continue
        cmd="$(ptx_cmd "$u")"
        if [[ "$kind" == "claude" && "$cmd" == *"claude --name"* ]]; then
            echo "$u"; return 0
        fi
        if [[ "$kind" == "deck" && ( "$cmd" == *loom-deck* || "$cmd" == *"[deck]"* || "$cmd" == *"· deck"* ) ]]; then
            echo "$u"; return 0
        fi
    done < <(ptx_list_uuids)
    return 0
}

ptx_append_uuid() {  # <uuid>
    local new="$1" cur
    cur="$(dconf read "$PTX_UUIDS" 2>/dev/null || echo '')"
    if [[ -z "$cur" || "$cur" == "@as []" || "$cur" == "[]" ]]; then
        dconf write "$PTX_UUIDS" "['${new}']"
    else
        dconf write "$PTX_UUIDS" "${cur%]}, '${new}']"
    fi
}

# Genera un profilo Ptyxis claude derivato dal registry. Echoes il nuovo UUID.
ptx_generate_claude() {  # <dir> <label> → uuid
    local dir="$1" label="$2" uuid d
    uuid="$(uuidgen | tr -d '-')"
    d="${PTX_ROOT}/Profiles/${uuid}"
    dconf write "${d}/label" "$(gv_str "$label")"
    dconf write "${d}/custom-command" "$(gv_str "bash -c \"cd ${dir} && claude --name '${label}'; exec bash\"")"
    dconf write "${d}/use-custom-command" "true"
    ptx_append_uuid "$uuid"
    echo "$uuid"
}
