#!/bin/bash
set -euo pipefail

# =============================================================================
# refresh.sh - Ri-pulla la config di TUTTI i progetti registrati (file → dconf)
# Usage: refresh.sh
# =============================================================================
#
# Per ogni progetto in /org/lamemind/loom/projects/: rilegge la sua `dir` dal
# registry, poi rilegge dir/.claude/loom-works.json e aggiorna la config nel
# registry. Ripetibile, additiva. Progetti con file assente/invalido → skip.
# Noop silenzioso se dconf assente.
#
# NB: è il refresh PLUGIN-SIDE. Il refresh che compass fa al proprio avvio è
# codice embedded di compass (legge lo stesso registry dconf), non questo script.
# =============================================================================

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${HERE}/lib-config.sh"

if ! reg_available; then
    echo "[refresh] dconf assente → noop"
    exit 0
fi

count=0
skipped=0
while read -r id; do
    [[ -z "$id" ]] && continue
    dir="$(reg_get "$id" dir)"
    if [[ -z "$dir" ]]; then
        echo "[refresh] $id: nessuna dir nel registry → skip"
        skipped=$((skipped + 1))
        continue
    fi
    f="$(cfg_file_path "$dir")"
    if [[ ! -f "$f" ]]; then
        echo "[refresh] $id: file config assente ($f) → skip"
        skipped=$((skipped + 1))
        continue
    fi
    if new_id="$(reg_pull "$dir")"; then
        echo "[refresh] $id → aggiornato (id file: $new_id)"
        count=$((count + 1))
    else
        echo "[refresh] $id: config invalido → skip"
        skipped=$((skipped + 1))
    fi
done < <(reg_list_projects)

echo "[refresh] fatto: $count aggiornati, $skipped skippati"
