#!/bin/bash
set -euo pipefail

# =============================================================================
# init-worktree.sh - Inizializzazione comune per worktree lane
# Usage: init-worktree.sh <worktree-path> [origin-repo-path]
#
# Operazioni:
#   1. Copia .claude/settings.local.json da origin → worktree
#      (Claude Code eredita permessi e hook del progetto principale)
#   2. Se la cartella parent è un git repo (es. Maven parent),
#      aggiunge il worktree a .git/info/exclude per evitare untracked noise
#   3. Chiama setup-worktree.sh se presente nel progetto (hook project-specific)
# =============================================================================

WORKTREE_PATH="${1:?Usage: init-worktree.sh <worktree-path> [origin-repo-path]}"
ORIGIN_PATH="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Determina origin: argomento esplicito, oppure risali dal worktree
if [[ -z "$ORIGIN_PATH" ]]; then
    # In un worktree git, git rev-parse --git-common-dir punta alla .git del repo principale
    COMMON_GIT=$(git -C "$WORKTREE_PATH" rev-parse --git-common-dir 2>/dev/null || echo "")
    if [[ -n "$COMMON_GIT" && "$COMMON_GIT" != ".git" ]]; then
        ORIGIN_PATH="$(dirname "$COMMON_GIT")"
    fi
fi

WT_NAME="$(basename "$WORKTREE_PATH")"

# ---------------------------------------------------------------------------
# 1. Copia .claude/settings.local.json
# ---------------------------------------------------------------------------

if [[ -n "$ORIGIN_PATH" && -f "${ORIGIN_PATH}/.claude/settings.local.json" ]]; then
    mkdir -p "${WORKTREE_PATH}/.claude"
    cp "${ORIGIN_PATH}/.claude/settings.local.json" "${WORKTREE_PATH}/.claude/settings.local.json"
    echo "-> settings.local.json copiato nel worktree"
else
    echo "-> SKIP settings.local.json (non trovato in origin)"
fi

# ---------------------------------------------------------------------------
# 2. Exclude parent git repo (evita untracked noise in repos contenitori)
# ---------------------------------------------------------------------------

PARENT_DIR="$(dirname "$WORKTREE_PATH")"
if git -C "$PARENT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    PARENT_ROOT="$(git -C "$PARENT_DIR" rev-parse --show-toplevel 2>/dev/null)"
    if [[ -n "$PARENT_ROOT" && "$PARENT_ROOT" != "$(git -C "$WORKTREE_PATH" rev-parse --show-toplevel 2>/dev/null)" ]]; then
        EXCLUDE_FILE="${PARENT_ROOT}/.git/info/exclude"
        mkdir -p "$(dirname "$EXCLUDE_FILE")"
        if ! grep -qF "/${WT_NAME}" "$EXCLUDE_FILE" 2>/dev/null; then
            echo "/${WT_NAME}" >> "$EXCLUDE_FILE"
            echo "-> Aggiunto /${WT_NAME} a ${PARENT_ROOT}/.git/info/exclude"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# 3. Hook project-specific: setup-worktree.sh
# ---------------------------------------------------------------------------

SETUP_HOOK=""
if [[ -n "$ORIGIN_PATH" && -x "${ORIGIN_PATH}/scripts/utils/setup-worktree.sh" ]]; then
    SETUP_HOOK="${ORIGIN_PATH}/scripts/utils/setup-worktree.sh"
elif [[ -x "${SCRIPT_DIR}/setup-worktree.sh" ]]; then
    SETUP_HOOK="${SCRIPT_DIR}/setup-worktree.sh"
fi

if [[ -n "$SETUP_HOOK" ]]; then
    # Estrai lane name dal worktree name (rimuovi prefisso repo-)
    LANE=""
    if [[ -n "$ORIGIN_PATH" ]]; then
        REPO_NAME="$(basename "$ORIGIN_PATH")"
        [[ "$WT_NAME" == "${REPO_NAME}-"* ]] && LANE="${WT_NAME#${REPO_NAME}-}"
    fi
    "$SETUP_HOOK" "$WORKTREE_PATH" "${LANE:-unknown}"
fi

echo "-> ✔️ init-worktree completato: ${WORKTREE_PATH}"
