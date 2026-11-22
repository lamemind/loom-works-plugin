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
#   .gitignore                        (solo la riga .claude/loom/headless/, se git
#                                      non la ignora già; fuori da git: niente)
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
    # Il modo della copia lo fissa init, non il sorgente: un file creato da `cp`
    # eredita i bit del template, e un template finito eseguibile in git
    # (succede: un markdown 100755 non lo segnala nessuno) farebbe nascere
    # eseguibili tasks.md e INDEX.md di ogni progetto inizializzato. Il chmod
    # copre anche --force su un file già esistente, dove `cp` tiene il modo di dest.
    cp "$src" "$dest"
    chmod 644 "$dest"
    log "wrote: $label"
}

# =============================================================================
# Regola di permesso sulla cache del plugin
# =============================================================================
# Gli agent del sistema doc aprono da sé i propri contratti sotto
# ${CLAUDE_PLUGIN_ROOT}/docs/. Quel path sta
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

# =============================================================================
# Regola .gitignore sullo stato dei turni headless
# =============================================================================
# `loom-deck-headless` scrive stato ed esito di ogni turno `claude -p` sotto
# .claude/loom/headless/ del progetto. È stato macchina-locale: senza una regola
# che lo copra, il primo `checkpoint-task` linked (`git add -A`) lo committa.
#
# Il controllo è `git check-ignore` sul path, non un grep nel .gitignore: una
# regola più larga già presente (`.claude/loom/`, `.claude/`) copre la cartella,
# e aggiungerne una seconda sarebbe rumore. Il path non deve esistere: git
# confronta il path con le regole. L'excludesFile globale è spento apposta: una
# regola di questa macchina non copre chi clona il repo su un'altra.
ensure_gitignore_headless() {
    local regola='.claude/loom/headless/'
    local gitignore="${PROJECT_ROOT}/.gitignore"

    if ! git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        log "fuori da git (skip): .gitignore → $regola"
        return 0
    fi
    if git -C "$PROJECT_ROOT" -c core.excludesFile=/dev/null \
         check-ignore -q -- "${regola}stato" 2> /dev/null; then
        log "gitignore covers (skip): $regola"
        return 0
    fi

    # Un .gitignore senza newline finale incollerebbe la regola all'ultima riga.
    if [[ -s "$gitignore" && -n "$(tail -c1 "$gitignore")" ]]; then
        echo >> "$gitignore"
    fi
    echo "$regola" >> "$gitignore"
    log "gitignore added: $regola"
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
ensure_gitignore_headless

# Identità di progetto + marker root: .claude/loom-works.json, creato dallo
# step 1b della skill (bootstrap interattivo owner/emoji/surfaces). Non qui.

log "done."
