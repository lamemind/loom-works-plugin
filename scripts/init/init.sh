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
#   {docs_root}/inbox/                (dir, vuota e senza .gitkeep)
#   .claude/settings.json             (solo la regola di permesso sulla cache plugin)
#
# L'inbox nasce vuota e non si versiona: ogni lettore ne tollera già l'assenza —
# la ricrea il primo checkpoint che ci scrive.
#
# NB: l'identità di progetto .claude/loom-works.json (che è anche il marker di
# project-root per lib.sh) è creata dallo step 1b della skill init (bootstrap
# interattivo), non da questo script.
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

# =============================================================================
# Regola di permesso sulla cache del plugin
# =============================================================================
# Gli agent doc (doc-router, doc-writer, doc-auditor, doc-grouper, doc-verifier)
# aprono da sé i propri contratti sotto ${CLAUDE_PLUGIN_ROOT}/docs/. Quel path sta
# nella cache del plugin, cioè FUORI dalla working directory del progetto: senza una
# regola che lo copra la Read cade sotto approvazione, e l'agent NON si ferma — chiude
# con un verdetto che si legge come legittimo, avendo giudicato senza il contratto.
#
# IL PATH NON DEVE PORTARE IL NUMERO DI VERSIONE. Una regola concessa a mano da un
# «non chiedere più» nasce version-pinned (…/loom-works/7.1.2/**) e muore al primo
# bump, riportando il guasto dopo che sembrava risolto. Si scrive quindi sul segmento
# stabile, e la tilde resta letterale: Claude Code la espande, così la regola non porta
# l'home di chi ha lanciato init e resta valida per ogni utente del repo.
ensure_cache_permission() {
    local settings="${PROJECT_ROOT}/.claude/settings.json"
    local regola

    # Derivata dal plugin root vivo, non cablata: se il marketplace o il nome del
    # plugin cambiano, la regola li segue. Fuori dalla cache (esecuzione dal repo
    # sorgente) il path derivato non avrebbe senso → si usa quello canonico.
    if [[ "$PLUGIN_ROOT" == */plugins/cache/* ]]; then
        regola="Read($(dirname "${PLUGIN_ROOT#"$HOME"}" | sed 's|^|~|')/**)"
    else
        regola='Read(~/.claude/plugins/cache/lamemind/loom-works/**)'
    fi

    if ! command -v jq > /dev/null; then
        log "WARN jq assente: aggiungi a mano in .claude/settings.json → $regola"
        return 0
    fi

    mkdir -p "${PROJECT_ROOT}/.claude"
    [[ -f "$settings" ]] || echo '{}' > "$settings"

    if jq -e --arg r "$regola" '.permissions.allow // [] | index($r)' "$settings" > /dev/null; then
        log "permission exists (skip): $regola"
        return 0
    fi

    local tmp="${settings}.tmp.$$"
    if jq --arg r "$regola" '.permissions.allow = ((.permissions.allow // []) + [$r])' \
         "$settings" > "$tmp"; then
        mv "$tmp" "$settings"
        log "permission added: $regola"
    else
        rm -f "$tmp"
        log "WARN .claude/settings.json non parsabile: aggiungi a mano → $regola"
    fi
}

log "project root: $PROJECT_ROOT"
log "plugin root:  $PLUGIN_ROOT"

create_dir "${PROJECT_ROOT}/${DOCS_ROOT}"
create_dir "${PROJECT_ROOT}/${DOCS_ROOT}/tasks"
create_dir "${PROJECT_ROOT}/${DOCS_ROOT}/reference"
create_dir "${PROJECT_ROOT}/${DOCS_ROOT}/inbox"

copy_template "${TEMPLATES}/tasks-skeleton.md" "${PROJECT_ROOT}/${DOCS_ROOT}/tasks.md"
copy_template "${TEMPLATES}/reference-index-skeleton.md" "${PROJECT_ROOT}/${DOCS_ROOT}/reference/INDEX.md"

ensure_cache_permission

# Identità di progetto + marker root: .claude/loom-works.json, creato dallo
# step 1b della skill (bootstrap interattivo owner/emoji/surfaces). Non qui.

log "done."
