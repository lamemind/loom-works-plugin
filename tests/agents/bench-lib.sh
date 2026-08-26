#!/usr/bin/env bash

# =============================================================================
# bench-lib.sh — helper condivisi del banco agent (sourced da unpack.sh/run.sh)
# =============================================================================
#
# Il banco misura I SORGENTI, mai la cache pubblicata: gli agent si definiscono
# a livello progetto (.claude/agents/ della fixture), copiati dall'hydrate dal
# build del cappello. E' cio' che rende possibile il collaudo pre-publish; che
# il publish porti gli stessi file si verifica una volta, sul progetto vero.
#
# L'ordine dell'hydrate e' parte del contratto: estrai → copia i sorgenti →
# git init e commit → POI colloca i casi. La guardia sul working tree scarta i
# file inbox non committati, quindi un caso messo prima del commit collauda un
# ramo diverso da quello previsto. Ogni caso dichiara nel proprio case.conf se
# il suo materiale resta committato o untracked.
#
# NON si packa mai una cartella idratata: dopo l'hydrate contiene .git, i
# sorgenti copiati e cio' che il run ha scritto — un pack da li' porta dentro
# roba derivata e il banco successivo parte da uno stato che nessuno ha deciso.
# =============================================================================

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${BENCH_DIR}/../.." && pwd)"
CAPPELLO="$(cd "${PLUGIN_ROOT}/.." && pwd)"
TAR="${BENCH_DIR}/fixture.tar"

# Il modello del LANCIATORE (claude -p): fa solo da tramite per il Task tool,
# quindi il piu' economico. Il modello del subagent sta nel frontmatter del suo
# body. Pinnato per id: il default del CLI cambia fra versioni e il banco
# misurerebbe un altro modello senza dirlo.
BENCH_MAIN_MODEL="${BENCH_MAIN_MODEL:-claude-haiku-4-5-20251001}"

bench_unpack() {  # <dest> <hydrate 0/1> [solo-caso]
    local dest="$1" hydrate="$2" solo_caso="${3:-}"
    [[ -f "$TAR" ]] || { echo "[bench] fixture.tar assente: $TAR" >&2; return 1; }
    mkdir -p "$dest"
    tar -xf "$TAR" -C "$dest"

    if [[ "$hydrate" -eq 1 ]]; then
        # sorgenti vivi: gli agent BUILDATI (template+frammenti gia' assemblati
        # dal cappello) e le primitive bash che i guardiani del giudice usano.
        # Gli agent entrano col prefisso `bench-` nel nome E nel filename: il
        # plugin installato porta agent OMONIMI in cache (magari di una versione
        # vecchia), e su un nome conteso il Task puo' risolvere quello sbagliato
        # — il banco misurerebbe la cache credendo di misurare il sorgente.
        local a base
        mkdir -p "$dest/.claude/agents"
        for a in "$PLUGIN_ROOT"/agents/doc-*.md; do
            base="$(basename "$a")"
            sed "0,/^name: /s/^name: /name: bench-/" "$a" > "$dest/.claude/agents/bench-${base}"
        done
        mkdir -p "$dest/.plugin-scripts/docs" "$dest/.plugin-scripts/utils"
        cp "$PLUGIN_ROOT"/scripts/docs/*.sh "$dest/.plugin-scripts/docs/"
        cp "$PLUGIN_ROOT"/scripts/utils/lib.sh "$dest/.plugin-scripts/utils/"

        git -C "$dest" init -q
        git -C "$dest" config user.name bench
        git -C "$dest" config user.email bench@local
        git -C "$dest" add -A
        git -C "$dest" commit -qm "fixture idratata"

        # collocazione DOPO il commit, secondo il case.conf; con <solo-caso> si
        # colloca il materiale di QUEL caso soltanto — il registro di un caso
        # non deve comparire nell'inbox di un altro
        local conf caso
        for conf in "$dest"/cases/*/case.conf; do
            [[ -f "$conf" ]] || continue
            caso="$(dirname "$conf")"
            [[ -n "$solo_caso" && "$(basename "$caso")" != "$solo_caso" ]] && continue
            # shellcheck source=/dev/null
            ( source "$conf"
              if [[ -n "${COLLOCA_SRC:-}" && -n "${COLLOCA_DEST:-}" ]]; then
                  mkdir -p "$dest/$(dirname "$COLLOCA_DEST")"
                  cp "$caso/$COLLOCA_SRC" "$dest/$COLLOCA_DEST"
                  if [[ "${COLLOCA_COMMIT:-1}" -eq 1 ]]; then
                      git -C "$dest" add -- "$COLLOCA_DEST"
                      git -C "$dest" commit -qm "caso: $COLLOCA_DEST"
                  fi
              fi )
        done
    fi
    return 0
}

# --- transcript del subagent --------------------------------------------------
# Il giudizio NON lo da' l'orchestratore: il verdetto lo prende chi legge il
# transcript del subagent, fuori dal processo che ha eseguito. Un modello che
# giudica il proprio lavoro e' compiacente.

bench_munge_cwd() {  # <cwd> → il segmento directory usato da ~/.claude/projects/
    printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'
}

bench_subagent_transcript() {  # <cwd> <session-id> → path dell'agent-*.jsonl piu' recente
    local dir="$HOME/.claude/projects/$(bench_munge_cwd "$1")/$2/subagents"
    [[ -d "$dir" ]] || return 1
    ls -t "$dir"/agent-*.jsonl 2>/dev/null | head -1
}

bench_envelope() {  # <transcript.jsonl> → l'envelope JSON dell'ultimo messaggio assistant
    # ultimo testo assistant; l'envelope e' l'ULTIMO blocco ```json fenced se
    # presente (i modelli antepongono prosa nonostante il contratto), altrimenti
    # il testo dal primo `{` all'ultima `}`
    local txt
    txt="$(jq -rs '
        [ .[] | select(.type == "assistant")
              | .message.content
              | if type == "array" then (map(select(.type == "text") | .text) | join("\n")) else . end
              | select(. != null and . != "") ]
        | last // empty
    ' "$1" 2>/dev/null)"
    local fenced
    fenced="$(awk '
        /^```(json)?[[:space:]]*$/ { if (infence) { infence = 0; next } infence = 1; buf = ""; next }
        infence { buf = buf $0 "\n" }
        END { printf "%s", buf }
    ' <<< "$txt")"
    if [[ -n "$fenced" ]]; then
        printf '%s\n' "$fenced"
    else
        # dal primo { all'ultima }
        printf '%s\n' "$txt" | sed -n '/{/,$p' | tac | sed -n '/}/,$p' | tac
    fi
}

# --- lanciatore ---------------------------------------------------------------

bench_spawn() {  # <fixture-dir> <agent> <prompt-file> <session-id> [timeout-sec]
    local fixture="$1" agent="$2" prompt_file="$3" sid="$4" tmo="${5:-900}"
    local prompt
    prompt="$(cat "$prompt_file")"
    ( cd "$fixture" && timeout "$tmo" claude -p \
        --model "$BENCH_MAIN_MODEL" \
        --session-id "$sid" \
        --dangerously-skip-permissions \
        "Invoca il tool Task con subagent_type ESATTAMENTE \"${agent}\" — il carattere per carattere conta. Nella lista degli agent ne esistono altri con nomi simili (es. con prefisso \"loom-works:\"): sono QUELLI SBAGLIATI, non li usare per nessuna ragione. Passa al Task ESATTAMENTE questo prompt, senza aggiungere niente:

${prompt}

Non fare nessun'altra azione. Quando il subagent termina rispondi solo: done" \
        >/dev/null 2>&1 )
}

bench_spawned_type() {  # <cwd> <session-id> → il subagent_type davvero invocato
    jq -r 'select(.type=="assistant") | .message.content
           | if type=="array" then (map(select(.type=="tool_use")) | .[] | .input.subagent_type // empty) else empty end' \
        "$HOME/.claude/projects/$(bench_munge_cwd "$1")/$2.jsonl" 2>/dev/null | head -1
}

# --- asserzioni ---------------------------------------------------------------

BENCH_PASS=0; BENCH_FAIL=0
b_ok() { BENCH_PASS=$((BENCH_PASS+1)); printf 'ok   %s\n' "$1"; }
b_ko() { BENCH_FAIL=$((BENCH_FAIL+1)); printf 'FAIL %s\n' "$1"; [[ -n "${2:-}" ]] && printf '     %s\n' "$2"; }

b_json_valid() {  # <name> <file>
    if jq -e . "$2" >/dev/null 2>&1; then b_ok "$1"; else b_ko "$1" "non e' JSON valido: $(head -c 200 "$2")"; fi
}
