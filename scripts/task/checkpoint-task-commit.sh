#!/bin/bash

# =============================================================================
# checkpoint-task-commit.sh - Commit e push per checkpoint-task
# Usage: checkpoint-task-commit.sh [--mode <repo|no-repo>] [--task <id>] [--no-add] [--doc-message "<msg>"] "commit message"
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
        --mode) LOOM_PROJECT_MODE="$2"; shift 2 ;;
        --docs-root) LOOM_DOCS_ROOT="$2"; shift 2 ;;
        --task) TASK_ID_ARG="$2"; shift 2 ;;
        --no-add) NO_ADD=1; shift ;;
        --doc-message) DOC_MESSAGE="$2"; shift 2 ;;
        *) break ;;
    esac
done

COMMIT_MESSAGE="${1:?Usage: checkpoint-task-commit.sh [--mode <repo|no-repo>] [--task <id>] [--no-add] \"commit message\"}"

PROJECT_ROOT="${PROJECT_ROOT:-$PWD}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"

SYMLINK_PATH="${PROJECT_ROOT}/$(lw_docs_root)/current-task.md"
TASKS_DIR="${PROJECT_ROOT}/$(lw_docs_root)/tasks"

TASK_FILE=""
TASK_ID=""
TRACKED_SHA=""

if [[ -n "$TASK_ID_ARG" ]]; then
    TASK_FILE=$(find "$TASKS_DIR" -maxdepth 1 -name "${TASK_ID_ARG}-*.md" 2>/dev/null | head -1)
    if [[ -z "$TASK_FILE" || ! -f "$TASK_FILE" ]]; then
        echo "ERROR: Task file non trovato per ${TASK_ID_ARG} in ${TASKS_DIR}" >&2
        exit 1
    fi
    TASK_ID=$(grep -m1 '^\- \*\*ID\*\*:' "$TASK_FILE" | sed 's/.*: //')
    TRACKED_SHA=$(grep -m1 '^\- \*\*Last tracked commit\*\*:' "$TASK_FILE" | sed 's/.*: //')
elif [[ -L "$SYMLINK_PATH" ]]; then
    TASK_FILE=$(readlink -f "$SYMLINK_PATH")
    if [[ -f "$TASK_FILE" ]]; then
        TASK_ID=$(grep -m1 '^\- \*\*ID\*\*:' "$TASK_FILE" | sed 's/.*: //')
        TRACKED_SHA=$(grep -m1 '^\- \*\*Last tracked commit\*\*:' "$TASK_FILE" | sed 's/.*: //')
    fi
fi

CURRENT_BRANCH=$(lw_current_branch)
CURRENT_SHA=$(lw_current_sha)

if ! lw_is_repo; then
    echo "-> no-repo mode: skip commit/push (nessun tracking git)"
    exit 0
fi

# Normalizza drift Progress: il modello a volte chiude la task con "✔️ 100%"
# invece di "✔️ Done" (idioma percentuale ereditato da start-task). Replace secco
# prima del commit: file committato corretto + gate TASK_DONE (più sotto) matcha.
if [[ -n "$TASK_FILE" && -f "$TASK_FILE" ]]; then
    sed -i 's|^\(- \*\*Progress\*\*:\) ✔️ 100%|\1 ✔️ Done|' "$TASK_FILE"
fi

STATUS=$(lw_git_status_porcelain)

if [[ -z "$STATUS" ]]; then
    echo "-> no changes to commit (SHA: ${CURRENT_SHA})"
    exit 0
fi

cd "$PROJECT_ROOT" || exit 1

if [[ $NO_ADD -eq 0 ]]; then
    lw_git_add -A
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

NEW_SHA=$(lw_current_sha)

# Last tracked commit: bump SOLO se la task NON è done. Il SHA del checkpoint si
# conosce solo DOPO il commit, quindi il sed modifica il task file post-commit
# (chicken-egg: scrivere il SHA cambierebbe di nuovo il SHA). Per le task in
# progress la riga sporca viene assorbita dal checkpoint successivo; per una task
# done non c'è checkpoint successivo → resterebbe WT dirty permanente. Lasciamo
# il valore stale (irrilevante: tracking chiuso) e WT pulito.
TASK_DONE=0
if [[ -n "$TASK_FILE" && -f "$TASK_FILE" ]] \
   && grep -qE '^- \*\*Progress\*\*:.*Done' "$TASK_FILE"; then
    TASK_DONE=1
fi

if [[ -n "$TASK_FILE" && -f "$TASK_FILE" && $TASK_DONE -eq 0 ]]; then
    sed -i "s|^\(- \*\*Last tracked commit\*\*:\).*|\1 ${NEW_SHA}|" "$TASK_FILE"
elif [[ $TASK_DONE -eq 1 ]]; then
    echo "-> task done: Last tracked commit non aggiornato (WT resta pulito)"
fi

# Derive compare URL from git remote (generic, non-hardcoded)
REMOTE_URL=$(lw_remote_url)
COMPARE_BASE=""
if [[ "$REMOTE_URL" =~ github\.com[:/](.+/.+)(\.git)?$ ]]; then
    REPO_PATH="${BASH_REMATCH[1]%.git}"
    COMPARE_BASE="https://github.com/${REPO_PATH}/compare"
fi

if [[ $COMMIT1_DONE -eq 1 ]]; then
    echo "-> commit 1 (codice+tracking): ${COMMIT1_SHA}"
fi
if [[ $COMMIT2_DONE -eq 1 ]]; then
    echo "-> commit 2 (doc-nozione, ${#DOC_FILES[@]} file): ${COMMIT2_SHA}"
fi
echo "-> HEAD: ${NEW_SHA} (was: ${TRACKED_SHA:-${CURRENT_SHA}})"
if [[ -n "$COMPARE_BASE" ]]; then
    if [[ -n "$TRACKED_SHA" ]]; then
        echo "-> compare: ${COMPARE_BASE}/${TRACKED_SHA}...${NEW_SHA}"
    else
        echo "-> compare: ${COMPARE_BASE}/${CURRENT_SHA}...${NEW_SHA}"
    fi
fi
