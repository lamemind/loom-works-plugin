#!/bin/bash
set -uo pipefail

# =============================================================================
# run-lane-hook.sh - Invoca l'hook on-lane-spawned project-level
# Usage: run-lane-hook.sh [--hook <path>] --lane <name>
#                         --project-root <path> --lane-root <path>
#
# Silent no-op se:
#   --hook vuoto o non passato, oppure file assente/non-eseguibile.
#
# UNA sola invocazione, sempre, sulla LANE PARENT ROOT ({project}-{lane}):
#   - $1  = lane parent root (path assoluto, unico parametro)
#   - CWD = lane parent root (cd prima di eseguire)
#   Mono o multi repo è irrilevante: si esegue una volta sola sulla root.
#
# Failure (exit != 0): warn evidente + retry command, exit 0.
# spawn-lane non viene mai rotto dall'hook.
#
# Env iniettato nell'hook:
#   LOOM_LANE          nome lane
#   LOOM_WORKTREE      lane parent root (= $1 = CWD)
#   LOOM_PROJECT_ROOT  project root (dove vive .claude/)
# =============================================================================

HOOK_PATH=""
LANE=""
PROJECT_ROOT_ARG=""
LANE_ROOT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --hook)         HOOK_PATH="$2"; shift 2 ;;
        --lane)         LANE="$2"; shift 2 ;;
        --project-root) PROJECT_ROOT_ARG="$2"; shift 2 ;;
        --lane-root)    LANE_ROOT="$2"; shift 2 ;;
        -*)             echo "ERROR: flag sconosciuto: $1" >&2; exit 1 ;;
        *)              shift ;;
    esac
done

# Silent no-op se hook non specificato
[[ -z "${HOOK_PATH}" ]] && exit 0

PR="${PROJECT_ROOT_ARG:-${PWD}}"

# Risolvi path hook relativo rispetto a PROJECT_ROOT (assoluto: cd nella lane root non lo rompe)
RESOLVED_HOOK="${HOOK_PATH}"
[[ "${HOOK_PATH}" != /* ]] && RESOLVED_HOOK="${PR}/${HOOK_PATH}"

# Silent no-op se file assente o non eseguibile
[[ -f "${RESOLVED_HOOK}" ]] || exit 0
[[ -x "${RESOLVED_HOOK}" ]] || exit 0

# Niente lane root → niente da fare
[[ -z "${LANE_ROOT}" ]] && exit 0

# ---------------------------------------------------------------------------
# Invocazione singola: cd nella lane root, $1 = lane root
# ---------------------------------------------------------------------------

echo "-> Hook on-lane-spawned: ${RESOLVED_HOOK}  (root: ${LANE_ROOT})"

if ( cd "${LANE_ROOT}" \
     && LOOM_LANE="${LANE}" \
        LOOM_WORKTREE="${LANE_ROOT}" \
        LOOM_PROJECT_ROOT="${PR}" \
        "${RESOLVED_HOOK}" "${LANE_ROOT}" ); then
    echo "-> ✔️ Hook completato"
else
    HOOK_EXIT=$?
    cat <<WARN

┌─────────────────────────────────────────────────────────────────────────────
│ ⚠️  WARNING: Hook on-lane-spawned fallito (exit ${HOOK_EXIT})
│    Lane root: ${LANE_ROOT}
│    La lane è stata creata correttamente — puoi continuare.
│
│    Correggi l'hook, poi riesegui (CWD = lane root, \$1 = lane root):
│
│      ( cd '${LANE_ROOT}' && \\
│        LOOM_LANE='${LANE}' \\
│        LOOM_WORKTREE='${LANE_ROOT}' \\
│        LOOM_PROJECT_ROOT='${PR}' \\
│        '${RESOLVED_HOOK}' '${LANE_ROOT}' )
│
│    Oppure via helper:
│      '${BASH_SOURCE[0]}' --hook '${HOOK_PATH}' \\
│        --lane '${LANE}' --project-root '${PR}' \\
│        --lane-root '${LANE_ROOT}'
└─────────────────────────────────────────────────────────────────────────────
WARN
fi

# exit 0 sempre: spawn-lane non deve rompere per colpa dell'hook
exit 0
