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
# Sale l'albero a partire da $PWD cercando il marker .claude/loom-works.json
# (config progetto OBBLIGATORIO, scritto da /loom-works:init). È l'UNICO marker:
# nessun fallback legacy — il vecchio sentinel .initialized non vale più.
# Se non trovato, fallback git toplevel. Final fallback: $PWD.
# Honor PROJECT_ROOT se già settato esplicitamente.

lw_find_project_root() {
    if [[ -n "${PROJECT_ROOT:-}" ]]; then
        echo "$PROJECT_ROOT"
        return 0
    fi
    local dir="$PWD"
    while [[ "$dir" != "/" && -n "$dir" ]]; do
        if [[ -f "$dir/.claude/loom-works.json" ]]; then
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
#
# Precedenza: file config del progetto → LOOM_DOCS_ROOT → "docs".
#
# Il FILE vince sull'env di proposito. `LOOM_DOCS_ROOT` arriva quasi sempre dal
# flag --docs-root che le skill interpolano da `user_config.doc_folder_name`, cioè
# da una preferenza utente GLOBALE, uguale per tutti i progetti. Il campo `docsRoot`
# in .claude/loom-works.json è invece PER-PROGETTO e committato: su un progetto che
# tiene la doc in runtime/ è l'unica fonte che lo sa. Il più specifico batte il più
# generico — stesso principio del layer Config in project-config-architecture.md.
#
# Senza questa precedenza uno script gira sulla cartella sbagliata in silenzio: non
# fallisce, misura zero file, e chi legge l'output crede che la doc sia a posto.

lw_docs_root() {
    local cfg root
    root="$(lw_find_project_root)"
    cfg="${root}/.claude/loom-works.json"
    if [[ -f "$cfg" ]] && command -v jq >/dev/null 2>&1; then
        local from_file
        from_file="$(jq -r '.docsRoot // empty' "$cfg" 2>/dev/null)"
        if [[ -n "$from_file" ]]; then
            echo "$from_file"
            return 0
        fi
    fi
    echo "${LOOM_DOCS_ROOT:-docs}"
}

# ---- Task attiva: cascata di risoluzione -------------------------------------
#
# Contratto di famiglia, gemello di inject-task.sh (hook SessionStart) e della
# statusline. Tre livelli:
#
#   1. arg esplicito                       -> chi invoca ha nominato la task
#   2. $LOOM_TASK                          -> binding di SESSIONE (spawn deck)
#   3. symlink {docs_root}/current-task.md -> binding di WORKTREE (linked mode)
#
# L'arg sta in cima o una sessione gia' vincolata non potrebbe piu' chiedere
# un'altra task. L'env batte il symlink perche' N sessioni parallele nello stesso
# worktree condividono un solo symlink: solo l'env sa quale delle N sei tu.
#
# Stampa tre righe eval-abili (valori %q-quotati, path con spazi al sicuro):
#
#   TASK_ID=T48
#   TASK_FILE=/abs/path/runtime/tasks/T48-slug.md
#   TASK_SRC=arg|env|symlink
#
# TASK_SRC rende la provenienza DICHIARATA invece che silenziosa: chi decide se la
# sessione vale linked (git add -A) o detached-equivalente (stage selettivo) lo
# legge, non lo indovina.
#
# Uso — l'exit code NON sopravvive dentro `eval "$(...)"` (il fallimento resta
# nella command substitution, eval vede una stringa vuota e ritorna 0):
#
#   out="$(lw_resolve_task "$maybe_id")" || exit 1
#   eval "$out"
#
# Exit: 0 = risolta · 1 = nessuna fonte · 2 = id noto ma task file assente
lw_resolve_task() {   # [<task-id>]
    local id="${1:-}" src="" root docs dir link base file
    root="$(lw_find_project_root)"
    docs="$(lw_docs_root)"
    dir="${root}/${docs}/tasks"

    if [[ -n "$id" ]]; then
        src="arg"
    elif [[ -n "${LOOM_TASK:-}" ]]; then
        id="${LOOM_TASK}"
        src="env"
    else
        link="${root}/${docs}/current-task.md"
        if [[ -L "$link" ]]; then
            # il symlink punta a tasks/T48-slug.md: l'ID e' il primo token
            base="$(basename "$(readlink "$link")" .md)"
            id="${base%%-*}"
            src="symlink"
        fi
    fi

    if [[ -z "$id" ]]; then
        echo "ERROR: nessuna task attiva — arg, \$LOOM_TASK e symlink ${docs}/current-task.md tutti assenti" >&2
        return 1
    fi

    file="$(ls "${dir}/${id}"-*.md 2>/dev/null | head -1)"
    if [[ -z "$file" || ! -f "$file" ]]; then
        echo "ERROR: task file non trovato per ${id} in ${dir} (fonte: ${src})" >&2
        return 2
    fi

    printf 'TASK_ID=%q\nTASK_FILE=%q\nTASK_SRC=%q\n' "$id" "$file" "$src"
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

# ---- Folder purge helpers ----------------------------------------------------

# Files that SURVIVE `git rm -rf <folder>`: untracked + ignored. `git rm` only
# touches TRACKED files, so a `.gitignore` inside the folder (or a root-level rule
# matching its content) leaves those files orphaned on disk after the purge. Lists
# them one-per-line, repo-relative; empty when the folder purges clean. <folder>
# is repo-relative. Note: `ls-files -o` WITHOUT `--exclude-standard` = untracked
# AND ignored — exactly the leftover set.
lw_folder_survivors() {  # <rel_folder>
    lw_is_repo || { echo ""; return 0; }
    git -C "$(lw_find_project_root)" ls-files -o -- "$1" 2>/dev/null || true
}

# Guarded recursive delete for leftover ignored/untracked files that `git rm`
# cannot remove. Refuses anything not STRICTLY inside the canonicalized project
# root: no '/', no the root itself, no path outside it, no empty/unresolvable.
# Absolute-path only — "no disastri".
lw_safe_rmrf() {  # <path>
    local target root
    target="$(realpath -m -- "$1" 2>/dev/null || true)"
    root="$(realpath -m -- "$(lw_find_project_root)" 2>/dev/null || true)"
    if [[ -z "$target" || -z "$root" ]]; then
        echo "ERROR: lw_safe_rmrf: path non risolvibile: $1" >&2; return 1
    fi
    if [[ "$target" == "/" || "$target" == "$root" ]]; then
        echo "ERROR: lw_safe_rmrf: rifiuto rm di '/' o project root: $target" >&2; return 1
    fi
    case "$target" in
        "$root"/?*) : ;;   # deve stare STRETTAMENTE dentro il project root
        *) echo "ERROR: lw_safe_rmrf: path fuori dal project root ($root): $target" >&2; return 1 ;;
    esac
    rm -rf -- "$target"
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
