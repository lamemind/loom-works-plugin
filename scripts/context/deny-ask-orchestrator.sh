#!/usr/bin/env bash
# loom-works — nega AskUserQuestion in una conversazione aperta da un orchestrator (hook
# PreToolUse, matcher AskUserQuestion).
#
# stdout -> decisione dell'hook: un JSON `hookSpecificOutput` con
# `permissionDecision: deny` e un motivo che Claude Code passa al modello al posto
# del risultato dello strumento. Lo stdout di PreToolUse non entra nel contesto
# come testo: entra il solo motivo del deny.
#
# PERCHE' UN DIVIETO E NON SOLO UNA RIGA. La riga dell'organigramma
# (`inject-orchestrator.sh`) dice alla sessione di scrivere le domande in chat, ma e'
# un'istruzione nel prompt e il modello la puo' dimenticare — le domande di una
# skill (`checkpoint-task`, `create-task`) arrivano dal body della skill, scritto
# per una sessione con un umano davanti. Un AskUserQuestion aperto l'orchestrator non lo
# chiude: la domanda resta ferma nella tab finche' l'utente non ci va. L'hook vale
# sempre: il motivo dice di scrivere la domanda in chat e chiudere il turno.
#
# NEGA SULLA SOLA PRESENZA DI LOOM_ORCHESTRATOR, senza chiedersi se l'orchestrator e' vivo. Una
# tab che sopravvive al suo orchestrator continua a scrivere le domande in chat, dove
# l'utente le legge: il costo e' una domanda in chat invece che nel riquadro, mai
# una domanda persa. Il controllo leggerebbe lo stato dell'orchestrator su disco, un
# formato di un'altra task. Senza LOOM_ORCHESTRATOR lo script non stampa niente ed esce 0:
# lo strumento passa.
#
# In un turno headless (`claude -p`) AskUserQuestion non esiste, e questo hook non
# scatta mai: li' lavora solo la riga dell'organigramma.
#
# L'id del perimetro orchestrabile entra nel motivo solo nella forma `T<numero>`: il motivo e' JSON
# scritto a mano, e un valore arbitrario lo romperebbe. Un valore fuori forma nega
# lo stesso, senza nominare l'orchestrator.
#
# NESSUN SOTTOPROCESSO, e lo stdin non si legge: il matcher di hooks.json filtra
# gia' lo strumento, e il payload non porta niente che cambi la decisione.
#
# Robustezza: nessun set -e, sempre exit 0 — un hook che fallisce non deve
# bloccare la sessione, e una decisione che non arriva lascia passare lo strumento.

orchestrator="${LOOM_ORCHESTRATOR:-}"
[ -n "$orchestrator" ] || exit 0

if [[ "$orchestrator" =~ ^T[0-9]+$ ]]; then
  chi="dall'orchestrator di ${orchestrator}"
else
  chi="da un orchestrator"
fi

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
  "AskUserQuestion non è disponibile: questa conversazione è aperta ${chi}, e l'orchestrator non chiude una domanda aperta con questo strumento. Scrivi la domanda in chat, in prosa, e chiudi il turno: l'orchestrator la legge a fine turno e ti risponde."
exit 0
