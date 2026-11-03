#!/usr/bin/env bash

# =============================================================================
# project-config.sh — i blocchi di progetto che le skill leggono da
#                     .claude/loom-works.json: taskFields e hooks
# Usage: project-config.sh fields
#        project-config.sh hooks <deliverableDone|taskDone>
#        project-config.sh match <key> <valore>
# =============================================================================
#
# Gemello di scripts/utils/docs-root.sh: serve al markdown delle skill, che può
# invocare un comando ma non sourcare una libreria bash. Legge il file del
# progetto in cui gira (PROJECT_ROOT, poi la risalita di lw_find_project_root),
# quindi non dipende da nessuna preferenza globale.
#
# ── Output ──────────────────────────────────────────────────────────────────
#   fields   una riga per campo, nell'ordine di dichiarazione:
#              FIELD|<key>|<inherit|->|<ask>
#            seguita, se il campo ha un pattern, da:
#              PATTERN|<key>|<regex>
#            Il testo libero è sempre l'ultimo campo, perché può contenere `|`
#            (una key no: cfg_validate_blocks lo rifiuta). Gli a capo dentro
#            `ask` diventano spazi.
#   hooks    una riga per skill, nell'ordine di dichiarazione:
#              HOOK|<n>|<skill>
#   match    MATCH=1 se il valore soddisfa il pattern del campo, MATCH=0 se no.
#            Il vuoto passa sempre, e un campo senza pattern accetta tutto. La
#            regex si valuta con test() di jq, cioè nel dialetto dichiarato
#            dallo schema (Oniguruma, dove `\d` funziona): il chiamante non la
#            valuta da sé, o la valuterebbe in un dialetto diverso.
#
# Blocco assente (o file assente) → nessuna riga, exit 0: un progetto che non
# dichiara niente ha l'header e il ciclo di vita di sempre.
#
# ── Validazione ─────────────────────────────────────────────────────────────
# Prima di stampare qualunque cosa il lettore valida ENTRAMBI i blocchi con
# cfg_validate_blocks (lib-config.sh), la stessa funzione di cfg_validate.
# Non basta che lo faccia cfg_validate: gira solo a init (register.sh) e al
# refresh di compass, e register.sh esce prima di validare quando dconf manca —
# su Windows non gira mai. Un blocco invalido → exit 1, col messaggio che
# nomina il valore: create-task scrive l'header senza campi, run-task e
# checkpoint-task non invocano hook e lo dicono.
#
# ── jq ──────────────────────────────────────────────────────────────────────
# I due blocchi sono annidati (taskFields è una lista di oggetti), e la regex
# con cui lw_docs_root ripiega senza jq legge solo un campo piatto. Senza jq:
#   - il file non nomina "taskFields" né "hooks" → nessuna riga, exit 0
#     (il fatto si prova sul testo, senza parse);
#   - il file li nomina → exit 1. Uno stampato vuoto lascerebbe nascere task
#     senza campi e mai invocare gli hook, con exit 0: il guasto silenzioso che
#     lw_docs_root descrive per docsRoot.
# Lo stesso vale per un JSON malformato: vuoto se non nomina i blocchi, exit 1
# se li nomina.
#
# Exit: 0 ok · 1 config illeggibile, invalida, o jq assente con blocchi
#       dichiarati · 2 uso sbagliato, o `match` su una key non dichiarata
# =============================================================================

set -uo pipefail

usage() {
    echo "Usage: project-config.sh fields | hooks <deliverableDone|taskDone> | match <key> <valore>" >&2
    exit 2
}

CMD="${1:-}"
[[ $# -gt 0 ]] && shift
case "$CMD" in
    fields) [[ $# -eq 0 ]] || usage ;;
    hooks)
        [[ $# -eq 1 ]] || usage
        case "$1" in
            deliverableDone|taskDone) ;;
            *) echo "ERROR: evento sconosciuto: $1 (ammessi: deliverableDone, taskDone)" >&2; exit 2 ;;
        esac
        ;;
    match) [[ $# -eq 2 ]] || usage ;;
    *) usage ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-config.sh
source "${SCRIPT_DIR}/lib-config.sh"

undeclared() {  # <key>
    echo "ERROR: campo non dichiarato in taskFields: $1" >&2
    exit 2
}

ROOT="$(lw_find_project_root)"
CFG="$(cfg_file_path "$ROOT")"

if [[ ! -f "$CFG" ]]; then
    [[ "$CMD" == match ]] && undeclared "$1"
    exit 0
fi

# Presenza dei blocchi provata sul testo, senza jq: decide se un vuoto è un
# fatto o un'ignoranza.
JSON=""
IFS= read -r -d '' JSON < "$CFG" || true
RE_DECLARED='"(taskFields|hooks)"[[:space:]]*:'
if [[ ! "$JSON" =~ $RE_DECLARED ]]; then
    [[ "$CMD" == match ]] && undeclared "$1"
    exit 0
fi

command -v jq >/dev/null 2>&1 || {
    echo "ERROR: jq richiesto per leggere taskFields/hooks: $CFG" >&2
    exit 1
}
cfg_validate_blocks "$CFG" || exit 1

# jq nativo di Windows scrive CRLF: il \r si toglie riga per riga.
lf() {
    local l
    while IFS= read -r l || [[ -n "$l" ]]; do
        printf '%s\n' "${l%$'\r'}"
    done
}

case "$CMD" in
    fields)
        jq -r '
            (.taskFields // [])[]
            | "FIELD|\(.key)|\(if .inherit == true then "inherit" else "-" end)|\((.ask // "") | gsub("[\\r\\n]+"; " "))",
              (select((.pattern // "") != "") | "PATTERN|\(.key)|\(.pattern)")
        ' "$CFG" | lf
        ;;
    hooks)
        jq -r --arg ev "$1" '(.hooks[$ev] // []) | to_entries[] | "HOOK|\(.key + 1)|\(.value)"' "$CFG" | lf
        ;;
    match)
        RES="$(jq -r --arg k "$1" --arg v "$2" '
            [ (.taskFields // [])[] | select(.key == $k) ]
            | if length == 0 then "UNDECLARED"
              else (.[0].pattern // "") as $p
                | if $v == "" or $p == "" or ($v | test($p)) then "MATCH=1" else "MATCH=0" end
              end
        ' "$CFG")"
        RES="${RES%$'\r'}"
        [[ "$RES" == UNDECLARED ]] && undeclared "$1"
        echo "$RES"
        ;;
esac
