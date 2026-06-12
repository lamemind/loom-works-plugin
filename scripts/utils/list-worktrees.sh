#!/bin/bash

# =============================================================================
# list-worktrees.sh - Lista worktree attivi
# Usage: list-worktrees.sh [--filter lane|main|all] [--lane <name>] [project_root]
#
# Mostra worktrees del progetto corrente (o del project_root specificato).
# Per una panoramica multi-project, eseguire da ciascun sub-repo separatamente.
# =============================================================================

FILTER="all"
LANE_FILTER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --filter) FILTER="$2"; shift 2 ;;
        --lane)   LANE_FILTER="$2"; shift 2 ;;
        -*) echo "ERROR: Flag sconosciuto: $1"; exit 1 ;;
        *) break ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

PROJECT_ROOT="${1:-$(lw_find_project_root)}"
PROJECT_NAME="$(basename "$PROJECT_ROOT")"
DOCS_ROOT="$(lw_docs_root)"

if ! git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: ${PROJECT_ROOT} non è un repository git" >&2
    exit 1
fi

echo "==================================================================="
echo "  WORKTREES di ${PROJECT_NAME} — filtro: ${LANE_FILTER:-${FILTER}}"
echo "==================================================================="

git -C "$PROJECT_ROOT" worktree list --porcelain | grep "^worktree" | cut -d' ' -f2 | while read -r wt; do
    WT_NAME=$(basename "$wt")

    # Determina tipo
    if [[ "$wt" == "$PROJECT_ROOT" ]]; then
        TYPE="main"
        LABEL="${WT_NAME}"
        LANE=""
    elif [[ "$WT_NAME" =~ ^${PROJECT_NAME}-(.+)$ ]]; then
        TYPE="lane"
        LANE="${BASH_REMATCH[1]}"
        LABEL="lane=${LANE}"
    else
        TYPE="other"
        LANE=""
        LABEL="$WT_NAME"
    fi

    # Applica filtro --filter
    if [[ "$FILTER" != "all" && "$FILTER" != "$TYPE" ]]; then
        continue
    fi

    # Applica filtro --lane
    if [[ -n "$LANE_FILTER" && "$LANE" != "$LANE_FILTER" ]]; then
        continue
    fi

    if [[ -d "$wt" ]]; then
        WT_BRANCH=$(cd "$wt" && git branch --show-current 2>/dev/null || echo "detached")
        WT_DIRTY=$(cd "$wt" && git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
        WT_COMMIT=$(cd "$wt" && git log -1 --format='%h %s' 2>/dev/null | head -c 60)

        # Task in esecuzione: legge il symlink current-task.md nel worktree
        # (presente solo dove docs/ è branchato → single-project). Risale fino
        # al task file per ID + titolo (dati ricchi downstream verso tasks.md).
        WT_TASK="(none)"
        CT_LINK="${wt}/${DOCS_ROOT}/current-task.md"
        if [[ -L "$CT_LINK" ]]; then
            CT_TARGET=$(readlink "$CT_LINK")
            CT_RESOLVED=$(readlink -f "$CT_LINK" 2>/dev/null || true)
            TASK_ID=""
            TASK_TITLE=""
            if [[ -n "$CT_RESOLVED" && -f "$CT_RESOLVED" ]]; then
                TASK_ID=$(grep -m1 -E '^- \*\*ID\*\*:' "$CT_RESOLVED" 2>/dev/null | grep -oE '[A-Z][0-9]+' | head -1)
                TASK_TITLE=$(grep -m1 -E '^# Task:' "$CT_RESOLVED" 2>/dev/null | sed 's/^# Task:[[:space:]]*//')
            fi
            [[ -z "$TASK_ID" ]] && TASK_ID=$(basename "$CT_TARGET" | grep -oE '[A-Z][0-9]+' | head -1)
            WT_TASK="${TASK_ID:-?}${TASK_TITLE:+ — $TASK_TITLE}"
        fi

        echo ""
        echo "  ${WT_NAME} [${TYPE}]"
        echo "     Label:  ${LABEL}"
        echo "     Branch: ${WT_BRANCH}"
        echo "     Dirty:  ${WT_DIRTY} file"
        echo "     Last:   ${WT_COMMIT}"
        echo "     Task:   ${WT_TASK}"
        echo "     Path:   ${wt}"
    fi
done

echo ""
echo "==================================================================="
