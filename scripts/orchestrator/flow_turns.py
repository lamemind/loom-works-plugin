"""
flow_turns — l'esito di un turno headless, letto dallo script del flusso.

Classificazione a lista bianca. Un passo è chiuso solo su due prove insieme:
la riga fissa che la skill scrive a fine turno e lo stato atteso su disco.
Tutto il resto sveglia l'orchestrator: domande, segnalazioni, un preflight con
sole proposte, una premessa decaduta, un errore, un permesso negato, ogni testo
che lo script non riconosce. Un testo riconosciuto per esclusione — «non vedo
domande, quindi è chiuso» — sbaglia in silenzio alla prima skill che cambia
forma; uno riconosciuto per inclusione, nel caso peggiore, sveglia
l'orchestrator una volta di troppo.

Le righe fisse:

  ✅ Preflight completato             preflight-task, decisioni congelate
  🛫 Nessuna ambiguità rilevata       preflight-task, nessuna decisione
  🚦 Segnalazioni — nessuna           run-task e checkpoint-task, nessuna
                                      segnalazione nel report
  ✅ Risposte registrate              un turno che ha registrato le risposte
                                      dell'orchestrator alle segnalazioni
  ❓ Domanda per l'orchestrator       un turno che chiude su una domanda: vince
                                      su ogni altra riga

Le ultime due le chiede la riga dell'organigramma (`inject-orchestrator.sh`) a
ogni conversazione aperta dall'orchestrator.

Il genere di un turno lo dice il suo prompt: il primo turno ha l'azione con cui
`loom-deck-headless open` l'ha aperto, un turno successivo lo slash command che
porta (`/loom-works:checkpoint-task`), o è una risposta. Una risposta si legge
come il passo che segue: dopo un preflight è un preflight, dopo un checkpoint
un checkpoint, dopo un run un run.
"""

import re

QUESTION_LINE = "❓ Domanda per l'orchestrator"
ANSWERS_LINE = "✅ Risposte registrate"
PREFLIGHT_DONE = ("✅ Preflight completato", "🛫 Nessuna ambiguità rilevata")
SIGNALS_NONE = re.compile(r"^🚦\s*Segnalazioni\s*[—–-]+\s*nessuna\.?$")
QUESTION_ITEM = re.compile(r"^(?:[-*]\s*)?D\d+\b")
PROPOSAL_ITEM = re.compile(r"^(?:[-*]\s*)?P\d+\b")
SIGNAL_ITEM = re.compile(r"^(?:[-*]\s*)?S\d+\b")
SKILL_PROMPTS = (("/loom-works:checkpoint-task", "checkpoint"), ("/loom-works:preflight-task", "preflight"),
                 ("/loom-works:run-task", "run"))
STEP_KINDS = ("preflight", "run", "checkpoint")


def plain_lines(text):
    """Le righe del testo senza la forma markdown che non cambia il senso:
    grassetto, codice in linea, spazi in testa e in coda."""
    lines = []
    for line in (text or "").splitlines():
        cleaned = line.replace("**", "").replace("`", "").strip()
        if cleaned:
            lines.append(cleaned)
    return lines


def has_line(text, fixed):
    return any(line.startswith(fixed) for line in plain_lines(text))


def signals_none(text):
    return any(SIGNALS_NONE.match(line) for line in plain_lines(text))


def preflight_done(text):
    return any(has_line(text, fixed) for fixed in PREFLIGHT_DONE)


def count_items(text, pattern):
    return sum(1 for line in plain_lines(text) if pattern.match(line))


def turn_genre(state):
    """Il genere del turno dallo stato headless del deck: `preflight`, `run`,
    `checkpoint` o `risposta`."""
    prompt = state.get("prompt") or ""
    for command, genre in SKILL_PROMPTS:
        if command in prompt:
            return genre
    if state.get("turn") == 1 and state.get("kind") in STEP_KINDS:
        return state["kind"]
    return "risposta"


class Verdict:
    """L'esito della lettura: `chiuso` (il passo è finito), `checkpoint` (il
    run è pulito, il ciclo passa al checkpoint) o `risveglio` col motivo."""

    def __init__(self, outcome, reason=""):
        self.outcome = outcome
        self.reason = reason

    def __repr__(self):
        return f"Verdict({self.outcome!r}, {self.reason!r})"


def wake(reason):
    return Verdict("risveglio", reason)


def classify(step_kind, genre, last_genre, outcome_class, text, facts):
    """L'esito di un turno finito.

    `step_kind` il passo aperto dallo script (`preflight`, `run`,
    `checkpoint`); `genre` quello del turno; `last_genre` quello dell'ultimo
    turno letto sullo stesso passo, che decide come si legge una risposta;
    `outcome_class` la classe dell'esito di `loom-deck-headless status`;
    `facts` le prove su disco: `preflight` (`ok`, `none`, `decaduta`),
    `scope_done` (i DLV del perimetro eseguibile del run tutti spuntati),
    `progress_grew` (un `### Avanzamento` in più dal checkpoint chiesto)."""
    if outcome_class == "errore":
        return wake("errore")
    if outcome_class == "permesso negato":
        return wake("permesso negato")
    if outcome_class != "turno chiuso":
        return wake("non classificato")
    if has_line(text, QUESTION_LINE):
        return wake("domanda")
    effective = genre
    if genre == "risposta":
        effective = "checkpoint" if last_genre == "checkpoint" else step_kind
    if effective == "preflight":
        if preflight_done(text) and facts.get("preflight") == "ok":
            return Verdict("chiuso")
        if facts.get("preflight") == "decaduta" or "premessa decaduta" in (text or ""):
            return wake("premessa decaduta")
        if count_items(text, QUESTION_ITEM):
            return wake("domande")
        if count_items(text, PROPOSAL_ITEM):
            return wake("proposte")
        return wake("non classificato")
    clean_line = signals_none(text) or (genre == "risposta" and has_line(text, ANSWERS_LINE))
    if effective == "run":
        if clean_line and facts.get("scope_done"):
            return Verdict("checkpoint")
        if clean_line:
            return wake("dlv aperti")
        if count_items(text, SIGNAL_ITEM):
            return wake("segnalazioni")
        return wake("non classificato")
    if clean_line and facts.get("progress_grew"):
        return Verdict("chiuso")
    if count_items(text, SIGNAL_ITEM):
        return wake("segnalazioni")
    return wake("non classificato")
