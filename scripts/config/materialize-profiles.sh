#!/bin/bash
set -euo pipefail

# =============================================================================
# materialize-profiles.sh - Sync registry → profili Ptyxis (surface tracked)
# Usage: materialize-profiles.sh [<id>]     (default: tutti i progetti)
# =============================================================================
#
# Per ogni surface TRACKED abilitata (claude, deck) di un progetto:
#   - se il binding è già in registry → skip (idempotente)
#   - se esiste un profilo Ptyxis per (dir, kind) → ADOTTA il suo UUID
#     (non distruttivo: non riscrive il profilo esistente)
#   - se manca:
#       claude → GENERA un profilo derivato (label + custom-command dal registry)
#       deck   → skip + log (il comando di lancio è loom-deck-specifico, non
#                generabile a livello plugin; va materializzato lato deck)
# Scrive il binding in /org/lamemind/loom/projects/<id>/bindings/<kind>/profile.
# Le surface LAUNCH (lista `launch` custom, es. codium/idea) non hanno profilo Ptyxis
# → ignorate dalla materializzazione (le lancia il consumer via command @project-root).
# Noop silenzioso se Ptyxis/dconf assenti.
# =============================================================================

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${HERE}/lib-config.sh"

ONLY_ID="${1:-}"

TRACKED_KINDS=(claude deck)

if ! ptx_available; then
    echo "[materialize] Ptyxis/dconf assente → noop"
    exit 0
fi

# Un profilo claude già materializzato porta la label congelata nel proprio
# custom-command: senza questo passaggio resterebbe alla formula con cui è stato
# generato anche dopo un cambio del contratto-label, uscendo dal match di compass.
sync_claude_label() {  # <id> <kind> <uuid> <label>
    [[ "$2" == "claude" ]] || return 0
    if ptx_sync_claude_label "$3" "$4"; then
        echo "[materialize] $1/$2: label riallineata → $4"
    fi
}

process_project() {
    local id="$1"
    local dir emoji name label surfaces_raw kind bound uuid
    dir="$(reg_get "$id" dir)"
    emoji="$(reg_get "$id" emoji)"
    name="$(reg_get "$id" name)"
    label="$(cfg_label "$emoji" "$name")"
    surfaces_raw="$(dconf read "$(reg_project_path "$id")/surfaces" 2>/dev/null || echo '')"

    if [[ -z "$dir" ]]; then
        echo "[materialize] $id: nessuna dir nel registry → skip"
        return 0
    fi

    for kind in "${TRACKED_KINDS[@]}"; do
        # surface abilitata nel registry?
        echo "$surfaces_raw" | grep -q "'$kind'" || continue

        bound="$(reg_get_binding "$id" "$kind")"
        if [[ -n "$bound" ]]; then
            echo "[materialize] $id/$kind: già bound ($bound)"
            sync_claude_label "$id" "$kind" "$bound" "$label"
            continue
        fi

        uuid="$(ptx_find_for_surface "$dir" "$kind")"
        if [[ -n "$uuid" ]]; then
            reg_set_binding "$id" "$kind" "$uuid"
            echo "[materialize] $id/$kind: adottato profilo esistente $uuid"
            sync_claude_label "$id" "$kind" "$uuid" "$label"
            continue
        fi

        if [[ "$kind" == "claude" ]]; then
            uuid="$(ptx_generate_claude "$dir" "$label")"
            reg_set_binding "$id" "$kind" "$uuid"
            echo "[materialize] $id/$kind: generato profilo $uuid (label: $label)"
        else
            echo "[materialize] $id/$kind: nessun profilo esistente; generate non supportato (loom-deck-specific) → skip"
        fi
    done
}

if [[ -n "$ONLY_ID" ]]; then
    process_project "$ONLY_ID"
else
    while read -r id; do
        [[ -z "$id" ]] && continue
        process_project "$id"
    done < <(reg_list_projects)
fi
