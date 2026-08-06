#!/bin/bash

# =============================================================================
# checkpoint-task-commit.sh - Commit e push per checkpoint-task
# Usage: checkpoint-task-commit.sh [--task <id>] [--no-add] [--doc-message "<msg>"] "commit message"
# Env:   PROJECT_ROOT (default: $PWD)
#
# Doppio commit: i file doc-nozione (sotto <docs-root>/ ma fuori da tasks.md e
# tasks/) finiscono in un commit separato "docs(...)". Codice + task tracking
# (task file, tasks.md) restano nel commit "checkpoint(...)". Se non ci sono
# file doc-nozione il comportamento resta a commit singolo.
# =============================================================================

NO_ADD=0
TASK_ID_ARG=""
DOC_MESSAGE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --docs-root) LOOM_DOCS_ROOT="$2"; shift 2 ;;
        --task) TASK_ID_ARG="$2"; shift 2 ;;
        --no-add) NO_ADD=1; shift ;;
        --doc-message) DOC_MESSAGE="$2"; shift 2 ;;
        *) break ;;
    esac
done

COMMIT_MESSAGE="${1:?Usage: checkpoint-task-commit.sh [--task <id>] [--no-add] \"commit message\"}"

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

# $LOOM_TASK = N sessioni parallele sullo stesso worktree, una task ciascuna. Li'
# `git add -A` rastrella dentro questo commit i file su cui stanno lavorando le
# altre — in silenzio, senza errore, e il danno si scopre a push fatto. Lo stage
# selettivo diventa quindi obbligatorio a prescindere da cosa ha passato il
# chiamante: peggio che possa succedere ora e' un "niente in stage", visibile.
if [[ "$TASK_SRC" == "env" && $NO_ADD -eq 0 ]]; then
    NO_ADD=1
    echo "-> binding via \$LOOM_TASK=${TASK_ID}: forzato --no-add (stage selettivo, il worktree puo' ospitare altre sessioni)"
fi

CURRENT_BRANCH=$(lw_current_branch)
CURRENT_SHA=$(lw_current_sha)

# Normalizza drift Progress: il modello a volte chiude la task con "✔️ 100%"
# invece di "✔️ Done" (idioma percentuale ereditato da start-task). Replace secco
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

if [[ $NO_ADD -eq 0 ]]; then
    lw_git_add -A
elif [[ -n "$TASK_FILE" && -f "$TASK_FILE" ]]; then
    # --no-add: lo stage l'ha fatto il chiamante PRIMA della normalizzazione
    # Progress qui sopra -> senza questo add la timbratura "Done at <data>" resta
    # fuori dall'index e il working tree resta dirty per sempre (il sed e' ancorato
    # a "Done$", non ri-scatta ai checkpoint successivi).
    git -C "$PROJECT_ROOT" add -- "$TASK_FILE"
fi

# --- Partizione file staged: doc-nozione vs codice+tracking ------------------
# Doc-nozione = sotto <docs-root>/ ma NON tasks.md e NON tasks/ (quelli sono
# tracking, restano col codice nel commit 1).
DOCS_ROOT="$(lw_docs_root)"
DOC_FILES=()
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if [[ "$f" == "${DOCS_ROOT}/"* \
          && "$f" != "${DOCS_ROOT}/tasks.md" \
          && "$f" != "${DOCS_ROOT}/tasks/"* ]]; then
        DOC_FILES+=("$f")
    fi
done < <(git -C "$PROJECT_ROOT" diff --cached --name-only)

# Sgancia i file doc-nozione dallo stage: andranno nel commit 2
if [[ ${#DOC_FILES[@]} -gt 0 ]]; then
    git -C "$PROJECT_ROOT" reset -q HEAD -- "${DOC_FILES[@]}" 2>/dev/null
fi

# --- Commit 1: codice + tracking (task file, tasks.md) -----------------------
COMMIT1_DONE=0
lw_git_commit_staged "$COMMIT_MESSAGE"
case $? in
    0) COMMIT1_SHA=$(lw_current_sha); COMMIT1_DONE=1 ;;
    2) echo "-> nessun file codice/tracking da committare" ;;
    *) echo "ERROR: Commit (codice+tracking) fallito" >&2; exit 1 ;;
esac

# --- Commit 2: doc-nozione (reference/*.md, overview.md, ...) -----------------
COMMIT2_DONE=0
if [[ ${#DOC_FILES[@]} -gt 0 ]]; then
    DOC_MESSAGE="${DOC_MESSAGE:-docs(${TASK_ID:-task}): capture nozioni documentali}"
    git -C "$PROJECT_ROOT" add -- "${DOC_FILES[@]}"
    lw_git_commit_staged "$DOC_MESSAGE"
    case $? in
        0) COMMIT2_SHA=$(lw_current_sha); COMMIT2_DONE=1 ;;
        2) echo "-> nessun file doc-nozione in stage (skip commit doc)" ;;
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
    echo "-> commit 1 (codice+tracking): ${COMMIT1_SHA}"
fi
if [[ $COMMIT2_DONE -eq 1 ]]; then
    echo "-> commit 2 (doc-nozione, ${#DOC_FILES[@]} file): ${COMMIT2_SHA}"
fi
