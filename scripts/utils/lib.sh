#!/bin/bash

# =============================================================================
# lib.sh - Helper sourced da altri script loom-works
# Usage: source "${LOOM_WORKS_ROOT}/scripts/utils/lib.sh"
# =============================================================================
#
# Fornisce:
# - Wrapper git e read helper
# - Detection del remote: l'unica capability davvero variabile
#
# Env letto:
# - PROJECT_ROOT (default: $PWD)
#
# Modello: REPO SEMPRE, REMOTE OPZIONALE. Un progetto loom-works e' sempre un
# repo git — se non lo e', `git init` e' un prerequisito, non un modo alternativo
# di funzionare. Cio' che manca davvero in natura e' il REMOTE: si lavora in
# locale, si committa, e non c'e' dove pushare. Il gate sta quindi solo sul push.
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

# ---- Remote detection ---------------------------------------------------------
#
# La sola capability variabile del modello. Gate su `origin` e non sulla presenza
# generica di un remote: tutto il resto della lib parla origin (il push con branch
# esplicito), quindi un remote di altro nome non renderebbe comunque pushabile il
# branch.

lw_has_remote() {
    git -C "$(lw_find_project_root)" remote get-url origin >/dev/null 2>&1
}

# ---- Docs root ---------------------------------------------------------------
#
# Precedenza: file config del progetto → LOOM_DOCS_ROOT → "docs".
#
# FONTE UNICA = il campo `docsRoot` di .claude/loom-works.json. E' PER-PROGETTO e
# committato: su un progetto che tiene la doc in runtime/ e' l'unica cosa che lo sa,
# e viaggia col repo. Il canale che c'era prima — il userConfig globale
# `doc_folder_name`, interpolato dalle skill nel flag --docs-root — e' stato rimosso
# (plugin v3.0.0): una preferenza utente vale per TUTTI i progetti, quindi non puo'
# descriverne uno non-default. Non era teoria: interpolava il valore globale `docs`
# su un progetto `runtime` e gli script giravano sulla cartella sbagliata in
# silenzio — non fallivano, misuravano zero file, e chi leggeva l'output credeva
# che la doc fosse a posto.
#
# `LOOM_DOCS_ROOT` sopravvive sotto il file come escape hatch (test, fixture senza
# file config). Resta SOTTO di proposito: un env sfuggito da una sessione o da un
# altro progetto non deve poter dirottare uno script su un progetto che ha gia'
# dichiarato la propria docs-root. Il piu' specifico batte il piu' generico —
# stesso principio del layer Config in project-config-architecture.md.
#
# Chi non puo' sourcare bash (il markdown delle skill) usa il wrapper CLI
# scripts/utils/docs-root.sh, gemello di resolve-task.sh.

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

# ---- Baseline del diff di checkpoint -----------------------------------------
#
# Da dove parte la finestra <base>..HEAD che checkpoint-task-analyze.sh mostra.
# NON e' un campo scritto nel task file: quello era un chicken-egg — il SHA si
# conosce solo DOPO il commit, ma scriverlo dentro il file appena committato lo
# modifica di nuovo, quindi il sed girava post-commit e lasciava il working tree
# sporco. Qui il baseline si deriva dalla history, ancorato al Progress Log:
#
#   - zero '### Avanzamento'  -> commit di CREAZIONE del task file
#   - >=1                     -> commit che ha INTRODOTTO l'ultimo header
#
# Il file va letto da HEAD, non dal working tree: al checkpoint la skill scrive
# '### Avanzamento N' PRIMA del commit, quindi sul working tree il pickaxe
# cercherebbe in history un header non ancora committato e uscirebbe vuoto.
#
# L'ancoraggio all'avanzamento rende il baseline il perimetro di cio' che si sta
# consolidando: un commit che sweep-a il task file per altro (una checkbox, le
# Decisions di preflight-task) non lo sposta piu'. In piu' l'hash esce sempre
# vivo dalla history, mentre un SHA storato puo' danglare dopo un rebase.
#
# Task file mai committato -> errore, non degradazione: una `git log` vuota
# passata a `git diff` significa "diff sull'intera history", cioe' una finestra
# falsa che si presenta come normale.
#
# Exit: 0 = SHA su stdout · 1 = non derivabile (messaggio su stderr)
lw_task_baseline_sha() {   # <task-file>
    local task_file="${1:?lw_task_baseline_sha: <task-file> richiesto}"
    local root top abs rel last sha
    root="$(lw_find_project_root)"
    top="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)"
    if [[ -z "$top" ]]; then
        echo "ERROR: baseline non derivabile: ${root} non e' un repo git" >&2
        return 1
    fi
    abs="$(realpath -m -- "$task_file" 2>/dev/null || true)"
    rel="${abs#"${top}/"}"

    if ! git -C "$top" cat-file -e "HEAD:${rel}" 2>/dev/null; then
        echo "ERROR: task file mai committato: ${rel}" >&2
        echo "       Il baseline del diff si deriva dalla history: committa il task file, poi rilancia." >&2
        return 1
    fi

    # "Ultimo" = N piu' alto, NON l'ultimo in ordine di file: il Progress Log si
    # trova scritto in entrambi i versi nel corpus (append in coda, oppure entry
    # nuova in testa) e un `tail -1` sul secondo caso prende il piu' VECCHIO —
    # baseline troppo indietro, finestra di diff che ingloba i checkpoint gia'
    # consolidati, senza nessun segnale. Il numero incrementale e' l'unico
    # ordinamento che non dipende da come la entry e' stata inserita.
    #
    # Poi pickaxe sull'header intero: -S conta le occorrenze, quindi regge anche
    # due avanzamenti con lo stesso testo (il secondo cambia comunque il conteggio).
    last="$(git -C "$top" show "HEAD:${rel}" \
            | grep -E '^### Avanzamento[[:space:]]+[0-9]+' \
            | sort -k3,3n | tail -1)"
    if [[ -n "$last" ]]; then
        sha="$(git -C "$top" log -S"$last" -1 --format=%H -- "$rel")"
    fi

    # Nessun avanzamento (o header legacy fuori formato): la finestra parte dalla
    # nascita della task — larga, mai falsa. Non e' un'anomalia da segnalare.
    if [[ -z "$sha" ]]; then
        sha="$(git -C "$top" log --diff-filter=A -1 --format=%H -- "$rel")"
    fi

    if [[ -z "$sha" ]]; then
        echo "ERROR: baseline non derivabile per ${rel}: nessun commit di creazione in history" >&2
        return 1
    fi
    printf '%s\n' "$sha"
}

# ---- Git wrappers -------------------------------------------------------------

lw_git_add() {
    git -C "$(lw_find_project_root)" add "$@"
}

lw_git_commit() {
    git -C "$(lw_find_project_root)" commit -m "$1"
}

# Commit dei soli file attualmente in stage. Exit code parlante:
#   0 = committato
#   1 = commit fallito
#   2 = niente in stage (nessun commit fatto, no-op silenzioso)
lw_git_commit_staged() {
    local root
    root="$(lw_find_project_root)"
    git -C "$root" diff --cached --quiet && return 2
    git -C "$root" commit -m "$1" || return 1
    return 0
}

# Senza `origin` non fallisce: avvisa su stderr ed esce 0, cosi' la skill chiamante
# prosegue invece di rompersi a meta'. Il warning NON e' cosmetico — e' l'unica
# differenza percepibile fra "pushato" e "resta locale". Un no-op muto lascerebbe
# credere che il lavoro sia remoto, e ogni skill task-level chiude con un push.
lw_git_push() {
    if ! lw_has_remote; then
        echo "WARNING: nessun remote 'origin' — commit locali, niente push." >&2
        return 0
    fi
    local branch="${1:-}"
    if [[ -n "$branch" ]]; then
        git -C "$(lw_find_project_root)" push origin "$branch"
    else
        git -C "$(lw_find_project_root)" push
    fi
}

# ---- Git read helpers ---------------------------------------------------------

lw_current_branch() {
    git -C "$(lw_find_project_root)" branch --show-current
}

lw_current_sha() {
    git -C "$(lw_find_project_root)" rev-parse --short HEAD
}

lw_git_status_porcelain() {
    git -C "$(lw_find_project_root)" status --porcelain
}

# ---- Folder purge helpers ----------------------------------------------------

# Files that SURVIVE `git rm -rf <folder>`: untracked + ignored. `git rm` only
# touches TRACKED files, so a `.gitignore` inside the folder (or a root-level rule
# matching its content) leaves those files orphaned on disk after the purge. Lists
# them one-per-line, repo-relative; empty when the folder purges clean. <folder>
# is repo-relative. Note: `ls-files -o` WITHOUT `--exclude-standard` = untracked
# AND ignored — exactly the leftover set.
lw_folder_survivors() {  # <rel_folder>
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
