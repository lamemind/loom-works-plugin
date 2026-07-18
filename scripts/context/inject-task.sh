#!/usr/bin/env bash
# loom-works — inietta la task attiva nel CONTESTO del modello (hook SessionStart).
#
# Cascata di risoluzione (contratto famiglia, gemella della statusline):
#   1. $LOOM_TASK  — binding di sessione (modello detached: N sessioni parallele, id distinto)
#   2. symlink current-task.md — fallback linked mode (una sola task condivisa)
#
# stdout -> additionalContext: SessionStart inietta lo stdout dell'hook nel prompt 1x
# alla nascita della sessione. E' l'UNICO iniettore della task: l'@-import statico
# @runtime/current-task.md in CLAUDE.md e' stato rimosso (era la v0 cieca all'env ->
# in detached tutte le sessioni ricevevano lo stesso symlink = task sbagliata).
#
# Robustezza: nessun set -e (un task mancante NON deve rompere la sessione); sempre exit 0.

proj="${CLAUDE_PROJECT_DIR:-$PWD}"
id="${LOOM_TASK:-}"
src=""
f=""

if [ -n "$id" ]; then
  # env LOOM_TASK vince -> binding di sessione
  f="$(ls "$proj"/runtime/tasks/"${id}"-*.md 2>/dev/null | head -1)"
  src="\$LOOM_TASK=${id}"
else
  # fallback linked -> risolvi il symlink condiviso current-task.md
  for c in "$proj/runtime/current-task.md" "$proj/docs/current-task.md"; do
    if [ -L "$c" ]; then
      f="$(dirname "$c")/$(readlink "$c")"
      id="$(basename "$f" .md)"
      src="symlink current-task.md"
      break
    fi
  done
fi

if [ -n "$f" ] && [ -f "$f" ]; then
  echo "## Task attiva di questa sessione"
  echo
  echo "_Iniettata dall'hook SessionStart (loom-works) · risolta via ${src}._"
  echo
  cat "$f"
fi

exit 0
