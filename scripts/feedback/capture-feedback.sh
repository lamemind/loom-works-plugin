#!/bin/bash

# =============================================================================
# capture-feedback.sh - Cattura la conversazione corrente e la deposita in loom
# Usage: capture-feedback.sh <annotazione libera...>
# Env:   CLAUDE_CODE_SESSION_ID (obbligatoria)  LOOM_WORKS_DIR (override)
# =============================================================================
#
# Impacchetta la sessione Claude Code corrente in una cartella-feedback dentro
# il repo loom-works, dove viene poi analizzata (`/feedback-review`).
#
# Payload prodotto: <loom>/<docsRoot>/feedbacks/FB-YYYYMMDDHHMMSS/
#   meta.json        annotazione utente + sender + sessione + versione plugin
#   transcript.jsonl copia integrale del jsonl al momento della cattura
#
# NON diagnostica: chi ha prodotto l'output non può analizzarlo (stesso contesto
# → razionalizza). Qui si raccoglie e si spedisce, punto.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/lib.sh
source "${SCRIPT_DIR}/../utils/lib.sh"

WARN_BYTES=$((20 * 1024 * 1024))

# ---- 1. Annotazione ---------------------------------------------------------

ANNOTATION="$*"
if [[ -z "${ANNOTATION// /}" ]]; then
    echo "  Usage: capture-feedback.sh <annotazione libera>" >&2
    die "annotazione mancante"
fi

# ---- 2. Sessione corrente ---------------------------------------------------

SID="${CLAUDE_CODE_SESSION_ID:-}"
[[ -n "$SID" ]] || die "sessione non identificabile (\$CLAUDE_CODE_SESSION_ID vuota)"

# Ricerca per id esatto su tutte le project-dir: il nome della dir è il cwd di
# APERTURA sessione con i non-alnum sostituiti da dash, non ricostruibile dal
# cwd corrente (può essere una subdir, e la trasformazione perde informazione).
TRANSCRIPT="$(find "${HOME}/.claude/projects" -maxdepth 2 -type f -name "${SID}.jsonl" -print -quit 2>/dev/null || true)"
[[ -n "$TRANSCRIPT" ]] || die "transcript non trovato per la sessione ${SID} sotto ~/.claude/projects/"

TRANSCRIPT_BYTES="$(stat -c %s "$TRANSCRIPT")"

# ---- 3. Destinazione: loom-works --------------------------------------------

LOOM_DIR="${LOOM_WORKS_DIR:-}"
if [[ -z "$LOOM_DIR" ]]; then
    if command -v dconf >/dev/null 2>&1; then
        LOOM_DIR="$(dconf read /org/lamemind/loom/projects/loom-works/dir 2>/dev/null | sed "s/^'//; s/'$//")"
    fi
fi

if [[ -z "$LOOM_DIR" ]]; then
    {
        echo "  Provato: \$LOOM_WORKS_DIR (vuota) e dconf read /org/lamemind/loom/projects/loom-works/dir (nessun valore)."
        echo "  Fix: esporta LOOM_WORKS_DIR=/path/di/loom-works, oppure registra loom-works con 'loom-works init'."
    } >&2
    die "dir di loom-works non risolvibile"
fi
[[ -d "$LOOM_DIR" ]] || die "dir di loom-works risolta ma inesistente: ${LOOM_DIR}"

LOOM_CFG="${LOOM_DIR}/.claude/loom-works.json"
LOOM_DOCS_ROOT="docs"
if [[ -f "$LOOM_CFG" ]]; then
    LOOM_DOCS_ROOT="$(jq -r '.docsRoot // "docs"' "$LOOM_CFG")"
fi

# ---- 4. Sender ---------------------------------------------------------------

SENDER_ROOT="$(lw_find_project_root)"
SENDER_ID=""
if [[ -f "${SENDER_ROOT}/.claude/loom-works.json" ]]; then
    SENDER_ID="$(jq -r '.id // empty' "${SENDER_ROOT}/.claude/loom-works.json")"
fi

PLUGIN_VERSION=""
PLUGIN_MANIFEST="${SCRIPT_DIR}/../../.claude-plugin/plugin.json"
[[ -f "$PLUGIN_MANIFEST" ]] && PLUGIN_VERSION="$(jq -r '.version // empty' "$PLUGIN_MANIFEST")"

# ---- 5. Scrittura payload ----------------------------------------------------

HANDLE="FB-$(date +%Y%m%d%H%M%S)"
FB_DIR="${LOOM_DIR}/${LOOM_DOCS_ROOT}/feedbacks/${HANDLE}"

[[ -e "$FB_DIR" ]] && die "cartella feedback già esistente: ${FB_DIR}"
mkdir -p "$FB_DIR"

cp "$TRANSCRIPT" "${FB_DIR}/transcript.jsonl"

jq -n \
    --arg handle "$HANDLE" \
    --arg capturedAt "$(date -Iseconds)" \
    --arg annotation "$ANNOTATION" \
    --arg senderRoot "$SENDER_ROOT" \
    --arg senderId "$SENDER_ID" \
    --arg sessionId "$SID" \
    --arg source "$TRANSCRIPT" \
    --argjson bytes "$TRANSCRIPT_BYTES" \
    --arg pluginVersion "$PLUGIN_VERSION" \
    '{
        handle: $handle,
        capturedAt: $capturedAt,
        annotation: $annotation,
        sender: { projectRoot: $senderRoot, projectId: $senderId },
        session: { id: $sessionId, transcriptSource: $source, bytes: $bytes },
        plugin: { version: $pluginVersion }
    }' > "${FB_DIR}/meta.json"

# ---- 6. Report ---------------------------------------------------------------

if (( TRANSCRIPT_BYTES > WARN_BYTES )); then
    echo "WARNING: transcript pesante ($(( TRANSCRIPT_BYTES / 1024 / 1024 )) MB) — copiato comunque, in chiaro." >&2
fi

echo "-> feedback: ${HANDLE}"
echo "-> path:     ${FB_DIR}"
echo "-> sessione: ${SID} ($(( TRANSCRIPT_BYTES / 1024 )) KB)"
echo "-> sender:   ${SENDER_ROOT}"
