#!/usr/bin/env bash
# Raccoglie stato git/fs per recap-status

set -euo pipefail

DOCS_ROOT="runtime"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --docs-root) DOCS_ROOT="$2"; shift 2;;
    *) shift;;
  esac
done

echo "=== BRANCH ==="
git rev-parse --abbrev-ref HEAD

echo ""
echo "=== HEAD COMMIT ==="
git log -1 --oneline

echo ""
echo "=== RECENT COMMITS ==="
git log --oneline -15

echo ""
echo "=== WORKING TREE ==="
if git status --porcelain | grep -q .; then
  git status --porcelain
else
  echo "(clean)"
fi

echo ""
echo "=== WORKTREES ==="
git worktree list

echo ""
echo "=== CURRENT TASK SYMLINK ==="
if [ -L "${DOCS_ROOT}/current-task.md" ]; then
  target=$(readlink "${DOCS_ROOT}/current-task.md")
  resolved=$(readlink -f "${DOCS_ROOT}/current-task.md" 2>/dev/null || echo "(broken)")
  echo "active: ${target}"
  echo "resolved: ${resolved}"
else
  echo "none"
fi

echo ""
echo "=== TASK FILES ==="
ls "${DOCS_ROOT}/tasks/" 2>/dev/null || echo "(no tasks/)"
