#!/bin/bash
set -euo pipefail

# =============================================================================
# drop-lane.sh - Distrugge una lane SENZA mergiare
# Usage: drop-lane.sh [--docs-root <root>] <lane> [--yes]
#
# Auto-detecta i worktrees *-{lane} in WORKTREE_BASE e li distrugge:
#   - git worktree remove --force (perde modifiche uncommitted)
#   - git branch -D feat/{lane}   (perde commit non mergiati)
#   - rimuove profilo terminale Ptyxis associato
#
# SENZA --yes: dry-run. Mostra cosa verrebbe distrutto (worktrees, branch,
#              commit non mergiati, file dirty) ed esce 0. NIENTE viene toccato.
# CON --yes:   esegue la distruzione.
#
# Exit code:
#   0 = ok (dry-run o distruzione completata)
#   1 = errore validazione / worktree non trovato
# =============================================================================

YES=false
LANE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --docs-root) LOOM_DOCS_ROOT="$2"; shift 2 ;;
        --yes) YES=true; shift ;;
        -*) echo "ERROR: Flag sconosciuto: $1"; exit 1 ;;
        *) LANE="$1"; shift ;;
    esac
done

: "${LANE:?Usage: drop-lane.sh [--docs-root <root>] <lane> [--yes]}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"
"${SCRIPT_DIR}/../utils/assert-capability.sh" repo

PROJECT_ROOT="$(lw_find_project_root)"
WORKTREE_BASE="$(dirname "$PROJECT_ROOT")"

# ---------------------------------------------------------------------------
# Auto-detect worktrees per la lane
# ---------------------------------------------------------------------------

declare -a LANE_WORKTREES=()
declare -a LANE_REPOS=()

while IFS= read -r -d '' candidate; do
    wt_name="$(basename "$candidate")"
    if [[ "$wt_name" == *"-${LANE}" ]]; then
        if git -C "$candidate" rev-parse --git-dir >/dev/null 2>&1; then
            LANE_WORKTREES+=("$candidate")
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
# Preview: cosa verrà distrutto
# ---------------------------------------------------------------------------

echo "DROP-LANE lane=${LANE} worktrees=${#LANE_WORKTREES[@]} $(${YES} && echo '[ESECUZIONE]' || echo '[DRY-RUN]')"
echo ""
echo "⚠️  Distruzione SENZA merge — i commit non mergiati e le modifiche uncommitted andranno PERSI."
echo ""

for i in "${!LANE_WORKTREES[@]}"; do
    wt="${LANE_WORKTREES[$i]}"
    repo="${LANE_REPOS[$i]}"
    branch="$(git -C "$wt" branch --show-current 2>/dev/null || echo '(detached)')"

    # Commit non mergiati nel repo base
    unmerged="n/a"
    if [[ -d "$repo" ]] && git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        base_branch="$(git -C "$repo" branch --show-current 2>/dev/null || echo 'main')"
        unmerged="$(git -C "$wt" rev-list --count "${base_branch}..HEAD" 2>/dev/null || echo '?')"
    fi

    # File dirty (uncommitted)
    dirty="$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

    echo "  • $(basename "$wt")"
    echo "      branch:           ${branch}  (verrà cancellato con -D)"
    echo "      commit non mergiati: ${unmerged}"
    echo "      file dirty:        ${dirty}"
    echo "      path:             ${wt}"
done
echo ""

# ---------------------------------------------------------------------------
# Dry-run: stop qui
# ---------------------------------------------------------------------------

if [[ "$YES" != true ]]; then
    echo "DRY-RUN — niente è stato toccato. Rilancia con --yes per distruggere."
    exit 0
fi

# ---------------------------------------------------------------------------
# Esecuzione: distruzione
# ---------------------------------------------------------------------------

for i in "${!LANE_WORKTREES[@]}"; do
    wt="${LANE_WORKTREES[$i]}"
    repo="${LANE_REPOS[$i]}"
    branch="$(git -C "$wt" branch --show-current 2>/dev/null || echo '')"

    echo "-> distruggo: $(basename "$wt")"

    # Profilo Ptyxis (best-effort)
    "${SCRIPT_DIR}/../utils/ptyxis-profile.sh" remove "$wt" || true

    # Rimuovi worktree (force: ignora dirty)
    if [[ -d "$repo" ]]; then
        git -C "$repo" worktree remove "$wt" --force 2>/dev/null || {
            echo "   WARN: worktree remove fallito, provo rm manuale"
            rm -rf "$wt"
            git -C "$repo" worktree prune 2>/dev/null || true
        }
        # Cancella branch (force)
        if [[ -n "$branch" && "$branch" != "(detached)" ]]; then
            git -C "$repo" branch -D "$branch" 2>/dev/null || \
                echo "   WARN: branch ${branch} non cancellato (forse già assente)"
        fi
    else
        echo "   WARN: repo origine ${repo} non trovato, rimuovo solo la folder"
        rm -rf "$wt"
    fi

    echo "-> ✔️ distrutto: $(basename "$wt")"
done

echo ""
echo "-> ✔️ lane '${LANE}' distrutta (${#LANE_WORKTREES[@]} worktree). Nessun merge effettuato."
