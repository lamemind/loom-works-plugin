#!/usr/bin/env bash
# loom-works — inietta la regola del registro ADR nel CONTESTO (hook SessionStart).
#
# stdout -> additionalContext, come ogni entry SessionStart.
#
# Perche' un emitter e non un `cat` diretto di docs/adr.md: il testo deve portare
# un comando ESEGUIBILE, e CLAUDE_PLUGIN_ROOT non e' nell'ambiente del tool Bash
# (verificato: la env e' interpolata nei body di skill e agent e nei command degli
# hook, non esportata al tool). Un `${CLAUDE_PLUGIN_ROOT}/scripts/task/adr.sh`
# copiato dal contesto si risolverebbe in `/scripts/task/adr.sh` — un fallimento
# che si presenta come comando non trovato, lontano dalla causa. Qui lo script
# risolve la propria sede da BASH_SOURCE e riempie il segnaposto {PLUGIN_ROOT}.
#
# Entry PROPRIA e non una sezione dentro inject-task.sh: quella satura il budget
# sui task file grandi (il cap e' per comando, non per sessione) e non gira
# affatto in una sessione senza task attiva, dove la regola serve uguale.
#
# Nessun indice dei record esce da qui, per scelta: il registro si interroga con
# `adr.sh cerca`, e una lista in contesto invecchierebbe a ogni scarto scritto.
#
# Robustezza: nessun set -e, sempre exit 0 — una regola che non arriva non deve
# rompere la sessione.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOC="${ROOT}/docs/adr.md"

[ -f "$DOC" ] || exit 0
sed "s|{PLUGIN_ROOT}|${ROOT}|g" "$DOC"
exit 0
