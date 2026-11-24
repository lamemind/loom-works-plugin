"""
watch_context — la misura del contesto dell'orchestrator, per il monitor.

L'orchestrator vivi di notifiche del monitor, e ogni notifica è un turno che rilegge
tutto il contesto: il contesto cresce per ore, e oltre una soglia l'orchestrator
chiude il giro e passa le consegne a un orchestrator nuovo. Nessun hook lo misura per
lei: il restamp scatta solo sui prompt umani, e le notifiche non lo sono.

La misura sta nel transcript dell'orchestrator. Ogni risposta del modello porta
`message.usage`, e `input_tokens + cache_read_input_tokens +
cache_creation_input_tokens` è la dimensione del contesto in quel momento. La
dimensione della finestra di contesto non sta nel transcript, solo nel payload
della statusLine: la soglia è quindi in token assoluti, e la passa l'orchestrator
all'armo del monitor (`--context-threshold`).

I gradini sono il 20, 40, 60, 80, 100 e 120% della soglia: il 120% è il secondo
tetto, oltre il quale l'orchestrator passa le consegne anche coi cicli aperti. Un
gradino si dice una volta. Quando una misura ne supera più d'uno insieme — al
primo armo, che trova un orchestrator nato già sopra i primi gradini, o dopo una
risposta molto lunga — esce un evento solo, col gradino più alto, e gli altri
contano come detti: ogni evento costa all'orchestrator un turno.

I gradini detti valgono per un `sessionId`, e stanno nello stato del monitor:
un riarmo dello stesso orchestrator non li ripete. L'orchestrator che riceve le consegne
riarma il monitor sullo stesso file di stato col proprio `sessionId`, e i suoi
gradini ripartono da zero: con gradini globali troverebbe il 100% già detto e
non riceverebbe più nessun evento. Lo stesso vale per un `/clear` dell'orchestrator,
che apre un transcript nuovo e un contesto nuovo.
"""

import json
import os

STEPS = (20, 40, 60, 80, 100, 120)
USAGE_FIELDS = ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens")


def usage_tokens(record):
    """La dimensione del contesto di una risposta del modello, o `None`.

    Contano solo le risposte della conversazione principale: un record di un
    subagent (`isSidechain`) misura il contesto del subagent. Un totale zero è
    un record sintetico (un errore dell'API), che non misura niente."""
    if not isinstance(record, dict) or record.get("type") != "assistant" or record.get("isSidechain"):
        return None
    usage = (record.get("message") or {}).get("usage")
    if not isinstance(usage, dict):
        return None
    total = 0
    for field in USAGE_FIELDS:
        value = usage.get(field)
        if isinstance(value, int) and value > 0:
            total += value
    return total or None


def read_usage(path, offset):
    """L'ultima misura scritta nel transcript dopo `offset`, e l'offset nuovo.

    Legge solo righe complete: un record a metà si rilegge al giro dopo. Il
    filtro sul testo viene prima del parse, perché il transcript di un orchestrator
    pesa megabyte e la prima lettura lo attraversa tutto. Un file più corto
    dell'offset è stato riscritto: si rilegge da capo."""
    try:
        size = os.path.getsize(path)
    except OSError:
        return None, offset
    if size < offset:
        offset = 0
    tokens = None
    with open(path, "rb") as transcript_handle:
        transcript_handle.seek(offset)
        for raw_line in transcript_handle:
            if not raw_line.endswith(b"\n"):
                break
            offset += len(raw_line)
            if b'"usage"' not in raw_line:
                continue
            try:
                record = json.loads(raw_line)
            except ValueError:
                continue
            measured = usage_tokens(record)
            if measured:
                tokens = measured
    return tokens, offset


def next_step(tokens, threshold, said):
    """Il gradino da dire per questa misura, o `None`, e i gradini detti dopo.

    Fra i gradini raggiunti e non ancora detti esce il più alto; tutti quelli
    raggiunti diventano detti."""
    reached = [step for step in STEPS if tokens * 100 >= threshold * step]
    fresh = [step for step in reached if step not in said]
    if not fresh:
        return None, said
    return max(fresh), sorted(set(said) | set(reached))


def thousands(number):
    return f"{number:,}".replace(",", ".")


def step_line(step, tokens, threshold):
    """La riga dell'evento: il gradino in testa, poi la misura. Al 100% e al
    120% dice anche cosa vuol dire per l'orchestrator."""
    line = f"orchestrator 🧠 contesto al {step}% della soglia: {thousands(tokens)} token su {thousands(threshold)}"
    if step == 100:
        line += " — giro in chiusura: passa le consegne a giro chiuso"
    elif step > 100:
        line += " — secondo tetto: passa le consegne anche coi cicli aperti"
    return line


def measure(entry, session_id, transcript, threshold):
    """Una misura del contesto dell'orchestrator: l'entry dello stato aggiornata, la
    riga da emettere e il suo gradino, o `None` e `None`.

    L'entry vale per un `sessionId` e una soglia: con un `sessionId` diverso —
    l'orchestrator che riceve le consegne, un `/clear` — o con un'altra soglia si
    riparte da zero, transcript riletto dall'inizio e nessun gradino detto."""
    if (not isinstance(entry, dict) or entry.get("session_id") != session_id
            or entry.get("threshold") != threshold):
        entry = {"session_id": session_id, "threshold": threshold, "offset": 0, "tokens": None, "said": []}
    tokens, entry["offset"] = read_usage(transcript, entry["offset"])
    if tokens:
        entry["tokens"] = tokens
    if not entry["tokens"]:
        return entry, None, None
    step, entry["said"] = next_step(entry["tokens"], threshold, entry["said"])
    return entry, (step_line(step, entry["tokens"], threshold) if step else None), step
