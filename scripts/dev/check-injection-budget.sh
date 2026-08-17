#!/usr/bin/env bash
# check-injection-budget.sh — guard T40: misura le hook entry contro la soglia operativa.
#
# Claude Code cappa lo stdout di OGNI comando hook a 10.000 CHAR (non byte); oltre
# soglia l'output viene SOSTITUITO da anteprima ~2KB + path -> il contesto del modello
# riceve un payload mutilato SENZA errori visibili. Questo guard misura ogni entry di
# hooks/hooks.json contro la soglia operativa (default 9.800) e fallisce se una sfora.
#
# Il restamp ha un tetto PROPRIO e piu' stretto (4.500): gira su UserPromptSubmit, cioe'
# a ogni turno, e non risponde alla stessa economia delle entry SessionStart.
#
# Uso interno pre-publish (vedi plugin-dev.md, flusso di pubblicazione):
#   ./scripts/dev/check-injection-budget.sh [--project <dir>] [--threshold N]
#                                           [--restamp-threshold N]
#
# - Entry statiche: eseguite as-is (senza LOOM_TASK), misurate una volta.
# - Entry dinamica (inject-task.sh): sweep su TUTTI i task file del progetto --project
#   (default: cwd se contiene runtime/tasks o docs/tasks), una run per LOOM_TASK.
#
# Exit: 0 = tutte le entry sotto soglia · 1 = almeno una sfora · 2 = errore uso.

set -u

THRESHOLD=9800

# Tetto proprio del restamp, piu' stretto di quello di piattaforma. `UserPromptSubmit`
# gira a OGNI TURNO, mentre ogni entry `SessionStart` si paga una volta per sessione:
# e' l'unica entry a costo moltiplicativo, e a 9.800 char sarebbe il canale piu' caro
# del sistema. Il tetto stava scritto DENTRO il file, per essere letto da chi lo allarga
# — ma quella riga si pagava a ogni turno anch'essa, ed era cornice per chi esegue il
# contratto invece di editarlo. Qui e' una guardia che fallisce, non una riga da leggere.
RESTAMP_THRESHOLD=4500

PROJECT="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --project)   PROJECT="$2"; shift 2 ;;
    --threshold) THRESHOLD="$2"; shift 2 ;;
    --restamp-threshold) RESTAMP_THRESHOLD="$2"; shift 2 ;;
    *) echo "arg sconosciuto: $1" >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOKS="$ROOT/hooks/hooks.json"
[ -f "$HOOKS" ] || { echo "hooks.json non trovato: $HOOKS" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq richiesto" >&2; exit 2; }

fail=0
printf '%-18s %-52s %8s  %s\n' "EVENT" "ENTRY" "CHAR" "STATUS"

check() { # $1=event $2=label $3=chars
  local status="OK" limit="$THRESHOLD"
  # Il restamp risponde al proprio tetto, non a quello di piattaforma: e' l'entry
  # che si paga per turno invece che per sessione.
  case "$2" in *restamp*) limit="$RESTAMP_THRESHOLD" ;; esac
  [ "$3" -gt "$limit" ] && { status="OVER ($limit)"; fail=1; }
  printf '%-18s %-52s %8s  %s\n' "$1" "$2" "$3" "$status"
}

while IFS=$'\t' read -r ev cmd; do
  rcmd="${cmd//\$\{CLAUDE_PLUGIN_ROOT\}/$ROOT}"
  label="${cmd##*/}"; label="${label%\"}"

  if [[ "$cmd" == *inject-task.sh* ]]; then
    # entry dinamica: sweep su tutti i task file del progetto
    found=0; max=0; maxid="-"
    for tf in "$PROJECT"/runtime/tasks/[TD][0-9]*.md "$PROJECT"/docs/tasks/[TD][0-9]*.md; do
      [ -f "$tf" ] || continue
      found=$((found+1))
      tid="$(basename "$tf")"; tid="${tid%%-*}"
      n=$(LOOM_TASK="$tid" CLAUDE_PROJECT_DIR="$PROJECT" bash -c "$rcmd" 2>/dev/null | wc -m)
      if [ "$n" -gt "$max" ]; then max=$n; maxid=$tid; fi
    done
    if [ "$found" -eq 0 ]; then
      printf '%-18s %-52s %8s  %s\n' "$ev" "$label (dinamica)" "-" "SKIP: nessun task file in $PROJECT"
    else
      check "$ev" "$label (max su $found task: $maxid)" "$max"
    fi
  else
    n=$( (unset LOOM_TASK; CLAUDE_PROJECT_DIR="$PROJECT" bash -c "$rcmd") 2>/dev/null | wc -m )
    check "$ev" "$label" "$n"
  fi
done < <(jq -r '.hooks | to_entries[] | .key as $ev | .value[].hooks[].command | $ev + "\t" + .' "$HOOKS")

echo
# Due soglie, due conseguenze diverse: sfondare $THRESHOLD mutila il payload, sfondare
# quella del restamp non rompe niente subito — moltiplica un costo per ogni turno. Il
# messaggio le nomina entrambe, o chi legge un OVER sul restamp cerca una mutilazione
# che non c'e'.
if [ "$fail" -eq 1 ]; then
  echo "FAIL: almeno una entry sopra la propria soglia (piattaforma $THRESHOLD char, restamp $RESTAMP_THRESHOLD)."
  echo "  oltre $THRESHOLD il payload arriva mutilato (anteprima 2KB + path); oltre il tetto del restamp il costo si moltiplica per ogni turno."
else
  echo "OK: tutte le entry sotto la propria soglia (piattaforma $THRESHOLD char, restamp $RESTAMP_THRESHOLD)."
fi
exit "$fail"
