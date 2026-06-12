#!/bin/bash
set -euo pipefail

# =============================================================================
# merge-lane.sh - Merge lane in main
# Usage: merge-lane.sh [--docs-root <root>] <lane> [--cleanup]
#
# Auto-detecta tutti i worktrees *-{lane} in WORKTREE_BASE.
# Modalità auto-rilevata:
#   Single-project: {project}-{lane} in WORKTREE_BASE → merge in PROJECT_ROOT
#   Multi-project:  {repo}-{lane} (più match, nessuno = PROJECT_NAME) → merge in ciascun {repo}
#
# Exit code:
#   0 = successo
#   1 = errore validazione / worktree non trovato
#   2 = conflitto git → invocare /loom-works:reconcile-tasks {conflict_dir}
#
# Nota: push è opzionale (remote potrebbe non esistere). Fallimento push = warning, non errore.
# =============================================================================

CLEANUP=false
LANE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --docs-root) LOOM_DOCS_ROOT="$2"; shift 2 ;;
        --cleanup) CLEANUP=true; shift ;;
        -*) echo "ERROR: Flag sconosciuto: $1"; exit 1 ;;
        *) LANE="$1"; shift ;;
    esac
done

: "${LANE:?Usage: merge-lane.sh [--docs-root <root>] <lane> [--cleanup]}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"
"${SCRIPT_DIR}/../utils/assert-capability.sh" repo

PROJECT_ROOT="$(lw_find_project_root)"
WORKTREE_BASE="$(dirname "$PROJECT_ROOT")"
PROJECT_NAME="$(basename "$PROJECT_ROOT")"
DOCS_ROOT="$(lw_docs_root)"
TASKS_FILE="${PROJECT_ROOT}/${DOCS_ROOT}/tasks.md"

# ---------------------------------------------------------------------------
# Auto-detect worktrees per la lane
# Cerca folder *-{lane} in WORKTREE_BASE che siano git repos
# ---------------------------------------------------------------------------

declare -a LANE_WORKTREES=()
declare -a LANE_REPOS=()

while IFS= read -r -d '' candidate; do
    wt_name="$(basename "$candidate")"
    # Deve matchare pattern *-{lane} esattamente
    if [[ "$wt_name" == *"-${LANE}" ]]; then
        # Deve essere un git worktree (non il checkout principale)
        if [[ -d "${candidate}/.git" ]] || git -C "$candidate" rev-parse --git-dir >/dev/null 2>&1; then
            LANE_WORKTREES+=("$candidate")
            # Repo originale = rimuovi il suffisso "-{lane}"
            repo_name="${wt_name%-${LANE}}"
            LANE_REPOS+=("${WORKTREE_BASE}/${repo_name}")
        fi
    fi
done < <(find "$WORKTREE_BASE" -maxdepth 1 -type d -print0 2>/dev/null)

if [[ ${#LANE_WORKTREES[@]} -eq 0 ]]; then
    echo "ERROR: Nessun worktree trovato per lane '${LANE}' in ${WORKTREE_BASE}" >&2
    echo "   Attesi folder del tipo: ${WORKTREE_BASE}/*-${LANE}/" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Determina modalità: single-project se l'unico worktree è {project}-{lane}
# ---------------------------------------------------------------------------

IS_SINGLE=false
if [[ ${#LANE_WORKTREES[@]} -eq 1 && "$(basename "${LANE_WORKTREES[0]}")" == "${PROJECT_NAME}-${LANE}" ]]; then
    IS_SINGLE=true
fi

echo "MERGE-LANE lane=${LANE} mode=$(${IS_SINGLE} && echo single-project || echo multi-project) worktrees=${#LANE_WORKTREES[@]}"

# ---------------------------------------------------------------------------
# Helper: push opzionale (remote potrebbe non esistere)
# ---------------------------------------------------------------------------

_try_push() {
    local git_dir="$1"
    local branch="$2"
    git -C "$git_dir" push origin "$branch" 2>/dev/null || \
        echo "-> WARN: push skipped (nessun remote o push fallito)"
}

# ---------------------------------------------------------------------------
# Helper: merge singolo worktree nel suo repo originale
# ---------------------------------------------------------------------------

_merge_one() {
    local wt_path="$1"
    local repo_path="$2"
    local branch_lane
    branch_lane="$(git -C "$wt_path" branch --show-current 2>/dev/null || echo "feat/${LANE}")"
    local branch_base
    branch_base="$(git -C "$repo_path" branch --show-current 2>/dev/null || echo "main")"

    echo ""
    echo "--- Merge: $(basename "$wt_path") → $(basename "$repo_path") ---"

    # 1. Commit pending nel worktree lane
    cd "$wt_path"
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "-> commit pending (lane worktree)"
        git add -A
        git commit -m "feat: lane ${LANE} — pending changes before merge

Generated with Claude Code"
    else
        echo "-> no pending changes (lane worktree)"
    fi
    _try_push "$wt_path" "$branch_lane"

    # 2. Commit pending nel repo base
    cd "$repo_path"
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "-> commit pending (base repo)"
        git add -A
        git commit -m "chore: lane ${LANE} — pending changes before merge

Generated with Claude Code"
    fi

    # 3. Pre-merge: allinea lane con base (risolve conflitti nel WT lane)
    cd "$wt_path"
    if ! git merge "$branch_base" --no-edit 2>/dev/null; then
        echo "ERROR: Conflitti in lane worktree durante pre-merge" >&2
        echo "CONFLICT_DIR=${wt_path}"
        exit 2
    fi
    echo "-> lane allineata con base"
    _try_push "$wt_path" "$branch_lane"

    # 4. Merge: lane → base
    cd "$repo_path"
    if ! git merge "$branch_lane" --no-edit; then
        echo "ERROR: Conflitti nel repo base durante merge (inatteso dopo pre-merge)" >&2
        echo "CONFLICT_DIR=${repo_path}"
        exit 2
    fi
    echo "-> merge completato: $(basename "$wt_path") → $(basename "$repo_path")"
    _try_push "$repo_path" "$branch_base"
}

# ---------------------------------------------------------------------------
# Merge tutti i worktrees rilevati
# ---------------------------------------------------------------------------

for i in "${!LANE_WORKTREES[@]}"; do
    _merge_one "${LANE_WORKTREES[$i]}" "${LANE_REPOS[$i]}"
done

# ---------------------------------------------------------------------------
# Single-project: sync tasks.md → lane worktree (per prossima task)
# ---------------------------------------------------------------------------

if [[ "$IS_SINGLE" == true ]]; then
    LANE_WT="${LANE_WORKTREES[0]}"
    LANE_TASKS_FILE="${LANE_WT}/${DOCS_ROOT}/tasks.md"

    if [[ "$CLEANUP" != true && -f "$TASKS_FILE" && -d "$(dirname "$LANE_TASKS_FILE")" ]]; then
        cp "$TASKS_FILE" "$LANE_TASKS_FILE"
        echo "-> tasks.md sincronizzato al worktree lane"
    fi

    # Prod Validation pendenti (task Done con item non checkati)
    TASKS_DIR="${PROJECT_ROOT}/${DOCS_ROOT}/tasks"
    PROD_VALIDATION_OUTPUT=""
    if [[ -d "$TASKS_DIR" ]]; then
        for task_file in "$TASKS_DIR"/*.md; do
            [[ -f "$task_file" ]] || continue
            if ! grep -q 'Progress.*✔️' "$task_file" 2>/dev/null; then
                continue
            fi
            TASK_ID=$(basename "$task_file" | grep -oE '^[A-Z][0-9]+')
            [[ -z "$TASK_ID" ]] && continue
            PENDING=$(sed -n '/^## Prod Validation$/,/^## /{ /^## /d; /^\- \[ \]/p; }' "$task_file")
            if [[ -n "$PENDING" ]]; then
                PROD_VALIDATION_OUTPUT+="  ${TASK_ID}:
$(echo "$PENDING" | sed 's/^/    /')
"
            fi
        done
    fi
    if [[ -n "$PROD_VALIDATION_OUTPUT" ]]; then
        echo ""
        echo "PENDING PROD VALIDATION:"
        echo "$PROD_VALIDATION_OUTPUT"
    fi
fi

# ---------------------------------------------------------------------------
# Cleanup opzionale: rimuovi worktrees
# ---------------------------------------------------------------------------

if [[ "$CLEANUP" == true ]]; then
    for i in "${!LANE_WORKTREES[@]}"; do
        wt="${LANE_WORKTREES[$i]}"
        repo="${LANE_REPOS[$i]}"
        branch_lane="$(git -C "$wt" branch --show-current 2>/dev/null || echo "feat/${LANE}")"

        echo "-> rimuovo worktree: ${wt}"

        # Profilo terminale Ptyxis associato (best-effort, noop se assente)
        "${SCRIPT_DIR}/../utils/ptyxis-profile.sh" remove "$wt" || true

        cd "$repo"
        git worktree remove "$wt" --force 2>/dev/null || true
        git branch -d "$branch_lane" 2>/dev/null || true
        echo "-> ✔️ worktree rimosso: $(basename "$wt")"
    done
else
    echo ""
    for wt in "${LANE_WORKTREES[@]}"; do
        echo "-> ✔️ merge ok, worktree preservato: ${wt}"
        echo "   cd ${wt} && claude"
    done
fi

# ---------------------------------------------------------------------------
# Aggiorna la vista LANES in tasks.md (D3). Eseguito alla fine: in --cleanup i
# worktree sono già rimossi → la lane sparisce dalla vista; senza cleanup resta.
# ---------------------------------------------------------------------------

PROJECT_ROOT="$PROJECT_ROOT" "${SCRIPT_DIR}/../utils/render-lanes.sh" \
    --docs-root "$DOCS_ROOT" || true
