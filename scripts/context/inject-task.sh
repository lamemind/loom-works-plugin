#!/usr/bin/env bash
# loom-works — inietta la task attiva nel CONTESTO del modello (hook SessionStart).
#
# Cascata di risoluzione (contratto famiglia, gemella della statusline):
#   1. $LOOM_TASK  — binding di sessione (modello detached: N sessioni parallele, id distinto)
#   2. symlink current-task.md — fallback linked mode (una sola task condivisa)
#
# stdout -> additionalContext: SessionStart inietta lo stdout dell'hook nel prompt 1x
# alla nascita della sessione. E' l'UNICO iniettore della task.
#
# Budget (T40): Claude Code ha un cap di 10.000 CHAR (non byte) per comando hook;
# oltre soglia l'output viene SOSTITUITO da anteprima ~2KB + path -> mutilazione
# silenziosa. Fill greedy per priorita', stop al primo che non entra:
#   - cappello + filepath + Description: sempre presenti
#   - sezioni canoniche in ordine di priorita' finche' il totale sta nel budget
#   - sezioni non canoniche: mai iniettate
#   - marcatore finale: elenco sezioni omesse + path per recupero via Read
#
# Robustezza: nessun set -e (un task mancante NON deve rompere la sessione); sempre exit 0.

BUDGET=9800    # soglia operativa (T40/D4), sotto il cap reale 10k
RESERVE=400    # quota del budget riservata al marcatore di omissione

proj="${CLAUDE_PROJECT_DIR:-$PWD}"
id="${LOOM_TASK:-}"
src=""
f=""

if [ -n "$id" ]; then
  # env LOOM_TASK vince -> binding di sessione
  for root in runtime docs; do
    f="$(ls "$proj/$root"/tasks/"${id}"-*.md 2>/dev/null | head -1)"
    [ -n "$f" ] && break
  done
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
  awk -v budget="$BUDGET" -v reserve="$RESERVE" -v src="$src" -v path="$f" '
  function canon(h,   n) {
    n = tolower(h)
    sub(/^[ \t]+/, "", n)
    if (n ~ /^description/)         return "Description"
    if (n ~ /^acceptance/)          return "Acceptance Criteria"
    if (n ~ /^deliverables/)        return "Deliverables Checklist"
    if (n ~ /^decision/)            return "Decisions"
    if (n ~ /^dependenc/)           return "Dependencies"
    if (n ~ /^implementation note/) return "Implementation Notes"
    if (n ~ /^testing note/)        return "Testing Notes"
    if (n ~ /^doc impact/)          return "Doc Impact"
    if (n ~ /^prod validation/)     return "Prod Validation"
    if (n ~ /^progress log/)        return "Progress Log"
    return ""
  }
  BEGIN {
    nsec = 0
    nprio = split("Acceptance Criteria|Deliverables Checklist|Decisions|Dependencies|Implementation Notes|Testing Notes|Doc Impact|Prod Validation|Progress Log", prio, "|")
  }
  /^## / {
    nsec++
    name[nsec] = substr($0, 4)
    body[nsec] = $0 "\n"
    next
  }
  {
    if (nsec == 0) header = header $0 "\n"
    else body[nsec] = body[nsec] $0 "\n"
  }
  END {
    out = "## Task attiva di questa sessione\n\n"
    out = out "_Iniettata a SessionStart (loom-works) - risolta via " src "._\n"
    out = out "_File completo: " path "_\n\n"
    out = out header

    # Description: imprescindibile, entra sempre
    for (i = 1; i <= nsec; i++)
      if (canon(name[i]) == "Description") { out = out body[i]; used[i] = 1 }

    # greedy per priorita, stop al primo che non entra
    stopped = 0
    for (p = 1; p <= nprio && !stopped; p++) {
      for (i = 1; i <= nsec; i++) {
        if (used[i] || canon(name[i]) != prio[p]) continue
        if (length(out) + length(body[i]) <= budget - reserve) {
          out = out body[i]
          used[i] = 1
        } else {
          stopped = 1
          break
        }
      }
    }

    # omissioni = canoniche non entrate + non canoniche (mai iniettate)
    om = ""
    for (i = 1; i <= nsec; i++)
      if (!used[i]) om = om (om == "" ? "" : ", ") name[i]

    printf "%s", out
    if (om != "")
      printf "\n_[budget iniezione %d char] Sezioni omesse: %s. Contenuto integrale nel file indicato sopra (Read on-demand)._\n", budget, om
  }
  ' "$f"
fi

exit 0
