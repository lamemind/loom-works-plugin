#!/bin/bash

# =============================================================================
# assert-capability.sh - Gate per skill repo-dependent
# Usage: assert-capability.sh <capability>
#
# Capabilities:
#   repo  — richiede project_mode=repo (git repository)
#
# Exit 0: capability disponibile.
# Exit 1: capability assente — messaggio su stderr, non procedere.
# =============================================================================

CAP="${1:?Usage: assert-capability.sh <capability>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

case "$CAP" in
    repo)
        if ! lw_is_repo; then
            echo "ERROR: Questa operazione richiede un progetto git (project_mode=repo)." >&2
            echo "       Le skill lane (spawn-lane, merge-lane) funzionano solo in modalità repo." >&2
            echo "       Usa /loom-works:init per configurare il progetto." >&2
            exit 1
        fi
        ;;
    *)
        echo "ERROR: Capability sconosciuta: '${CAP}'. Valori supportati: repo" >&2
        exit 1
        ;;
esac
