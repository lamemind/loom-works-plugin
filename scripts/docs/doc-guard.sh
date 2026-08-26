#!/usr/bin/env bash

# =============================================================================
# doc-guard.sh — le guardie di ingresso dei flussi non presidiati
# Usage: doc-guard.sh worktree --docs-root <name> [--extra <path>]...
# =============================================================================
#
# `worktree`: verifica che il working tree sia pulito sul perimetro doc —
# {docs_root}/inbox/, {docs_root}/reference/, CLAUDE.md, piu' gli --extra.
# Una sola invocazione `git status --porcelain -uall` sul perimetro: il -uall
# e' obbligatorio, o una cartella interamente untracked collassa nella riga
# `?? <dir>/` e i singoli file diventano invisibili.
#
# Exit (famiglia guardia): 0 pulito · 2 sporco, con l'elenco dei file su stdout
#                          · 1 non e' un repository git (o errore d'uso)
#
# La STOP e' politica del CHIAMANTE, non dello script: qui 2 dice «ho trovato
# qualcosa», e sono i flussi di drain a decidere che quel qualcosa e' un red
# flag. Tenere il verdetto nello script e la politica nella skill permette a un
# chiamante futuro (una diagnostica, un dry-run) di usare la stessa guardia
# senza fermarsi.
#
# NESSUN lock per il drain concorrente (scelta di spec §5.1): il caso realistico
# e' sequenziale — un run morto a meta' lascia il tree sporco e il successivo si
# ferma qui. Un lockfile stale bloccherebbe ogni drain futuro e nessuno lo
# andrebbe a cercare. Il drain ri-verifica la guardia PRIMA DI OGNI FILE, non
# solo prima del primo: il confine fra due file e' un punto a tree pulito, e la
# guardia li' prende lo sporco esterno sopraggiunto durante la coda.
# =============================================================================

set -uo pipefail

die_usage() { echo "[doc-guard] ERROR: $*" >&2; exit 1; }

[[ $# -ge 1 ]] || die_usage "sottocomando richiesto: worktree"
SUB="$1"; shift
[[ "$SUB" == "worktree" ]] || die_usage "sottocomando ignoto: ${SUB}"

DOCS_ROOT=""
EXTRA=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --docs-root) DOCS_ROOT="$2"; shift 2 ;;
        --extra)     EXTRA+=("$2"); shift 2 ;;
        *) die_usage "argomento ignoto: $1" ;;
    esac
done
[[ -n "$DOCS_ROOT" ]] || die_usage "--docs-root obbligatorio"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"

PROJECT_ROOT="$(lw_find_project_root)"

git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
    || { echo "[doc-guard] ERROR: non e' un repository git: ${PROJECT_ROOT}" >&2; exit 1; }

PATHSPEC=("${DOCS_ROOT}/inbox" "${DOCS_ROOT}/reference" "CLAUDE.md")
for e in ${EXTRA[@]+"${EXTRA[@]}"}; do
    PATHSPEC+=("$e")
done

DIRTY="$(git -C "$PROJECT_ROOT" status --porcelain -uall -- "${PATHSPEC[@]}" 2>/dev/null)"

if [[ -n "$DIRTY" ]]; then
    echo "$DIRTY"
    exit 2
fi
exit 0
