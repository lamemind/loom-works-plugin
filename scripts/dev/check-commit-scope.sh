#!/usr/bin/env bash
# check-commit-scope.sh — gate T123: un commit di skill task porta SOLO i suoi path.
#
# L'indice git e' uno per worktree, non per sessione: un `git mv` o un `git add`
# lasciato da un'altra sessione sta in stage quando la skill committa, e un
# `git commit -m` senza pathspec lo rastrella sotto un messaggio che parla d'altro.
# Questo gate sporca l'indice di un repo temporaneo con path estranei, poi esegue
# ogni attore che committa (create-task, lo snippet di preflight, checkpoint nei due
# regimi, clean-tasks, cleanup-done-tasks) e misura:
#   - i file dentro ogni commit prodotto (solo quelli attesi)
#   - cio' che resta in stage dopo (i path estranei, intatti)
#   - la timbratura "Done at" dentro il commit di checkpoint
#
# Il regime linked (symlink current-task.md) e' l'eccezione dichiarata: il worktree
# appartiene alla task e `git add -A` e' legittimo — si misura che committa tutto,
# non che scopa. Per questo gira per ultimo: consuma i path estranei.
#
# Uso interno pre-publish (publish.sh lo esegue come gate):
#   ./scripts/dev/check-commit-scope.sh [--keep]
#
# Exit: 0 = tutte le asserzioni passano · 1 = almeno una fallisce · 2 = errore uso.

set -u

KEEP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --keep) KEEP=1; shift ;;
    *) echo "arg sconosciuto: $1" >&2; exit 2 ;;
  esac
done

PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TASK_SCRIPTS="$PLUGIN_ROOT/scripts/task"
command -v jq >/dev/null || { echo "jq richiesto" >&2; exit 2; }

REPO="$(mktemp -d)"
cleanup() { [ "$KEEP" -eq 1 ] && { echo "repo lasciato in: $REPO"; return; }; rm -rf -- "$REPO"; }
trap cleanup EXIT

FAIL=0
pass() { echo "  ok   $*"; }
fail() { echo "  FAIL $*" >&2; FAIL=1; }

# set sorted newline-joined, da confrontare con `expect`
committed() { git -C "$REPO" diff-tree --no-commit-id --name-only -r --no-renames "$1" | sort; }
staged()    { git -C "$REPO" diff --cached --name-only --no-renames | sort; }
expect() {  # <label> <actual> <expected-lines...>
  local label="$1" actual="$2"; shift 2
  local want; want="$(printf '%s\n' "$@" | sort)"
  if [ "$actual" = "$want" ]; then pass "$label"; else
    fail "$label"
    echo "       atteso:  $(echo "$want" | tr '\n' ' ')" >&2
    echo "       trovato: $(echo "$actual" | tr '\n' ' ')" >&2
  fi
}

FOREIGN=(".26-01-01-altrui/a.txt" ".26-01-01-altrui/b.txt" "altrui.txt")
expect_foreign_staged() { expect "$1 — i path estranei restano in stage" "$(staged)" "${FOREIGN[@]}"; }

task_file() {  # <id> <slug> <progress>
  cat > "$REPO/docs/tasks/$1-$2.md" <<MD
# Task: $2

- **ID**: $1
- **Created on**: 2026-01-01
- **Priority**: Med
- **Size**: S
- **Folder**: ${4:-}
- **Progress**: $3

## Description

fixture

## Decisions

## Doc Impact
MD
}

# ── fixture ─────────────────────────────────────────────────────────────────
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email gate@loom
git -C "$REPO" config user.name gate
git -C "$REPO" config commit.gpgsign false
mkdir -p "$REPO/.claude" "$REPO/docs/tasks" "$REPO/docs/reference" "$REPO/src" "$REPO/.26-01-01-altrui" "$REPO/.26-01-01-t03"
echo '{"id":"gate","emoji":"🧪","name":"gate","docsRoot":"docs"}' > "$REPO/.claude/loom-works.json"
# come in un progetto reale: il symlink della task attiva e' runtime, non tracciato
printf 'docs/current-task.md\n*.log\n' > "$REPO/.gitignore"
cat > "$REPO/docs/tasks.md" <<'MD'
# Tasks

## Tasks Overview

| ID  | Pri | Prog | Task (max 64) |
| --- | --- | ---- | ------------- |
| T03 | ⚡ | ✔️ | baz |
| T02 | ⚡ | 🟡 | bar |

## Lane attive

## Execution Plan

```
Legend: ✔️ Done  🟡 In Progress  🔒 Locked
```
MD
echo code > "$REPO/src/code.txt"
echo a > "$REPO/.26-01-01-altrui/a.txt"
echo t03 > "$REPO/.26-01-01-t03/f.txt"
echo log > "$REPO/.26-01-01-t03/x.log"
task_file T02 bar "🟡 In Progress"
task_file T03 baz "✔️ Done at 2020-01-01" "./.26-01-01-t03"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m "init"

# indice sporco come lo lascia un'altra sessione: un rename (git mv stagia da se')
# e un add a meta'
git -C "$REPO" mv .26-01-01-altrui/a.txt .26-01-01-altrui/b.txt
echo x > "$REPO/altrui.txt"; git -C "$REPO" add altrui.txt
expect_foreign_staged "fixture"

cd "$REPO" || exit 2
unset LOOM_TASK
source "$PLUGIN_ROOT/scripts/utils/lib.sh"

# ── 1. wrapper senza pathspec ────────────────────────────────────────────────
echo "1. lw_git_add_n_commit senza pathspec"
lw_git_add_n_commit "msg" 2>/dev/null; rc=$?
[ "$rc" -eq 3 ] && pass "rifiuta (exit 3)" || fail "atteso exit 3, trovato $rc"
expect_foreign_staged "wrapper"
BEFORE="$(git rev-parse HEAD)"
[ "$(git rev-parse HEAD)" = "$BEFORE" ] && pass "nessun commit prodotto" || fail "ha committato"

# ── 2. create-task.sh ────────────────────────────────────────────────────────
echo "2. create-task.sh"
task_file T01 foo "🔵 Backlog"
"$TASK_SCRIPTS/create-task.sh" T01 foo "foo desc" Med >/dev/null 2>&1 || fail "create-task.sh exit $?"
expect "commit = task file + tasks.md" "$(committed HEAD)" docs/tasks.md docs/tasks/T01-foo.md
expect_foreign_staged "create-task"

# ── 3. snippet di preflight-task ─────────────────────────────────────────────
echo "3. preflight-task (snippet lw_git_add_n_commit)"
printf '\n### Preflight\n\n- **D1** — x\n' >> docs/tasks/T01-foo.md
sed -i 's/| T01 | ⚡ | 🔵 |/| T01 | ⚡ | 🟢 |/' docs/tasks.md
lw_git_add_n_commit "task(T01): preflight - 1 decisioni congelate" docs/tasks/T01-foo.md docs/tasks.md >/dev/null || fail "wrapper exit $?"
expect "commit = task file + tasks.md" "$(committed HEAD)" docs/tasks.md docs/tasks/T01-foo.md
expect_foreign_staged "preflight"

# ── 4. checkpoint-task-commit.sh detached ───────────────────────────────────
echo "4. checkpoint-task-commit.sh detached (\$LOOM_TASK, pathspec dopo --)"
echo more >> src/code.txt
echo nozione > docs/reference/nuova.md
sed -i 's/^- \*\*Progress\*\*: .*/- **Progress**: ✔️ Done/' docs/tasks/T01-foo.md
LOOM_TASK=T01 "$TASK_SCRIPTS/checkpoint-task-commit.sh" "checkpoint(T01): x" >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && pass "senza pathspec in detached: rifiuta (exit $rc)" || fail "senza pathspec in detached ha committato"
LOOM_TASK=T01 "$TASK_SCRIPTS/checkpoint-task-commit.sh" --doc-message "docs(T01): n" "checkpoint(T01): x" -- src/code.txt docs/reference/nuova.md >/dev/null 2>&1 || fail "checkpoint detached exit $?"
expect "commit 1 = codice + task file" "$(committed HEAD~1)" src/code.txt docs/tasks/T01-foo.md
expect "commit 2 = doc-nozione" "$(committed HEAD)" docs/reference/nuova.md
git show HEAD~1:docs/tasks/T01-foo.md | grep -q "✔️ Done at 20" && pass "Done at dentro il commit" || fail "Done at assente dal commit"
[ -z "$(git status --porcelain -- docs/tasks/T01-foo.md)" ] && pass "task file pulito dopo il commit" || fail "task file ancora dirty"
expect_foreign_staged "checkpoint detached"

# ── 5. clean-tasks.sh / cleanup-done-tasks.sh ───────────────────────────────
echo "5. clean-tasks.sh --apply"
"$TASK_SCRIPTS/clean-tasks.sh" --apply T01 >/dev/null 2>&1 || fail "clean-tasks exit $?"
expect "commit = task file + tasks.md" "$(committed HEAD)" docs/tasks.md docs/tasks/T01-foo.md
expect_foreign_staged "clean-tasks"

echo "   cleanup-done-tasks.sh --apply --ignored-files keep (folder con file ignorato)"
"$TASK_SCRIPTS/cleanup-done-tasks.sh" --apply --days 1 --ignored-files keep T03 >/dev/null 2>&1 || fail "cleanup-done-tasks exit $?"
expect "commit keep = solo il file ignorato" "$(committed HEAD~1)" .26-01-01-t03/x.log
expect "commit purge = task file + folder + tasks.md" "$(committed HEAD)" docs/tasks.md docs/tasks/T03-baz.md .26-01-01-t03/f.txt .26-01-01-t03/x.log
expect_foreign_staged "cleanup-done-tasks"

# ── 6. checkpoint-task-commit.sh linked — per ultimo, consuma l'indice ──────
echo "6. checkpoint-task-commit.sh linked (symlink, git add -A legittimo)"
ln -s tasks/T02-bar.md docs/current-task.md
echo linked >> src/code.txt
sed -i 's/^- \*\*Progress\*\*: .*/- **Progress**: ✔️ Done/' docs/tasks/T02-bar.md
"$TASK_SCRIPTS/checkpoint-task-commit.sh" "checkpoint(T02): y" >/dev/null 2>&1 || fail "checkpoint linked exit $?"
expect "commit = tutto il worktree, rename compreso" "$(committed HEAD)" src/code.txt docs/tasks/T02-bar.md "${FOREIGN[@]}"
git show HEAD:docs/tasks/T02-bar.md | grep -q "✔️ Done at 20" && pass "Done at dentro il commit" || fail "Done at assente dal commit"
[ -z "$(staged)" ] && pass "indice vuoto dopo il commit linked" || fail "indice non vuoto: $(staged | tr '\n' ' ')"

echo
if [ "$FAIL" -eq 0 ]; then echo "OK: ogni commit resta nel proprio perimetro"; exit 0; fi
echo "FERMO: un commit porta path che non sono suoi" >&2
exit 1
