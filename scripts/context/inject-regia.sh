#!/usr/bin/env bash
# loom-works — inietta la riga dell'ORGANIGRAMMA nel contesto di una conversazione
# aperta da una regia (hook SessionStart).
#
# stdout -> additionalContext, come ogni entry SessionStart.
#
# Una conversazione aperta dalla regia non sa di esserlo. Se pone una domanda con
# AskUserQuestion la regia non la puo' chiudere: un messaggio di un'altra sessione
# non risponde a un AskUserQuestion aperto, e la domanda resta ferma nella tab
# finche' l'utente non ci va. La riga dice alla sessione dove sta e dove vanno le
# domande: in chat, a fine turno, dove la regia le legge dopo l'evento `turno
# finito` del monitor. Il divieto vero lo fa l'hook PreToolUse
# (`deny-ask-regia.sh`): un'istruzione nel prompt il modello la puo' dimenticare,
# l'hook no.
#
# LA RIGA C'E' SOLO CON LOOM_REGIA. La mette il deck, e solo a uno spawn chiesto da
# una regia (`loom-deck-spawn --regia`, `loom-deck-headless open|reply --regia`);
# nessun figlio la eredita dal processo padre. Senza la variabile lo script non
# stampa niente: una conversazione aperta a mano non riceve nessuna riga.
#
# IL VALORE E' IL PERIMETRO E BASTA (`T197`), non la sessione della regia: la
# sessione che fa da regia cambia a un passaggio di consegne, il perimetro no. Un
# valore fuori dalla forma `T<numero>` non stampa niente: il testo entra nel
# contesto, e un valore arbitrario non deve diventare una riga che il modello legge
# come istruzione.
#
# Entry PROPRIA e non una sezione di inject-task.sh: quella satura il budget sui
# task file grandi (il cap e' per comando, non per sessione), e la riga deve
# arrivare intera anche quando la task arriva troncata.
#
# NESSUN SOTTOPROCESSO: in un turno headless SessionStart scatta a ogni `--resume`,
# cioe' a ogni risposta della regia, e in Git Bash su Windows ogni sottoprocesso
# costa circa 150 ms. Il controllo della forma e la stampa sono builtin di bash.
#
# Robustezza: nessun set -e, sempre exit 0 — una riga che non arriva non deve
# rompere la sessione.

regia="${LOOM_REGIA:-}"
[[ "$regia" =~ ^T[0-9]+$ ]] || exit 0

printf '%s\n' \
  "## Organigramma — conversazione aperta dalla regia di ${regia}" \
  "" \
  "Questa conversazione è aperta dalla regia di ${regia}: le domande le scrivi in chat a fine turno, le legge la regia e ti risponde. Non usare \`AskUserQuestion\`: la regia non chiude una domanda aperta con quello strumento, e qui è negato."
exit 0
