#!/usr/bin/env bash

# =============================================================================
# adr.sh — il nome di prima di scarti.sh: inoltra argomenti, stdin ed exit
# Usage: come scarti.sh, con gli stessi sottocomandi
# =============================================================================
#
# Il registro degli scarti si chiamava registro ADR e stava in adr/ della
# docs-root. Il comando vero e' scarti.sh, nella stessa cartella; questo file
# resta perche' la regia (checkpoint-mandate) chiama `adr.sh cerca` per nome e la
# regia non si modifica. Senza questo file la regia non troverebbe il comando,
# leggerebbe un exit diverso da 0 come «nessuno scarto» e riporterebbe
# segnalazioni gia' scartate, senza un errore visibile.
#
# `exec` e non una chiamata: il processo diventa scarti.sh, e exit code, stdin e
# stdout sono i suoi senza una riga di codice qui che possa alterarli.
# =============================================================================

exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scarti.sh" "$@"
