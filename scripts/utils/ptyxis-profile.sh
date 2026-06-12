#!/bin/bash
set -euo pipefail

# =============================================================================
# ptyxis-profile.sh - Gestione profili terminale Ptyxis per lane worktree
# Usage:
#   ptyxis-profile.sh add <repo-path> <worktree-path> <lane>
#   ptyxis-profile.sh remove <worktree-path>
#
# add:    se esiste un profilo Ptyxis il cui custom-command punta a <repo-path>,
#         lo duplica per il worktree: label + " [lane]", cd → <worktree-path>.
#         Idempotente: se esiste già un profilo per <worktree-path>, skip.
# remove: elimina il profilo Ptyxis il cui custom-command punta a <worktree-path>.
#
# AUTO-DETECT: se dconf non è disponibile o Ptyxis non ha profili → noop (exit 0).
# Best-effort: pensato per essere chiamato con `|| true` da spawn-lane/merge-lane.
# =============================================================================

DCONF_ROOT="/org/gnome/Ptyxis"
UUIDS_KEY="${DCONF_ROOT}/profile-uuids"

# ---------------------------------------------------------------------------
# Guard: Ptyxis/dconf disponibili?
# ---------------------------------------------------------------------------

_ptyxis_available() {
    command -v dconf >/dev/null 2>&1 || return 1
    local uuids
    uuids="$(dconf read "$UUIDS_KEY" 2>/dev/null || echo "")"
    [[ -n "$uuids" && "$uuids" != "@as []" && "$uuids" != "[]" ]]
}

# ---------------------------------------------------------------------------
# Helper: normalizza path (espande ~, risolve)
# ---------------------------------------------------------------------------

_norm_path() {
    local p="$1"
    p="${p/#\~/$HOME}"
    realpath -m "$p" 2>/dev/null || echo "$p"
}

# ---------------------------------------------------------------------------
# Helper: estrae il path dopo "cd " dal custom-command
# Input:  'bash -c "cd ~/foo/bar && exec bash"'  (output di dconf read)
# Output: ~/foo/bar  (normalizzato)
# ---------------------------------------------------------------------------

_profile_path() {
    local uuid="$1"
    local cmd
    cmd="$(dconf read "${DCONF_ROOT}/Profiles/${uuid}/custom-command" 2>/dev/null || echo "")"
    [[ -z "$cmd" ]] && return 0
    local raw
    raw="$(echo "$cmd" | sed -nE 's/.*cd ([^&]+) &&.*/\1/p' | sed -E 's/[[:space:]]+$//')"
    [[ -z "$raw" ]] && return 0
    _norm_path "$raw"
}

# ---------------------------------------------------------------------------
# Helper: lista UUID dei profili (uno per riga)
# ---------------------------------------------------------------------------

_list_uuids() {
    dconf read "$UUIDS_KEY" 2>/dev/null \
        | tr -d "[]' " | tr ',' '\n' | sed '/^$/d'
}

# ---------------------------------------------------------------------------
# Helper: trova UUID del primo profilo che punta a <path>
# ---------------------------------------------------------------------------

_find_uuid_by_path() {
    local target
    target="$(_norm_path "$1")"
    local uuid
    while read -r uuid; do
        [[ -z "$uuid" ]] && continue
        local p
        p="$(_profile_path "$uuid")"
        if [[ -n "$p" && "$p" == "$target" ]]; then
            echo "$uuid"
            return 0
        fi
    done < <(_list_uuids)
    return 0
}

# ---------------------------------------------------------------------------
# Helper: append UUID a profile-uuids
# ---------------------------------------------------------------------------

_append_uuid() {
    local new_uuid="$1"
    local current
    current="$(dconf read "$UUIDS_KEY" 2>/dev/null || echo "")"
    if [[ -z "$current" || "$current" == "@as []" || "$current" == "[]" ]]; then
        dconf write "$UUIDS_KEY" "['${new_uuid}']"
    else
        dconf write "$UUIDS_KEY" "${current%]}, '${new_uuid}']"
    fi
}

# ---------------------------------------------------------------------------
# Helper: rimuove UUID da profile-uuids
# ---------------------------------------------------------------------------

_remove_uuid() {
    local uuid="$1"
    local current
    current="$(dconf read "$UUIDS_KEY" 2>/dev/null || echo "")"
    [[ -z "$current" ]] && return 0
    local updated
    updated="$(echo "$current" \
        | sed -E "s/'${uuid}', ?//; s/, ?'${uuid}'//; s/'${uuid}'//")"
    dconf write "$UUIDS_KEY" "$updated"
}

# ===========================================================================
# Comando: add
# ===========================================================================

cmd_add() {
    local repo_path="$1"
    local wt_path="$2"
    local lane="$3"

    # Idempotenza: profilo per il worktree già presente?
    local existing
    existing="$(_find_uuid_by_path "$wt_path")"
    if [[ -n "$existing" ]]; then
        echo "-> [ptyxis] profilo già presente per ${wt_path} (${existing}), skip"
        return 0
    fi

    # Trova profilo sorgente che punta al repo
    local src_uuid
    src_uuid="$(_find_uuid_by_path "$repo_path")"
    if [[ -z "$src_uuid" ]]; then
        echo "-> [ptyxis] nessun profilo associato a ${repo_path}, skip"
        return 0
    fi

    local new_uuid
    new_uuid="$(uuidgen | tr -d '-')"
    local src_dir="${DCONF_ROOT}/Profiles/${src_uuid}"
    local new_dir="${DCONF_ROOT}/Profiles/${new_uuid}"

    # Copia tutte le chiavi dal profilo sorgente
    local key val
    while read -r key; do
        [[ -z "$key" ]] && continue
        val="$(dconf read "${src_dir}/${key}" 2>/dev/null || echo "")"
        [[ -n "$val" ]] && dconf write "${new_dir}/${key}" "$val"
    done < <(dconf list "${src_dir}/" 2>/dev/null)

    # Override label: append " [lane]"
    local src_label
    src_label="$(dconf read "${src_dir}/label" 2>/dev/null || echo "''")"
    local new_label="${src_label%\'} [${lane}]'"
    dconf write "${new_dir}/label" "$new_label"

    # Override custom-command: cd → worktree path
    dconf write "${new_dir}/custom-command" "'bash -c \"cd ${wt_path} && exec bash\"'"
    dconf write "${new_dir}/use-custom-command" "true"

    # Registra nel profile-uuids
    _append_uuid "$new_uuid"

    echo "-> [ptyxis] profilo lane creato: ${new_label} (${new_uuid})"
}

# ===========================================================================
# Comando: remove
# ===========================================================================

cmd_remove() {
    local wt_path="$1"

    local uuid
    uuid="$(_find_uuid_by_path "$wt_path")"
    if [[ -z "$uuid" ]]; then
        echo "-> [ptyxis] nessun profilo associato a ${wt_path}, skip"
        return 0
    fi

    _remove_uuid "$uuid"
    dconf reset -f "${DCONF_ROOT}/Profiles/${uuid}/" 2>/dev/null || true

    echo "-> [ptyxis] profilo lane rimosso: ${uuid}"
}

# ===========================================================================
# Main
# ===========================================================================

ACTION="${1:-}"

if ! _ptyxis_available; then
    # Noop silenzioso su macchine senza Ptyxis/dconf
    exit 0
fi

case "$ACTION" in
    add)
        [[ $# -eq 4 ]] || { echo "Usage: ptyxis-profile.sh add <repo-path> <worktree-path> <lane>" >&2; exit 1; }
        cmd_add "$2" "$3" "$4"
        ;;
    remove)
        [[ $# -eq 2 ]] || { echo "Usage: ptyxis-profile.sh remove <worktree-path>" >&2; exit 1; }
        cmd_remove "$2"
        ;;
    *)
        echo "Usage: ptyxis-profile.sh {add <repo> <wt> <lane> | remove <wt>}" >&2
        exit 1
        ;;
esac
