#!/usr/bin/env bash

# =============================================================================
# resolve-registry-path.sh — dove atterra il registro di findings, senza chiedere
# Usage: resolve-registry-path.sh --skill <nome> --perimeter <slug>
# =============================================================================
#
# Il registro di align-doc / drain-doc / lint-doc vive UN COMMIT: entra in
# cronologia per restare consultabile con `git show`, poi sparisce dal working
# tree. Non e' doc di progetto e non e' cantiere da conservare.
#
# Path fisso: file .md nudo in project root, nessuna cartella. Una cartella che
# per costruzione resta vuota non organizza niente, e ogni cartella dot-prefixed
# e' superficie che un .gitignore di progetto puo' prendere. Un file nudo in root
# si difende proprio perche' da' fastidio: se una run muore a meta', il residuo e'
# visibile invece che archiviato.
#
# Mai sotto {docs_root}/: e' il perimetro di doc-metrics.sh e build-index.sh, e
# li' dentro il registro verrebbe misurato dalla skill che lo sta scrivendo, con
# il generatore dell'indice che gli chiede un TLDR che non ha ragione di avere.
#
# Nome:  loom-registry-<YYYYMMDD-HHMM>-<skill>-<perimetro>.md
#   Il timestamp al minuto da' l'unicita' fra run — un basename costante collide
#   alla seconda esecuzione, e `git log --follow` su un path costante mescola run
#   diverse. Il perimetro rende `git log` leggibile senza aprire il file; il
#   prefisso dichiara la provenienza a chi ne trova uno orfano in root.
#
# Va invocato PRIMA di spawnare qualunque subagent: qui dentro c'e' il controllo
# gitignore, che e' hard error. Il commit di registrazione e' l'unico custode dei
# finding — un registro ignorato non entra in nessun commit, quindi proseguire lo
# cancellerebbe senza lasciare traccia da nessuna parte.
#
# Stampa (ultima riga, parsabile):
#   REGISTRY_PATH=<path assoluto del file registro>
#
# Il file NON viene creato: lo scrive il chiamante. Qui si risolve solo dove.
#
# Env: PROJECT_ROOT
# Exit: 0 = risolto · 1 = errore duro (arg mancante, non un repo, path ignorato)
# =============================================================================

set -uo pipefail

SKILL=""
PERIMETER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skill)     SKILL="$2"; shift 2 ;;
        --perimeter) PERIMETER="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done

slugify() {
    local s
    s="$(tr '[:upper:]' '[:lower:]' <<< "$1")"
    s="$(tr -c 'a-z0-9\n' '-' <<< "$s")"
    s="$(tr -s '-' <<< "$s")"
    s="${s#-}"
    printf '%s' "${s%-}"
}

SKILL="$(slugify "$SKILL")"
PERIMETER="$(slugify "$PERIMETER")"

[[ -n "$SKILL" ]]     || { echo "ERROR: --skill <nome> obbligatorio" >&2; exit 1; }
[[ -n "$PERIMETER" ]] || { echo "ERROR: --perimeter <slug> obbligatorio (usa 'inbox' o 'full' se il perimetro non ha un nome naturale)" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"

PROJECT_ROOT="$(lw_find_project_root)"
NAME="loom-registry-$(date +%Y%m%d-%H%M)-${SKILL}-${PERIMETER}.md"
REGISTRY_PATH="${PROJECT_ROOT}/${NAME}"

if ! git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: ${PROJECT_ROOT} non e' un repository git" >&2
    echo "  Il ciclo write -> commit -> delete non ha dove registrare: fermati." >&2
    exit 1
fi

if RULE="$(git -C "$PROJECT_ROOT" check-ignore -v -- "$REGISTRY_PATH" 2>/dev/null)"; then
    echo "ERROR: il registro sarebbe ignorato da git, quindi nessun commit lo conserverebbe" >&2
    echo "  path:   ${REGISTRY_PATH}" >&2
    echo "  regola: ${RULE}" >&2
    echo "  Togli la regola dal .gitignore: il commit di registrazione e' l'unico custode dei finding." >&2
    exit 1
fi

echo "REGISTRY_PATH=${REGISTRY_PATH}"
