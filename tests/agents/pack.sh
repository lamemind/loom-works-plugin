#!/usr/bin/env bash

# =============================================================================
# pack.sh — ricostruisce fixture.tar da una cartella di lavoro
# Usage: tests/agents/pack.sh <dir-fixture-nuda>
# =============================================================================
#
# Tar NON compresso: git deltifica bene un tar nudo, mentre un .tar.gz produce
# un blob interamente nuovo a ogni pack. La fixture sta in un archivio e non in
# alberatura per non inquinare le ricerche del repo: un reference/ finto e dei
# file inbox finti sono indistinguibili da doc vera per grep e per gli scanner.
#
# GUARDIA: mai packare una cartella idratata. Una cartella con .git, con i
# sorgenti copiati (.claude/agents/, .plugin-scripts/) o con residui di run
# porta dentro roba derivata, e il banco successivo parte da uno stato che
# nessuno ha deciso.
# =============================================================================

set -euo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${1:?uso: pack.sh <dir-fixture-nuda>}"

[[ -d "$SRC" ]] || { echo "[pack] dir assente: $SRC" >&2; exit 1; }
for spia in .git .claude/agents .plugin-scripts; do
    [[ -e "$SRC/$spia" ]] && { echo "[pack] RIFIUTO: $SRC contiene $spia — e' una cartella idratata, non si packa" >&2; exit 1; }
done

tar -cf "${BENCH_DIR}/fixture.tar" -C "$SRC" .
echo "[pack] scritto: ${BENCH_DIR}/fixture.tar ($(du -h "${BENCH_DIR}/fixture.tar" | cut -f1))"
