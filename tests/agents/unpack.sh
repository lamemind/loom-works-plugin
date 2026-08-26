#!/usr/bin/env bash

# =============================================================================
# unpack.sh — estrae la fixture, e per default la idrata
# Usage: tests/agents/unpack.sh [<dest>] [--hydrate=false]
# =============================================================================
#
# Idratare = copiare i sorgenti vivi (agent buildati, primitive bash), git init
# con identita' locale e nessun remote, commit, POI collocare i casi secondo il
# loro case.conf. La cartella per EDITARE la fixture nasce non idratata per
# costruzione (--hydrate=false): e' la ragione per cui l'idratazione e'
# un'opzione di unpack e non un comando a parte.
#
# Non cancella mai niente: stampa il path e finisce.
# =============================================================================

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/bench-lib.sh"

DEST=""
HYDRATE=1
for a in "$@"; do
    case "$a" in
        --hydrate=false) HYDRATE=0 ;;
        --hydrate=true)  HYDRATE=1 ;;
        *) DEST="$a" ;;
    esac
done
[[ -z "$DEST" ]] && DEST="$(mktemp -d /tmp/loom-agent-fixture.XXXXXX)"

bench_unpack "$DEST" "$HYDRATE"
echo "$DEST"
