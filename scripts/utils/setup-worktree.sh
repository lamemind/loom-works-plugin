#!/bin/bash

# =============================================================================
# setup-worktree.sh - Hook post-creazione worktree (customizzazione progetto)
# Usage: setup-worktree.sh <worktree-path> <lane>
#
# Template hook. Copia nel progetto utente e personalizza con setup progetto-specifico:
#   - npm install / yarn
#   - Porte dinamiche per test paralleli
#   - Config locali
#   - Qualsiasi altra inizializzazione project-specific
# =============================================================================

WORKTREE_PATH="${1:?Usage: setup-worktree.sh <worktree-path> <lane>}"
LANE="${2:?Lane name required}"

# Questo file è un template: di default è un noop.
# Rimpiazza con la logica di setup del tuo progetto.
echo "  OK setup-worktree noop per lane=${LANE} path=${WORKTREE_PATH}"
