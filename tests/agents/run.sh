#!/usr/bin/env bash

# =============================================================================
# run.sh — esegue i casi del banco agent
# Usage: tests/agents/run.sh [--smoke] [--case <nome>] [--giri N]
# =============================================================================
#
# Per ogni caso: unpack+hydrate in una temporanea SUA (i casi non condividono
# stato: un writer sporca il tree e inquinerebbe il validator), spawn del
# subagent via `claude -p` (solo lanciatore), poi il GIUDIZIO fuori processo —
# uno script legge il transcript del subagent e asserisce sull'envelope.
#
# Due livelli, tenuti separati o un errore di forma passa per variabilita' del
# modello: FORMA (envelope JSON valido, campi obbligatori — deterministico,
# varianza zero) e MERITO (perimetro, tollerante — assert.sh del caso).
#
# Verde di un caso di merito: --giri 3, tutti dentro il perimetro (DoD). Il
# default e' 1 giro: serve a iterare sull'infrastruttura senza pagare tre
# spawn a modifica.
#
# Su rosso la cartella del caso RESTA, col path stampato. Su verde si cancella.
#
# --smoke: solo i casi con SMOKE=1 nel case.conf (uno per agent). Il router
# costa minuti e centinaia di k-token per file inbox, l'helper spiccioli: una
# suite che li tratta uguale non si lancia mai.
# =============================================================================

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/bench-lib.sh"

SMOKE=0; ONLY_CASE=""; GIRI=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --smoke)  SMOKE=1; shift ;;
        --case)   ONLY_CASE="$2"; shift 2 ;;
        --giri)   GIRI="$2"; shift 2 ;;
        *) echo "arg ignoto: $1" >&2; exit 2 ;;
    esac
done

command -v claude >/dev/null || { echo "[bench] claude CLI richiesto" >&2; exit 1; }
command -v jq >/dev/null || { echo "[bench] jq richiesto" >&2; exit 1; }

# elenco dei casi dal tar, senza estrarre tutto
LIST_DIR="$(mktemp -d)"
tar -xf "$TAR" -C "$LIST_DIR" ./cases 2>/dev/null || tar -xf "$TAR" -C "$LIST_DIR" cases
CASES=()
for conf in "$LIST_DIR"/cases/*/case.conf; do
    [[ -f "$conf" ]] || continue
    nome="$(basename "$(dirname "$conf")")"
    [[ -n "$ONLY_CASE" && "$nome" != "$ONLY_CASE" ]] && continue
    if [[ "$SMOKE" -eq 1 ]]; then
        grep -q '^SMOKE=1' "$conf" || continue
    fi
    CASES+=("$nome")
done
rm -rf "$LIST_DIR"
[[ ${#CASES[@]} -gt 0 ]] || { echo "[bench] nessun caso selezionato" >&2; exit 1; }

echo "[bench] casi: ${CASES[*]}  ·  giri: $GIRI  ·  lanciatore: $BENCH_MAIN_MODEL"

KEPT=()
for nome in "${CASES[@]}"; do
    for giro in $(seq 1 "$GIRI"); do
        FIX="$(mktemp -d "/tmp/loom-agent-run.${nome}.g${giro}.XXXXXX")"
        bench_unpack "$FIX" 1 "$nome" || { b_ko "$nome/g$giro: unpack"; KEPT+=("$FIX"); continue; }
        CASO="$FIX/cases/$nome"
        # shellcheck source=/dev/null
        # unset prima del source: il subshell eredita le variabili del giro
        # precedente, e un case.conf senza PRE lascerebbe quello del caso prima
        AGENT="$(unset AGENT; source "$CASO/case.conf"; echo "${AGENT:-}")"
        PRE="$(unset PRE; source "$CASO/case.conf"; echo "${PRE:-}")"

        # pre-hook del caso (es. applicare la patch che il validator misura)
        if [[ -n "$PRE" ]]; then
            ( cd "$FIX" && bash "$CASO/$PRE" ) || { b_ko "$nome/g$giro: pre-hook"; KEPT+=("$FIX"); continue; }
        fi

        SID="$(uuidgen)"
        echo "── $nome · giro $giro · agent bench-$AGENT · sid $SID"
        bench_spawn "$FIX" "bench-$AGENT" "$CASO/prompt.md" "$SID" || true

        # il lanciatore puo' "normalizzare" il nome e invocare l'agent omonimo
        # del plugin in cache: misureremmo la cache credendo di misurare il
        # sorgente — si asserisce PRIMA di leggere qualunque envelope
        SPAWNED="$(bench_spawned_type "$FIX" "$SID")"
        if [[ "$SPAWNED" != "bench-$AGENT" ]]; then
            b_ko "$nome/g$giro: il lanciatore ha invocato '$SPAWNED' invece di 'bench-$AGENT'"
            KEPT+=("$FIX"); continue
        fi

        TRX="$(bench_subagent_transcript "$FIX" "$SID")" || TRX=""
        if [[ -z "$TRX" ]]; then
            b_ko "$nome/g$giro: transcript del subagent non trovato" \
                 "atteso sotto ~/.claude/projects/$(bench_munge_cwd "$FIX")/$SID/subagents/"
            KEPT+=("$FIX"); continue
        fi

        ENV_FILE="$FIX/.envelope.json"
        bench_envelope "$TRX" > "$ENV_FILE"

        # ── FORMA, comune a ogni caso: l'envelope e' JSON valido ──
        if ! jq -e . "$ENV_FILE" >/dev/null 2>&1; then
            b_ko "$nome/g$giro: FORMA — ultimo messaggio non e' un envelope JSON" "$(head -c 300 "$ENV_FILE")"
            KEPT+=("$FIX"); continue
        fi
        b_ok "$nome/g$giro: FORMA — envelope JSON"

        # ── il resto del giudizio e' del caso ──
        FAIL_BEFORE=$BENCH_FAIL
        # shellcheck source=/dev/null
        source "$CASO/assert.sh" "$ENV_FILE" "$FIX" "$TRX"
        if [[ $BENCH_FAIL -gt $FAIL_BEFORE ]]; then
            KEPT+=("$FIX")
        else
            rm -rf "$FIX"
        fi
    done
done

echo
echo "── ${BENCH_PASS} ok · ${BENCH_FAIL} fail ──"
if [[ ${#KEPT[@]} -gt 0 ]]; then
    echo "cartelle mantenute per la diagnosi:"
    printf '  %s\n' "${KEPT[@]}"
fi
[[ $BENCH_FAIL -eq 0 ]] || exit 1
exit 0
