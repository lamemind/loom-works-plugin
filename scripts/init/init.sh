#!/bin/bash

# =============================================================================
# init.sh - Bootstrap minimale struttura loom-works su un progetto
# Usage: init.sh [--force] [--docs-root <name>]
# =============================================================================
#
# Crea (solo se assenti):
#   {docs_root}/tasks.md              (da templates/tasks-skeleton.md)
#   {docs_root}/reference/INDEX.md    (da templates/reference-index-skeleton.md)
#   {docs_root}/tasks/                (dir)
#   {docs_root}/reference/            (dir)
#   .claude/loom-works.initialized    (file sentinel: il progetto è stato inizializzato)
#
# Idempotente: file/dir esistenti NON sono sovrascritti.
# Opzione --force: rigenera tasks.md e INDEX.md anche se presenti (distruttivo).
#
# Env:
#   PROJECT_ROOT (default: $PWD) — root del progetto target
#   CLAUDE_PLUGIN_ROOT           — root del plugin (per trovare i template)
# =============================================================================

set -euo pipefail

FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) FORCE=1; shift ;;
        --docs-root) LOOM_DOCS_ROOT="$2"; shift 2 ;;
        *) break ;;
    esac
done

PROJECT_ROOT="${PROJECT_ROOT:-$PWD}"
DOCS_ROOT="${LOOM_DOCS_ROOT:-docs}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

TEMPLATES="${PLUGIN_ROOT}/templates"

log() { echo "[loom-works:init] $*"; }

create_dir() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        log "dir exists: ${dir#$PROJECT_ROOT/}"
    else
        mkdir -p "$dir"
        log "created dir: ${dir#$PROJECT_ROOT/}"
    fi
}

copy_template() {
    local src="$1"
    local dest="$2"
    local label="${dest#$PROJECT_ROOT/}"

    if [[ -f "$dest" && "$FORCE" -ne 1 ]]; then
        log "file exists (skip): $label"
        return 0
    fi
    if [[ ! -f "$src" ]]; then
        log "ERROR template missing: $src"
        return 1
    fi
    cp "$src" "$dest"
    log "wrote: $label"
}

log "project root: $PROJECT_ROOT"
log "plugin root:  $PLUGIN_ROOT"

create_dir "${PROJECT_ROOT}/${DOCS_ROOT}"
create_dir "${PROJECT_ROOT}/${DOCS_ROOT}/tasks"
create_dir "${PROJECT_ROOT}/${DOCS_ROOT}/reference"

copy_template "${TEMPLATES}/tasks-skeleton.md" "${PROJECT_ROOT}/${DOCS_ROOT}/tasks.md"
copy_template "${TEMPLATES}/reference-index-skeleton.md" "${PROJECT_ROOT}/${DOCS_ROOT}/reference/INDEX.md"

# Sentinel: file dentro .claude/ (creata lazy). Config vera vive in plugin settings.json.
SENTINEL_DIR="${PROJECT_ROOT}/.claude"
SENTINEL="${SENTINEL_DIR}/loom-works.initialized"
if [[ ! -f "$SENTINEL" ]]; then
    mkdir -p "$SENTINEL_DIR"
    date -u +"%Y-%m-%dT%H:%M:%SZ" > "$SENTINEL"
    log "wrote sentinel: .claude/loom-works.initialized"
fi

log "done."
