#!/bin/bash

# =============================================================================
# checkpoint-task-commit.sh - Commit e push per checkpoint-task
# Usage: checkpoint-task-commit.sh [--task <id>] [--doc-message "<msg>"] "commit message" -- <path>...
# Env:   PROJECT_ROOT (default: $PWD)
#
# Doppio commit: i file doc-nozione (sotto <docs-root>/ ma fuori da tasks.md e
# tasks/) finiscono in un commit separato "docs(...)". Codice + task tracking
# (task file, tasks.md) restano nel commit "checkpoint(...)". Se non ci sono
# file doc-nozione il comportamento resta a commit singolo.
#
# Perimetro del commit: la pathspec dopo `--`, obbligatoria. Entrano solo quei
# path piu' il task file. Il worktree non appartiene a una task: ospita N sessioni,
# ognuna sulla sua, e l'indice tiene anche lo stage delle altre. Lo script non
# puo' distinguere il suo dal loro, quindi l'unica fonte della lista e' il
# chiamante. Senza pathspec esce 1 prima di toccare qualunque file: nessun
# `git add -A`, nessun commit.
#
# Ogni commit porta la propria pathspec (lw_git_add_n_commit): cio' che era in
# stage prima e fuori perimetro resta in stage, non entra.
# =============================================================================

TASK_ID_ARG=""
DOC_MESSAGE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --docs-root) LOOM_DOCS_ROOT="$2"; shift 2 ;;
        --task) TASK_ID_ARG="$2"; shift 2 ;;
        --doc-message) DOC_MESSAGE="$2"; shift 2 ;;
        *) break ;;
    esac
done

COMMIT_MESSAGE="${1:?Usage: checkpoint-task-commit.sh [--task <id>] [--doc-message \"<msg>\"] \"commit message\" -- <path>...}"
shift

SCOPE_SPEC=()
if [[ "${1:-}" == "--" ]]; then
    shift
    SCOPE_SPEC=("$@")
elif [[ $# -gt 0 ]]; then
    echo "ERROR: argomenti dopo il messaggio: la pathspec va introdotta da '--'" >&2
    exit 1
fi

PROJECT_ROOT="${PROJECT_ROOT:-$PWD}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"

TASK_FILE=""
TASK_ID=""
TASK_SRC=""

if RESOLVED="$(lw_resolve_task "$TASK_ID_ARG")"; then
    eval "$RESOLVED"
elif [[ -n "$TASK_ID_ARG" ]]; then
    # Un id chiesto esplicitamente e non risolvibile e' un errore duro: chi lo ha
    # passato sa quale task vuole, committare "quella sbagliata ma qualcosa" sarebbe
    # peggio del fallimento. Senza arg si prosegue: il commit del codice non deve
    # dipendere dall'esistenza di un binding (lw_resolve_task ha gia' loggato perche').
    exit 1
fi

# Senza pathspec l'unico perimetro conoscibile sarebbe "tutto" (git add -A), che
# rastrellerebbe nel commit il lavoro delle altre sessioni sullo stesso worktree.
if [[ ${#SCOPE_SPEC[@]} -eq 0 ]]; then
    echo "ERROR: pathspec assente. Il worktree ospita altre sessioni e lo script non sa quali file sono tuoi: passali dopo '--'." >&2
    echo "       es: checkpoint-task-commit.sh --task ${TASK_ID:-Txx} \"msg\" -- src/a.ts src/b.ts" >&2
    exit 1
fi

CURRENT_BRANCH=$(lw_current_branch)
CURRENT_SHA=$(lw_current_sha)

# Normalizza drift Progress: il modello a volte chiude la task con "✔️ 100%"
# invece di "✔️ Done" (idioma percentuale del campo Progress). Replace secco
# prima del commit: file committato corretto + gate TASK_DONE (più sotto) matcha.
if [[ -n "$TASK_FILE" && -f "$TASK_FILE" ]]; then
    sed -i '0,/^- \*\*Progress\*\*:/s|^\(- \*\*Progress\*\*:\) ✔️ 100%|\1 ✔️ Done|' "$TASK_FILE"
    DONE_DATE=$(date +%Y-%m-%d)
    sed -i '0,/^- \*\*Progress\*\*:/s|^\(- \*\*Progress\*\*:\) ✔️ Done$|\1 ✔️ Done at '"${DONE_DATE}"'|' "$TASK_FILE"
fi

STATUS=$(lw_git_status_porcelain)

if [[ -z "$STATUS" ]]; then
    echo "-> no changes to commit (SHA: ${CURRENT_SHA})"
    exit 0
fi

cd "$PROJECT_ROOT" || exit 1

# --- Perimetro: lista di path root-relative, deduplicata -----------------------
declare -A SEEN=()
SCOPE=()
add_scope() {  # <path>
    local p="$1"
    [[ -z "$p" ]] && return 0
    if [[ "$p" == /* ]]; then
        p="$(realpath -m --relative-to="$PROJECT_ROOT" "$p")"
    fi
    p="${p#./}"
    [[ -n "${SEEN[$p]:-}" ]] && return 0
    SEEN["$p"]=1
    SCOPE+=("$p")
}

for p in "${SCOPE_SPEC[@]}"; do add_scope "$p"; done
# Il task file entra sempre: porta la timbratura Done at e i marker Doc Impact,
# e il chiamante non deve ricordarsi di elencarlo.
if [[ -n "$TASK_FILE" && -f "$TASK_FILE" ]]; then
    add_scope "$TASK_FILE"
fi
echo "-> perimetro dichiarato: ${#SCOPE[@]} path (l'indice altrui resta in stage)"

# --- Partizione: doc-nozione vs codice+tracking --------------------------------
# Doc-nozione = sotto <docs-root>/ ma NON tasks.md e NON tasks/ (quelli sono
# tracking, restano col codice nel commit 1).
DOCS_ROOT="$(lw_docs_root)"
DOC_FILES=()
CODE_FILES=()
for f in "${SCOPE[@]}"; do
    if [[ "$f" == "${DOCS_ROOT}/"* \
          && "$f" != "${DOCS_ROOT}/tasks.md" \
          && "$f" != "${DOCS_ROOT}/tasks/"* ]]; then
        DOC_FILES+=("$f")
    else
        CODE_FILES+=("$f")
    fi
done

# --- Commit 1: codice + tracking (task file, tasks.md) -----------------------
COMMIT1_DONE=0
if [[ ${#CODE_FILES[@]} -gt 0 ]]; then
    lw_git_add_n_commit "$COMMIT_MESSAGE" "${CODE_FILES[@]}"
    case $? in
        0) COMMIT1_SHA=$(lw_current_sha); COMMIT1_DONE=1 ;;
        2) echo "-> nessuna modifica sui file codice/tracking" ;;
        *) echo "ERROR: Commit (codice+tracking) fallito" >&2; exit 1 ;;
    esac
else
    echo "-> nessun file codice/tracking nel perimetro"
fi

# --- Commit 2: doc-nozione (reference/*.md, overview.md, ...) -----------------
COMMIT2_DONE=0
if [[ ${#DOC_FILES[@]} -gt 0 ]]; then
    DOC_MESSAGE="${DOC_MESSAGE:-docs(${TASK_ID:-task}): capture nozioni documentali}"
    lw_git_add_n_commit "$DOC_MESSAGE" "${DOC_FILES[@]}"
    case $? in
        0) COMMIT2_SHA=$(lw_current_sha); COMMIT2_DONE=1 ;;
        2) echo "-> nessuna modifica sui file doc-nozione (skip commit doc)" ;;
        *) echo "ERROR: Commit (doc-nozione) fallito" >&2; exit 1 ;;
    esac
fi

if [[ $COMMIT1_DONE -eq 0 && $COMMIT2_DONE -eq 0 ]]; then
    echo "-> nothing committed"
    exit 0
fi

if ! lw_git_push "$CURRENT_BRANCH"; then
    echo "ERROR: Push fallito" >&2
    exit 1
fi

if [[ $COMMIT1_DONE -eq 1 ]]; then
    echo "-> commit 1 (codice+tracking, ${#CODE_FILES[@]} path): ${COMMIT1_SHA}"
fi
if [[ $COMMIT2_DONE -eq 1 ]]; then
    echo "-> commit 2 (doc-nozione, ${#DOC_FILES[@]} path): ${COMMIT2_SHA}"
fi
