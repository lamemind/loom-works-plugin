#!/usr/bin/env bash
# announce-state.sh — annuncia lo stato del turno a loom-compass, se c'è.
#
# Wrapper degli hook di stato (UserPromptSubmit → running, Notification → ask,
# Stop → done, SessionEnd → end). Il lavoro vero lo fa il bridge `compass`, che
# NON vive nel plugin: parla D-Bus, GNOME e Ptyxis, cioè coupling di OS e
# terminale, che si isola nei consumer invece di entrare nel contratto di
# famiglia. Qui sta solo il wiring, che prima era ricopiato a mano in
# ~/.claude/settings.json su ogni macchina.
#
# GUARDIA DI PRESENZA: il plugin arriva anche a chi non ha compass né GNOME. Senza
# il bridge questo script è inerte — è la condizione che rende distribuibile un
# hook che invoca un comando non garantito.
#
# STDOUT MUTO, sempre: su UserPromptSubmit lo stdout di un hook entra nel contesto
# del modello e consuma il tetto di iniezione. `gdbus call` stampa `()` quando
# riesce, ed è esattamente il rumore da non iniettare.
#
# EXIT 0 SEMPRE: un hook che fallisce disturba il turno, e qui non c'è nessun
# fallimento che valga il disturbo.

state="${1:-}"
[ -n "$state" ] || exit 0

command -v compass >/dev/null 2>&1 || exit 0

compass "$state" >/dev/null 2>&1 || true
exit 0
