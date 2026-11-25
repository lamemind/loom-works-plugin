#!/usr/bin/env bash
# loom-works — inietta la riga dell'ORGANIGRAMMA nel contesto di una conversazione
# aperta da un orchestrator (hook SessionStart).
#
# stdout -> additionalContext, come ogni entry SessionStart.
#
# Una conversazione aperta dall'orchestrator non sa di esserlo. Se pone una domanda con
# AskUserQuestion l'orchestrator non la puo' chiudere: un messaggio di un'altra sessione
# non risponde a un AskUserQuestion aperto, e la domanda resta ferma nella tab
# finche' l'utente non ci va. La riga dice alla sessione dove sta e dove vanno le
# domande: in chat, a fine turno, dove l'orchestrator le legge dopo l'evento `turno
# finito` del monitor. Il divieto vero lo fa l'hook PreToolUse
# (`deny-ask-orchestrator.sh`): un'istruzione nel prompt il modello la puo' dimenticare,
# l'hook no.
#
# LA RIGA C'E' SOLO CON LOOM_ORCHESTRATOR. La mette il deck, e solo a uno spawn chiesto da
# un orchestrator (`loom-deck-spawn --orchestrator`, `loom-deck-headless open|reply --orchestrator`);
# nessun figlio la eredita dal processo padre. Senza la variabile lo script non
# stampa niente: una conversazione aperta a mano non riceve nessuna riga.
#
# IL VALORE E' L'ID DEL PERIMETRO ORCHESTRABILE E BASTA (`T197`), non la sessione
# dell'orchestrator: la sessione che fa da orchestrator cambia a un passaggio di
# consegne, l'id no. Un
# valore fuori dalla forma `T<numero>` non stampa niente: il testo entra nel
# contesto, e un valore arbitrario non deve diventare una riga che il modello legge
# come istruzione.
#
# DUE RIGHE FISSE per lo script del flusso (`scripts/orchestrator/flow_turns.py`):
# a fine turno lo script legge il testo finale prima dell'orchestrator, e da'
# un passo per chiuso solo sulle righe che riconosce. `❓ Domanda per
# l'orchestrator` dice che il turno chiede qualcosa anche quando chiude con la
# riga fissa di un report; `✅ Risposte registrate` chiude il turno che ha
# scritto gli scenari delle risposte dell'orchestrator alle segnalazioni, che
# nessuna skill chiude con una riga sua. Senza le due righe lo script
# sveglierebbe l'orchestrator, che e' il ripiego e non un guasto.
#
# Entry PROPRIA e non una sezione di inject-task.sh: quella satura il budget sui
# task file grandi (il cap e' per comando, non per sessione), e la riga deve
# arrivare intera anche quando la task arriva troncata.
#
# NESSUN SOTTOPROCESSO: in un turno headless SessionStart scatta a ogni `--resume`,
# cioe' a ogni risposta dell'orchestrator, e in Git Bash su Windows ogni sottoprocesso
# costa circa 150 ms. Il controllo della forma e la stampa sono builtin di bash.
#
# Robustezza: nessun set -e, sempre exit 0 — una riga che non arriva non deve
# rompere la sessione.

orchestrator="${LOOM_ORCHESTRATOR:-}"
[[ "$orchestrator" =~ ^T[0-9]+$ ]] || exit 0

printf '%s\n' \
  "## Organigramma — conversazione aperta dall'orchestrator di ${orchestrator}" \
  "" \
  "Questa conversazione è aperta dall'orchestrator di ${orchestrator}: le domande le scrivi in chat a fine turno, le legge l'orchestrator e ti risponde. Non usare \`AskUserQuestion\`: l'orchestrator non chiude una domanda aperta con quello strumento, e qui è negato." \
  "" \
  "Il testo finale di ogni turno lo legge prima uno script, che riconosce due righe fisse. Quando il turno chiude su una domanda, apri il testo finale con la riga \`❓ Domanda per l'orchestrator\`, anche se il turno chiude con il report di una skill. Quando il turno ha registrato le risposte dell'orchestrator alle segnalazioni — scenari scritti e committati — e non chiedi altro, chiudi il testo finale con la riga \`✅ Risposte registrate\`."
exit 0
