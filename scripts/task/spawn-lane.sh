#!/bin/bash
set -euo pipefail

# =============================================================================
# spawn-lane.sh - Crea worktree per una lane
# Usage: spawn-lane.sh [--docs-root <root>] [--lane-hook <path>] <lane> [repo1 repo2 ...]
#
# Modalità:
#   Single-project (nessun repo): worktree {project}-{lane} da PROJECT_ROOT
#   Multi-project  (repo...):     worktree {repo}-{lane} per ogni repo specificato
#
# I repo sono nomi (non path) risolti come sibling di PROJECT_ROOT.
# Idempotente: se il worktree esiste già viene skippato.
# =============================================================================

LANE_HOOK=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --docs-root)  LOOM_DOCS_ROOT="$2"; shift 2 ;;
        --lane-hook)  LANE_HOOK="$2"; shift 2 ;;
        -*) echo "ERROR: Flag sconosciuto: $1"; exit 1 ;;
        *) break ;;
    esac
done

LANE="${1:?Usage: spawn-lane.sh [--docs-root <root>] <lane> [repo1 repo2 ...]}"
shift
REPOS=("$@")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"
# shellcheck source=../utils/assert-capability.sh
"${SCRIPT_DIR}/../utils/assert-capability.sh" repo

PROJECT_ROOT="$(lw_find_project_root)"
WORKTREE_BASE="$(dirname "$PROJECT_ROOT")"
PROJECT_NAME="$(basename "$PROJECT_ROOT")"

# Lane parent root: target unico dell'hook on-lane-spawned ({project}-{lane})
LANE_ROOT="${WORKTREE_BASE}/${PROJECT_NAME}-${LANE}"

# ---------------------------------------------------------------------------
# Helper: crea un singolo worktree
# Args: REPO_DIR WORKTREE_PATH
# ---------------------------------------------------------------------------

_spawn_one() {
    local repo_dir="$1"
    local wt_path="$2"
    local wt_name
    wt_name="$(basename "$wt_path")"

    if [[ -d "$wt_path" ]]; then
        echo "-> Lane già attiva: ${wt_path}"
        echo "   cd ${wt_path} && claude"
        return 0
    fi

    # Verifica dirty working tree
    if ! git -C "$repo_dir" diff --quiet HEAD -- 2>/dev/null; then
        echo ""
        echo "WARNING: Modifiche non committate in ${repo_dir}."
        echo "   Il worktree viene creato dal HEAD committato — le modifiche locali NON saranno nel worktree."
        echo ""
    fi

    local base_branch
    base_branch="$(git -C "$repo_dir" branch --show-current 2>/dev/null || echo "main")"
    [[ -z "$base_branch" ]] && base_branch="main"

    local branch_lane="feat/${LANE}"

    echo "-> Creo worktree: ${wt_path} (branch ${branch_lane} da ${base_branch})"
    git -C "$repo_dir" worktree add -b "$branch_lane" "$wt_path" "$base_branch"

    # Init worktree (copia settings.local.json, exclude parent)
    "${SCRIPT_DIR}/../utils/init-worktree.sh" "$wt_path" "$repo_dir"

    # Profilo terminale Ptyxis (best-effort, noop se Ptyxis assente)
    "${SCRIPT_DIR}/../utils/ptyxis-profile.sh" add "$repo_dir" "$wt_path" "$LANE" || true

    echo "-> ✔️ worktree=${wt_path} branch=${branch_lane}"
    echo "   cd ${wt_path} && claude"
}

# ---------------------------------------------------------------------------
# Single-project (nessun repo specificato)
# ---------------------------------------------------------------------------

if [[ ${#REPOS[@]} -eq 0 ]]; then
    echo "SPAWN-LANE lane=${LANE} mode=single-project project=${PROJECT_NAME}"

    WORKTREE_PATH="${WORKTREE_BASE}/${PROJECT_NAME}-${LANE}"
    _spawn_one "$PROJECT_ROOT" "$WORKTREE_PATH"

# ---------------------------------------------------------------------------
# Multi-project (repos specificati come sibling di PROJECT_ROOT)
# ---------------------------------------------------------------------------
else
    echo "SPAWN-LANE lane=${LANE} mode=multi-project repos=${REPOS[*]}"

    for REPO in "${REPOS[@]}"; do
        REPO_PATH="${WORKTREE_BASE}/${REPO}"

        if [[ ! -d "$REPO_PATH" ]]; then
            echo "ERROR: Repo non trovato: ${REPO_PATH}" >&2
            exit 1
        fi

        if ! git -C "$REPO_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            echo "ERROR: ${REPO_PATH} non è un repository git" >&2
            exit 1
        fi

        LANE_WT_PATH="${WORKTREE_BASE}/${REPO}-${LANE}"
        _spawn_one "$REPO_PATH" "$LANE_WT_PATH"
    done
fi

# ---------------------------------------------------------------------------
# Aggiorna la vista LANES in tasks.md (D3: git=verità, tasks.md=vista)
# ---------------------------------------------------------------------------

PROJECT_ROOT="$PROJECT_ROOT" "${SCRIPT_DIR}/../utils/render-lanes.sh" \
    --docs-root "$(lw_docs_root)" || true

# ---------------------------------------------------------------------------
# Hook on-lane-spawned (D2: UNA invocazione sulla lane root {project}-{lane})
# ---------------------------------------------------------------------------

"${SCRIPT_DIR}/../utils/run-lane-hook.sh" \
    --hook         "${LANE_HOOK}" \
    --lane         "${LANE}" \
    --project-root "${PROJECT_ROOT}" \
    --lane-root    "${LANE_ROOT}"
