#!/bin/bash
set -euo pipefail

# =============================================================================
# reconcile-tasks-context.sh - Estrae contesto OT per riconciliazione tasks.md
# Usage: reconcile-tasks-context.sh [--docs-root <root>] <conflict-dir>
#
# Precondition: merge in corso (MERGE_HEAD esiste) in <conflict-dir>
# Rilevante solo per single-project (in multi-project tasks.md non viene branchato).
# Output: contesto strutturato per LLM (stdout)
# =============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --docs-root) LOOM_DOCS_ROOT="$2"; shift 2 ;;
        -*) echo "ERROR: Flag sconosciuto: $1" >&2; exit 1 ;;
        *) break ;;
    esac
done

CONFLICT_DIR="${1:-}"
if [[ -z "$CONFLICT_DIR" || ! -d "$CONFLICT_DIR" ]]; then
    echo "Usage: reconcile-tasks-context.sh [--docs-root <root>] <conflict-dir>" >&2
    exit 1
fi

DOCS_ROOT="${LOOM_DOCS_ROOT:-docs}"
TASKS_PATH="${DOCS_ROOT}/tasks.md"

cd "$CONFLICT_DIR"

if ! git rev-parse MERGE_HEAD >/dev/null 2>&1; then
    echo "ERROR: Nessun merge in corso in ${CONFLICT_DIR} (MERGE_HEAD non trovato)" >&2
    exit 1
fi

HEAD_SHA=$(git rev-parse --short HEAD)
MERGE_SHA=$(git rev-parse --short MERGE_HEAD)
BASE_SHA=$(git merge-base HEAD MERGE_HEAD)
BASE_SHORT=$(git rev-parse --short "$BASE_SHA")

CONFLICTED=$(git diff --name-only --diff-filter=U)

if [[ -z "$CONFLICTED" ]]; then
    echo "ERROR: Nessun file in conflitto in ${CONFLICT_DIR}" >&2
    exit 1
fi

# Classifica file: tasks.md vs other
TASKS_FILES=()
OTHER_FILES=()

while IFS= read -r file; do
    if [[ "$file" == "$TASKS_PATH" ]]; then
        TASKS_FILES+=("$file")
    else
        OTHER_FILES+=("$file")
    fi
done <<< "$CONFLICTED"

echo "=== CONFLICTED FILES ==="
for f in "${TASKS_FILES[@]+"${TASKS_FILES[@]}"}"; do
    echo "$f [tasks]"
done
for f in "${OTHER_FILES[@]+"${OTHER_FILES[@]}"}"; do
    echo "$f [other]"
done
echo ""

# --- tasks.md: contesto OT completo ---

for file in "${TASKS_FILES[@]+"${TASKS_FILES[@]}"}"; do
    echo "=== TASKS FILE: $file ==="
    echo ""

    echo "--- BASE (merge-base: $BASE_SHORT) ---"
    git show "${BASE_SHA}:${file}" 2>/dev/null || echo "(file non esisteva al merge-base)"
    echo ""

    echo "--- DIFF A (HEAD: $HEAD_SHA) ---"
    git diff "${BASE_SHA}..HEAD" -- "$file" 2>/dev/null || echo "(nessun diff)"
    echo ""

    echo "--- COMMITS A (HEAD) ---"
    git log "${BASE_SHA}..HEAD" --oneline -- "$file" 2>/dev/null || echo "(nessun commit)"
    echo ""

    echo "--- DIFF B (MERGE_HEAD: $MERGE_SHA) ---"
    git diff "${BASE_SHA}..MERGE_HEAD" -- "$file" 2>/dev/null || echo "(nessun diff)"
    echo ""

    echo "--- COMMITS B (MERGE_HEAD) ---"
    git log "${BASE_SHA}..MERGE_HEAD" --oneline -- "$file" 2>/dev/null || echo "(nessun commit)"
    echo ""
done

# --- Other files (lista; risolti con checkout --theirs in reconcile-tasks) ---

if [[ ${#OTHER_FILES[@]} -gt 0 ]]; then
    echo "=== OTHER CONFLICTED FILES ==="
    for f in "${OTHER_FILES[@]}"; do
        echo "$f"
    done
fi
