#!/bin/bash

# =============================================================================
# lib.sh - Helper sourced da altri script loom-works
# Usage: source "${LOOM_WORKS_ROOT}/scripts/utils/lib.sh"
# =============================================================================
#
# Fornisce:
# - Detection project_mode (repo | no-repo) via auto-detect
# - Wrapper git condizionali: noop silenzioso in no-repo
# - Read helper git: ritornano stringa vuota in no-repo
#
# Env letto:
# - PROJECT_ROOT (default: $PWD)
# - LOOM_PROJECT_MODE (override manuale, opzionale)
#
# Config vera vive in plugin settings.json (project level), non nel sentinel.
# =============================================================================

# ---- Project root detection --------------------------------------------------
#
# Sale l'albero a partire da $PWD cercando il sentinel .claude/loom-works.initialized
# (scritto da /loom-works:init). Retrocompat: accetta anche .loom-works/.initialized
# (vecchio formato folder). Se non trovato, fallback git toplevel.
# Final fallback: $PWD. Honor PROJECT_ROOT se già settato esplicitamente.

lw_find_project_root() {
    if [[ -n "${PROJECT_ROOT:-}" ]]; then
        echo "$PROJECT_ROOT"
        return 0
    fi
    local dir="$PWD"
    while [[ "$dir" != "/" && -n "$dir" ]]; do
        if [[ -f "$dir/.claude/loom-works.initialized" || -f "$dir/.loom-works/.initialized" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    local git_root
    git_root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)"
    if [[ -n "$git_root" ]]; then
        echo "$git_root"
        return 0
    fi
    echo "$PWD"
}

# ---- Project mode detection ---------------------------------------------------

lw_project_mode() {
    if [[ -n "${LOOM_PROJECT_MODE:-}" ]]; then
        echo "$LOOM_PROJECT_MODE"
        return 0
    fi
    local root
    root="$(lw_find_project_root)"
    if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "repo"
    else
        echo "no-repo"
    fi
}

lw_is_repo() {
    [[ "$(lw_project_mode)" == "repo" ]]
}

# ---- Docs root ---------------------------------------------------------------

lw_docs_root() {
    echo "${LOOM_DOCS_ROOT:-docs}"
}

# ---- Git wrappers (noop in no-repo) ------------------------------------------

lw_git_add() {
    lw_is_repo || return 0
    git -C "$(lw_find_project_root)" add "$@"
}

lw_git_commit() {
    lw_is_repo || return 0
    git -C "$(lw_find_project_root)" commit -m "$1"
}

# Commit dei soli file attualmente in stage. Exit code parlante:
#   0 = committato
#   1 = commit fallito
#   2 = niente in stage (nessun commit fatto, no-op silenzioso)
lw_git_commit_staged() {
    lw_is_repo || return 2
    local root
    root="$(lw_find_project_root)"
    git -C "$root" diff --cached --quiet && return 2
    git -C "$root" commit -m "$1" || return 1
    return 0
}

lw_git_push() {
    lw_is_repo || return 0
    local branch="${1:-}"
    if [[ -n "$branch" ]]; then
        git -C "$(lw_find_project_root)" push origin "$branch"
    else
        git -C "$(lw_find_project_root)" push
    fi
}

# ---- Git read helpers (empty string in no-repo) ------------------------------

lw_current_branch() {
    lw_is_repo || { echo ""; return 0; }
    git -C "$(lw_find_project_root)" branch --show-current
}

lw_current_sha() {
    lw_is_repo || { echo ""; return 0; }
    git -C "$(lw_find_project_root)" rev-parse --short HEAD
}

lw_git_status_porcelain() {
    lw_is_repo || { echo ""; return 0; }
    git -C "$(lw_find_project_root)" status --porcelain
}

lw_remote_url() {
    lw_is_repo || { echo ""; return 0; }
    git -C "$(lw_find_project_root)" config --get remote.origin.url 2>/dev/null || echo ""
}

# ---- Error helpers -----------------------------------------------------------

die() {
    local msg="${*:-errore}"
    echo "ERROR: $msg" >&2
    local say_sh
    say_sh="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/say.sh"
    if [[ -f "$say_sh" ]]; then
        # shellcheck source=/dev/null
        source "$say_sh" 2>/dev/null && say_auto "errore $msg" 2>/dev/null || true
    fi
    exit 1
}
