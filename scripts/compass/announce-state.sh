#!/usr/bin/env bash
# announce-state.sh — annuncia lo stato del turno: alla conversazione, e a compass.
#
# Wrapper degli hook di stato (UserPromptSubmit → running, Notification → ask,
# Stop → done, SessionEnd → end). Due consumatori indipendenti, in quest'ordine:
#
#   1. la CONVERSAZIONE MARCATA — banner e suono per-conversazione, emessi da qui
#      con notify-send e canberra. Non passano da compass perché il suo canale è
#      keyed sul profilo del PROGETTO e sopprime la ripetizione: due conversazioni
#      dello stesso progetto che finiscono una dietro l'altra producono un solo
#      segnale, e quel segnale non dice quale delle N ha finito.
#   2. il BRIDGE `compass` — badge, pallino e suono di progetto. Il lavoro vero
#      non vive nel plugin: parla D-Bus, GNOME e Ptyxis, cioè coupling di OS e
#      terminale, che si isola nei consumer invece di entrare nel contratto di
#      famiglia. Qui sta solo il wiring, che prima era ricopiato a mano in
#      ~/.claude/settings.json su ogni macchina.
#
# ORDINE VINCOLANTE: la conversazione prima del bridge. `compass ask` poll-a fino
# a 1,5 s il registro dei processi vivi per confermare l'attesa, e il banner
# per-conversazione non deve pagare quell'attesa.
#
# GUARDIA DI PRESENZA su OGNI binario esterno: il plugin arriva anche a chi non ha
# compass, né GNOME, né notify-send, né un riproduttore di suoni. Senza di loro il
# ramo corrispondente è inerte — è la condizione che rende distribuibile un hook
# che invoca comandi non garantiti. I due rami sono indipendenti: senza compass la
# notifica per-conversazione funziona comunque, e viceversa.
#
# STDOUT MUTO, sempre: su UserPromptSubmit lo stdout di un hook entra nel contesto
# del modello e consuma il tetto di iniezione. `gdbus call` stampa `()` quando
# riesce, ed è esattamente il rumore da non iniettare.
#
# EXIT 0 SEMPRE: un hook che fallisce disturba il turno, e qui non c'è nessun
# fallimento che valga il disturbo.

state="${1:-}"
[ -n "$state" ] || exit 0

# Registro dei processi Claude vivi: un file JSON per processo CLI, keyed sul pid
# nel nome. Stessa fonte che legge `bin/compass`, e l'unica che porta il titolo
# della tab.
LIVE_DIR="${HOME}/.claude/sessions"

# Tipi di notifica che NON significano «qualcuno ti aspetta».
#
# L'hook `Notification` è più largo del suo nome: il CLI lo emette anche per
# l'idle a un minuto (`idle_prompt`), per la riuscita di un login
# (`auth_success`) e per la fine di un agent (`agent_completed`). Il campo che li
# distingue arriva sullo STESSO stdin dell'hook, quindi la soppressione non costa
# nessuna osservazione esterna — è la differenza con `bin/compass`, che non legge
# lo stdin e deve poll-are il registro dei processi vivi per la stessa domanda.
#
# CAMPO ASSENTE → SI NOTIFICA. Un CLI più vecchio non lo scrive, e sopprimere
# sull'incertezza toglierebbe `ask` del tutto a chi ha quella versione.
IDLE_TYPES=' idle_prompt auth_success agent_completed '

# ── Marca di priorità: il sidecar per-conversazione ──────────────────────────
#
# `<project-root>/.claude/loom/session-tasks.jsonl`, lo stesso file JSONL
# append-only con cui il deck lega una conversazione a una task. Qui si legge un
# solo campo, `priority` (booleano), con la stessa semantica di lettura del deck:
# LAST-WINS PER CAMPO — vince l'ultimo record che NOMINA il campo, e i record che
# non lo nominano non lo toccano. `false` è quindi una smarcatura esplicita, non
# un'assenza.
_sidecar_priority() {
    local sid="$1" file="$2" v
    if command -v jq >/dev/null 2>&1; then
        v=$(jq -r --arg sid "$sid" \
              'select(.sessionId == $sid and has("priority")) | .priority' \
              "$file" 2>/dev/null | tail -1)
        [ "$v" = "true" ]
        return
    fi
    # Senza jq: il record è un JSON piatto su una riga, quindi i due grep in
    # cascata isolano le righe di QUESTA conversazione che portano il campo, e
    # l'ultima decide. Gli spazi attorno ai due punti sono tollerati perché il
    # file è editabile a mano — è così che si collauda questo ramo.
    grep -E "\"sessionId\"[[:space:]]*:[[:space:]]*\"${sid}\"" "$file" 2>/dev/null \
        | grep -E "\"priority\"[[:space:]]*:" \
        | tail -1 \
        | grep -qE "\"priority\"[[:space:]]*:[[:space:]]*true"
}

# ── Titolo del banner ────────────────────────────────────────────────────────

# Titolo della tab di questa conversazione, dal registro dei processi vivi.
#
# `deck-run` compone il titolo («emoji nome · task [ emoji ] nota») e lo passa a
# `claude --name`; il CLI lo scrive nel proprio file di registro come `name`, che
# è quindi la fonte già pronta — niente da ricomporre qui. L'hook conosce il
# sessionId e non il pid, quindi il match è sul CONTENUTO del file e non sul suo
# nome: lo stesso grep di `bin/compass`.
_live_name_for() {
    local sid="$1" f
    [ -d "$LIVE_DIR" ] || return 0
    f=$(grep -l "\"sessionId\"[[:space:]]*:[[:space:]]*\"${sid}\"" \
            "$LIVE_DIR"/*.json 2>/dev/null | head -1)
    [ -n "$f" ] || return 0
    if command -v jq >/dev/null 2>&1; then
        jq -r '.name // ""' "$f" 2>/dev/null
        return 0
    fi
    grep -o "\"name\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$f" 2>/dev/null \
        | head -1 | sed 's/.*"\([^"]*\)"$/\1/'
}

# Etichetta del progetto dal file di config: `emoji + name`, la stessa formula
# derivata con cui compass titola il cappello.
#
# Serve solo come RIPIEGO del titolo della tab: una sessione lanciata a mano
# senza `--name` non ha nulla nel registro, e un banner che non nomina il
# progetto non dice a cosa appartiene la conversazione.
_project_label() {
    local cfg="$1/.claude/loom-works.json" emoji name
    [ -f "$cfg" ] || return 0
    if command -v jq >/dev/null 2>&1; then
        emoji=$(jq -r '.emoji // ""' "$cfg" 2>/dev/null)
        name=$(jq -r '.name // ""' "$cfg" 2>/dev/null)
    else
        emoji=$(grep -o '"emoji"[[:space:]]*:[[:space:]]*"[^"]*"' "$cfg" 2>/dev/null \
                  | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
        name=$(grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$cfg" 2>/dev/null \
                 | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    fi
    [ -n "$name" ] || return 0
    printf '%s' "${emoji:+${emoji} }${name}"
}

# ── Payload dell'hook (stdin) ────────────────────────────────────────────────

# Lo stdin dell'hook, letto UNA volta sola e con un tetto di attesa.
#
# Prima di T158 questo script non leggeva affatto lo stdin, quindi non poteva
# bloccarsi: la `read` lo reintroduce come rischio, e il tetto lo chiude. `-t 1`
# fa cadere l'attesa dopo un secondo conservando l'input parziale già letto, e
# resta largamente dentro il timeout di 5 s con cui gli hook invocano lo script.
# `-d ''` legge fino a EOF invece che fino al primo newline: il payload è un JSON
# su una riga oggi, ma nulla lo garantisce.
#
# Nessuno legge lo stdin dopo di noi — `compass` non lo tocca — quindi consumarlo
# non toglie niente a valle.
_hook_payload() {
    local p=''
    [ -t 0 ] && return 0   # invocazione a mano da terminale: niente da leggere
    IFS= read -r -d '' -t 1 p || true
    printf '%s' "$p"
}

_notification_type() {
    local payload="$1"
    [ -n "$payload" ] || return 0
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$payload" | jq -r '.notification_type // ""' 2>/dev/null
        return 0
    fi
    printf '%s' "$payload" \
        | grep -oE '"notification_type"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | head -1 | sed 's/.*"\([^"]*\)"$/\1/'
}

# ── Suono ────────────────────────────────────────────────────────────────────

# Stessa cascata di compass (canberra, poi `paplay` sui file del tema
# freedesktop): sulla conversazione marcata questo ding PRENDE IL POSTO di quello
# di compass, quindi deve suonare identico.
#
# In background e con gli fd staccati. Non è solo per non aspettare la fine
# dell'audio: un figlio che tiene aperto lo stdout dell'hook fa aspettare il
# chiamante anche dopo che l'hook è uscito.
_play() {
    local id="$1" oga="/usr/share/sounds/freedesktop/stereo/${1}.oga"
    if command -v canberra-gtk-play >/dev/null 2>&1; then
        ( canberra-gtk-play -i "$id" >/dev/null 2>&1 & ) </dev/null
        return 0
    fi
    if command -v paplay >/dev/null 2>&1 && [ -f "$oga" ]; then
        ( paplay "$oga" >/dev/null 2>&1 & ) </dev/null
    fi
}

# ── Notifica per-conversazione ───────────────────────────────────────────────

# Banner e ding della conversazione marcata, sui soli stati notevoli.
#
# `running` e `end` restano fuori: il primo è l'inizio del turno, che chi lo ha
# lanciato sta già guardando, il secondo è la chiusura di una conversazione che
# non c'è più. Gli stati notevoli sono gli stessi due su cui compass alza il
# badge — `done` e `ask`.
_notify_priority() {
    local state="$1" sid root sidecar ntype body urgency sound title

    case "$state" in
        done|ask) ;;
        *)        return 0 ;;
    esac

    sid="${CLAUDE_CODE_SESSION_ID:-}"
    root="${CLAUDE_PROJECT_DIR:-}"
    [ -n "$sid" ] && [ -n "$root" ] || return 0

    sidecar="${root}/.claude/loom/session-tasks.jsonl"
    [ -f "$sidecar" ] || return 0
    _sidecar_priority "$sid" "$sidecar" || return 0

    if [ "$state" = "ask" ]; then
        ntype=$(_notification_type "$(_hook_payload)")
        if [ -n "$ntype" ] && [[ "$IDLE_TYPES" == *" ${ntype} "* ]]; then
            return 0
        fi
        # `critical` non è enfasi: è ciò che tiene il banner a schermo finché non
        # lo chiudi. La conversazione è bloccata finché non rispondi, quindi un
        # banner che sparisce da sé perde l'unica informazione che porta.
        body='chiede conferma'; urgency='critical'; sound='bell'
    else
        body='ha finito';       urgency='normal';   sound='complete'
    fi

    title=$(_live_name_for "$sid")
    if [ -z "$title" ]; then
        title=$(_project_label "$root")
        title="${title:+${title} · }${sid:0:8}"
    fi

    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u "$urgency" -- "$title" "$body" >/dev/null 2>&1 || true
    fi
    _play "$sound"
}

# ── Esecuzione ───────────────────────────────────────────────────────────────

_notify_priority "$state"

if command -v compass >/dev/null 2>&1; then
    compass "$state" >/dev/null 2>&1 || true
fi

exit 0
