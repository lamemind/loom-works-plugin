#!/usr/bin/env bash
# loom-works — ri-timbra i contratti nel CONTESTO, solo sui turni umani (hook
# UserPromptSubmit).
#
# stdout -> contesto del modello.
#
# Perche' uno script e non un `cat` diretto di docs/restamp.md: Claude Code chiama
# prompt anche cio' che non ha scritto nessuno — la fine di un comando o di un
# subagent in background, il messaggio di un subagent, il messaggio di un'altra
# sessione. Il restamp contrasta il drift sui turni umani: su quei messaggi ripete
# il contratto senza un turno da proteggere, e il costo cresce col numero di agenti
# invece che col numero di turni.
#
# IL SOLO DISCRIMINANTE E' IL TESTO DI `prompt`. Il payload ha le stesse chiavi per
# umano e macchina, e l'origine del messaggio (`origin.kind`, `commandMode`) sta nel
# transcript, non sullo stdin.
#
# SI SOPPRIME SOLO SU UNA FORMA NOTA, tutto il resto riceve il restamp: stdin vuoto,
# JSON rotto, forma nuova. Il filtro poggia su un testo che il CLI puo' cambiare
# senza avviso, e la direzione del guasto deve restare questa: torna lo spreco, mai
# un umano senza contratto.
#
# I PATTERN CERCANO I BYTE GREZZI DEL JSON: `"prompt":"` senza spazio, l'a capo
# scritto `\n`, le virgolette scritte `\"`. Un prompt umano che CITA una di queste
# forme non matcha, perche' nel JSON le sue virgolette arrivano scritte `\"` e la
# chiave non si ricompone. Chi invece APRE il prompt con una forma nota perde il
# restamp per un turno, ed e' accettato.
#
# NESSUN SOTTOPROCESSO, e la ragione e' il costo: lo script gira a ogni messaggio
# consegnato, e in Git Bash su Windows ogni sottoprocesso costa circa 150 ms. Per
# questo niente `jq` per il match e niente `cat`/`$(<file)` per la stampa — e
# `$(<file)` taglierebbe anche l'a capo finale, mentre lo stdout deve essere
# identico al file byte per byte.
#
# Robustezza: nessun set -e, sempre exit 0 — una regola che non arriva non deve
# rompere la sessione.

script_path="${BASH_SOURCE[0]}"
case "$script_path" in
    */*) script_dir="${script_path%/*}" ;;
    *)   script_dir="." ;;
esac
restamp_file="${script_dir}/../../docs/restamp.md"

[ -f "$restamp_file" ] || exit 0

# Il tetto di caratteri limita il costo sui messaggi lunghi: `read` da una pipe legge
# un byte per chiamata, e la decisione dipende solo dall'inizio del `prompt`, che nel
# payload viene dopo i soli campi brevi (id e path). Un `prompt` oltre il tetto non
# matcha e riceve il restamp, che e' la direzione giusta del guasto.
stdin_prefix=''
if [ ! -t 0 ]; then
    IFS= read -r -d '' -n 16384 -t 1 stdin_prefix || true
fi

case "$stdin_prefix" in
    *'"prompt":"<task-notification>\n<task-id>'*) exit 0 ;;
    *'"prompt":"<agent-message from=\"'*)         exit 0 ;;
    *'"prompt":"<cross-session-message from=\"'*) exit 0 ;;
esac

restamp_text=''
IFS= read -r -d '' restamp_text < "$restamp_file" || true
printf '%s' "$restamp_text"
exit 0
