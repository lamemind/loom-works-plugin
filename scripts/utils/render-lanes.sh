#!/bin/bash
set -euo pipefail

# =============================================================================
# render-lanes.sh - Rigenera la sezione <!-- LANES:START/END --> in tasks.md
# Usage: render-lanes.sh [--docs-root <root>] [--remove <lane>]
#
# Implementa D3 (T08): git = verità, tasks.md = vista.
# Wrappa list-worktrees.sh (lasciato raw, detection pura) per scoprire i
# worktree lane, li aggrega per lane e inietta una sezione gestita add-or-replace
# in tasks.md.
#
# Detection:
#   Single-project: worktree lane di PROJECT_ROOT ({project}-{lane}).
#   Multi-project:  worktree lane dei sub-repo sibling in WORKTREE_BASE
#                   ({repo}-{lane}). Il base/docs repo non è branchato → nessuna
#                   lane lì, le lane emergono dai sub-repo.
#
# --remove <lane>: esclude esplicitamente una lane dalla vista (cleanup post-merge
#   quando il worktree non è ancora stato rimosso al momento della render).
#
# Noop silenzioso in no-repo (nessun worktree possibile).
# =============================================================================

REMOVE_LANE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --docs-root) LOOM_DOCS_ROOT="$2"; shift 2 ;;
        --remove)    REMOVE_LANE="$2"; shift 2 ;;
        -*) echo "ERROR: Flag sconosciuto: $1"; exit 1 ;;
        *) break ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# no-repo → nessun worktree, niente da rendere
lw_is_repo || exit 0

PROJECT_ROOT="$(lw_find_project_root)"
WORKTREE_BASE="$(dirname "$PROJECT_ROOT")"
DOCS_ROOT="$(lw_docs_root)"
TASKS_FILE="${PROJECT_ROOT}/${DOCS_ROOT}/tasks.md"

if [[ ! -f "$TASKS_FILE" ]]; then
    echo "WARN: tasks.md assente, render LANES saltata: ${TASKS_FILE}" >&2
    exit 0
fi

# ---------------------------------------------------------------------------
# Repos da scansionare: PROJECT_ROOT + sibling primary checkout in WORKTREE_BASE.
# I worktree lane hanno .git come FILE (non dir) → esclusi automaticamente.
# ---------------------------------------------------------------------------

declare -a SCAN_REPOS=("$PROJECT_ROOT")
while IFS= read -r -d '' d; do
    [[ "$d" == "$PROJECT_ROOT" ]] && continue
    [[ -d "$d/.git" ]] || continue
    SCAN_REPOS+=("$d")
done < <(find "$WORKTREE_BASE" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

# ---------------------------------------------------------------------------
# Detection via list-worktrees.sh (raw). Parse dei blocchi [lane] → TSV:
#   lane \t repo \t branch \t dirty \t task
# ---------------------------------------------------------------------------

TSV_TMP="$(mktemp)"
BLOCK_TMP="$(mktemp)"
OUT_TMP="$(mktemp)"
trap 'rm -f "$TSV_TMP" "$BLOCK_TMP" "$OUT_TMP"' EXIT

for repo in "${SCAN_REPOS[@]}"; do
    "${SCRIPT_DIR}/list-worktrees.sh" --filter lane "$repo" 2>/dev/null | awk '
        /^  [^ ].*\[lane\]$/ { line=$0; sub(/^  /,"",line); sub(/ \[lane\]$/,"",line);
                               wt=line; lane=""; branch=""; dirty=""; task=""; next }
        /^     Label:  lane=/ { lane=$0; sub(/.*lane=/,"",lane) }
        /^     Branch: /       { branch=$0; sub(/^     Branch: /,"",branch) }
        /^     Dirty:  /       { dirty=$0; sub(/^     Dirty:  /,"",dirty); sub(/ file.*/,"",dirty) }
        /^     Task:   /       { task=$0; sub(/^     Task:   /,"",task); if (task == "(none)") task="" }
        /^     Path:   / {
            repo=wt; if (lane != "") sub("-" lane "$","",repo)
            print lane "\t" repo "\t" branch "\t" dirty "\t" task
        }
    ' >> "$TSV_TMP" || true
done

# ---------------------------------------------------------------------------
# Aggregazione per lane (preserva ordine di prima apparizione)
# ---------------------------------------------------------------------------

declare -A L_REPOS L_BRANCHES L_DIRTY L_TASK
declare -a L_ORDER=()

while IFS=$'\t' read -r lane repo branch dirty task; do
    [[ -z "$lane" ]] && continue
    [[ -n "$REMOVE_LANE" && "$lane" == "$REMOVE_LANE" ]] && continue

    if [[ -z "${L_REPOS[$lane]+x}" ]]; then
        L_ORDER+=("$lane"); L_REPOS[$lane]=""; L_BRANCHES[$lane]=""; L_DIRTY[$lane]=0; L_TASK[$lane]=""
    fi

    case " ${L_REPOS[$lane]} " in *" $repo "*) :;; *) L_REPOS[$lane]="${L_REPOS[$lane]} $repo";; esac
    [[ -n "$branch" ]] && case " ${L_BRANCHES[$lane]} " in *" $branch "*) :;; *) L_BRANCHES[$lane]="${L_BRANCHES[$lane]} $branch";; esac

    # Prima task non vuota incontrata vince (single-project: una sola; multi: di norma nessuna)
    [[ -z "${L_TASK[$lane]}" && -n "$task" ]] && L_TASK[$lane]="$task"

    d="${dirty//[^0-9]/}"; [[ -z "$d" ]] && d=0
    L_DIRTY[$lane]=$(( ${L_DIRTY[$lane]} + d ))
done < "$TSV_TMP"

# ---------------------------------------------------------------------------
# Render righe tabella
# ---------------------------------------------------------------------------

ROWS=""
for lane in "${L_ORDER[@]}"; do
    repos="$(echo "${L_REPOS[$lane]}" | xargs | sed 's/ /, /g')"
    branches="$(echo "${L_BRANCHES[$lane]}" | xargs | sed 's/ /, /g')"
    [[ -z "$branches" ]] && branches="—"
    task="${L_TASK[$lane]:-—}"
    d="${L_DIRTY[$lane]}"
    if [[ "$d" -eq 0 ]]; then stato="🟢 clean"; else stato="🔴 ${d} file"; fi
    ROWS+="| ${lane} | ${repos} | ${branches} | ${task} | ${stato} |"$'\n'
done

{
    echo "<!-- LANES:START -->"
    echo "## Lane attive"
    echo ""
    echo "| Lane | Repos | Branch | Task | Stato |"
    echo "|------|-------|--------|------|-------|"
    if [[ -n "$ROWS" ]]; then
        printf '%s' "$ROWS"
    else
        echo "| _(nessuna lane attiva)_ |  |  |  |  |"
    fi
    echo "<!-- LANES:END -->"
} > "$BLOCK_TMP"

# ---------------------------------------------------------------------------
# Inject add-or-replace
#   - se i marker esistono → sostituisci il blocco
#   - altrimenti → inserisci prima di "## Execution Plan" (o append in fondo)
# ---------------------------------------------------------------------------

if grep -q '<!-- LANES:START -->' "$TASKS_FILE"; then
    awk -v bf="$BLOCK_TMP" '
        BEGIN { while ((getline l < bf) > 0) b = b l "\n"; sub(/\n$/,"",b) }
        /<!-- LANES:START -->/ { print b; skip=1; next }
        /<!-- LANES:END -->/   { skip=0; next }
        skip { next }
        { print }
    ' "$TASKS_FILE" > "$OUT_TMP"
else
    awk -v bf="$BLOCK_TMP" '
        BEGIN { while ((getline l < bf) > 0) b = b l "\n"; sub(/\n$/,"",b) }
        /^## Execution Plan/ && !done { print b; print ""; done=1 }
        { print }
        END { if (!done) { print ""; print b } }
    ' "$TASKS_FILE" > "$OUT_TMP"
fi

mv "$OUT_TMP" "$TASKS_FILE"
echo "-> LANES section aggiornata (${#L_ORDER[@]} lane) in ${TASKS_FILE#"$PROJECT_ROOT"/}"
