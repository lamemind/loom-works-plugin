#!/bin/bash

# =============================================================================
# checkpoint-task-analyze.sh - Raccoglie info per checkpoint-task
# Usage: checkpoint-task-analyze.sh [--task <id>]
# Env:   PROJECT_ROOT (default: $PWD), LOOM_TASK
# =============================================================================
#
# L'analisi diff <baseline>..HEAD ha senso solo sul binding di WORKTREE (symlink
# current-task.md): li' la task e' una sola e tutto il movimento del repo le
# appartiene. Con un binding di SESSIONE (arg esplicito o $LOOM_TASK) il worktree
# ospita N task in parallelo, quindi il diff raccoglie anche il lavoro delle altre
# — lo script lo salta e lascia al chiamante il compito di derivare i deliverables
# dal contesto della conversazione. Vedi docs/task-management.md §Detached.
# =============================================================================

TASK_ID_ARG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --docs-root) LOOM_DOCS_ROOT="$2"; shift 2 ;;
        --task) TASK_ID_ARG="$2"; shift 2 ;;
        *) break ;;
    esac
done

PROJECT_ROOT="${PROJECT_ROOT:-$PWD}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"

RESOLVED="$(lw_resolve_task "$TASK_ID_ARG")" || exit 1
eval "$RESOLVED"

PROGRESS=$(grep -m1 '^\- \*\*Progress\*\*:' "$TASK_FILE" | sed 's/.*: //')

if [[ "$TASK_SRC" != "symlink" ]]; then
    echo "CHECKPOINT-TASK-ANALYSIS task=${TASK_ID} src=${TASK_SRC} branch=$(lw_current_branch) progress=${PROGRESS} mode=detached-equivalent"
    echo ""
    echo "  Analisi diff saltata: binding di sessione (${TASK_SRC}), il worktree puo' ospitare"
    echo "  altre task in parallelo. Deriva i deliverables dal contesto e stagia a mano"
    echo "  (checkpoint-task-commit.sh --task ${TASK_ID} --no-add)."
    echo ""
    exit 0
fi

# Baseline derivato dalla history (lw_task_baseline_sha in lib.sh): ancorato
# all'ultimo '### Avanzamento' del Progress Log letto da HEAD.
BASELINE_SHA="$(lw_task_baseline_sha "$TASK_FILE")" || exit 1

CURRENT_BRANCH=$(lw_current_branch)
CURRENT_SHA=$(lw_current_sha)

FILES_COMMITTED=$(git -C "$PROJECT_ROOT" diff --name-only "${BASELINE_SHA}" 2>/dev/null || echo "")
FILES_UNCOMMITTED=$(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null || echo "")
COMMITS_SINCE=$(git -C "$PROJECT_ROOT" log "${BASELINE_SHA}..HEAD" --oneline 2>/dev/null || echo "")
DIFF_STATS=$(git -C "$PROJECT_ROOT" diff --stat "${BASELINE_SHA}" 2>/dev/null || echo "")

SHA_RANGE="$(git -C "$PROJECT_ROOT" rev-parse --short "${BASELINE_SHA}")..${CURRENT_SHA:-n/a}"
BRANCH_DISPLAY="${CURRENT_BRANCH:-n/a}"

echo "CHECKPOINT-TASK-ANALYSIS task=${TASK_ID} src=${TASK_SRC} branch=${BRANCH_DISPLAY} progress=${PROGRESS} sha=${SHA_RANGE} mode=linked"

if [[ -n "$COMMITS_SINCE" ]]; then
    echo ""
    echo "COMMITS SINCE CHECKPOINT:"
    echo "$COMMITS_SINCE" | while read -r line; do
        echo "  $line"
    done
fi

if [[ -n "$FILES_COMMITTED" ]]; then
    echo ""
    echo "FILES MODIFIED (committed):"
    echo "$FILES_COMMITTED" | while read -r line; do
        echo "  - $line"
    done
fi

if [[ -n "$FILES_UNCOMMITTED" ]]; then
    echo ""
    echo "FILES MODIFIED (uncommitted):"
    echo "$FILES_UNCOMMITTED" | while read -r line; do
        echo "  $line"
    done
fi

if [[ -n "$DIFF_STATS" ]]; then
    echo ""
    echo "DIFF STATS:"
    echo "$DIFF_STATS" | tail -1 | sed 's/^/  /'
fi

if [[ -z "$FILES_COMMITTED" && -z "$FILES_UNCOMMITTED" && -z "$COMMITS_SINCE" ]]; then
    echo ""
    echo "  (nessuna modifica dal checkpoint)"
fi

echo ""
