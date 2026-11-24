"""
flow_log — il flusso di un giro su disco, e gli ordini dell'orchestrator.

Due file in `.claude/loom/orchestrator/` del progetto, ignorata da git, ognuno
con un solo scrittore:

  T<id>-flow.jsonl    il flusso: righe solo in coda, ognuna col suo `seq`.
                      Lo scrive il solo processo del flusso (`flow.py run`)
  T<id>-ordini.jsonl  gli ordini dell'orchestrator allo script: `prosegui`,
                      `abbandona`, `tieni`. Lo scrive la sola riga di comando
                      `flow.py <ordine>`, che lancia l'orchestrator

Lo stato corrente del giro non sta in nessun file: si ricava rileggendo il
flusso dall'inizio (`replay`). È così che lo script riparte dopo un crash, e
che `recap` e `wait` leggono il giro senza parlare col processo.

Le righe del flusso, per `tipo`:

  avvio      il processo del flusso è partito: pid, ora d'avvio del processo
  prima      le cifre dei membri al primo avvio del giro: Prog, DLV, AC
  piano      il piano letto: valido con la sua impronta, o non valido e perché
  evento     un evento degli scanner del monitor, con genere e task
  passo      la fotografia intera del passo di un membro, a ogni cambio: l'ultima
             riga `passo` di un membro è il suo passo corrente
  turno      l'esito di un turno headless classificato
  risveglio  una riga per l'orchestrator: lo sveglia `flow.py wait`
  fermo      un membro su cui lo script non apre passi, e perché
  libero     un membro fermo che torna allo script
  ordine     un ordine dell'orchestrator applicato, col suo numero
  guasto     una fonte che si è rotta, senza fermare il processo
  fine       il processo del flusso si è chiuso

Solo libreria standard: il modulo gira dalla cache del plugin su Linux e su
Windows.
"""

import datetime
import json
import os

STATE_DIR = os.path.join(".claude", "loom", "orchestrator")
# Le fasi in cui un passo è ancora aperto. `chiuso` e `abbandonato` lo chiudono.
OPEN_PHASES = ("in apertura", "turno", "attesa", "coda", "checkpoint")
ORDERS = ("prosegui", "abbandona", "tieni")
KEEPALIVE = "keep-alive"


def paths(project_root, head):
    directory = os.path.join(project_root, STATE_DIR)
    return {
        "dir": directory,
        "flow": os.path.join(directory, f"{head}-flow.jsonl"),
        "orders": os.path.join(directory, f"{head}-ordini.jsonl"),
        "watch": os.path.join(directory, f"{head}-watch.json"),
        "lock": os.path.join(directory, f"{head}-flow.lock"),
        "log": os.path.join(directory, f"{head}-flow.log"),
        "state": os.path.join(directory, f"{head}.md"),
    }


def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def parse_iso(text):
    """L'epoch di un `2026-11-24T19:47:39.005Z`, `None` se la stringa non lo è."""
    if not isinstance(text, str):
        return None
    try:
        moment = datetime.datetime.strptime(text[:19], "%Y-%m-%dT%H:%M:%S")
    except ValueError:
        return None
    return moment.replace(tzinfo=datetime.timezone.utc).timestamp()


def read_rows(path, offset=0):
    """Le righe complete del flusso dopo `offset`, e l'offset nuovo. Una riga a
    metà — il processo la sta scrivendo — si rilegge al giro dopo; una riga
    che non è JSON si salta."""
    rows = []
    try:
        size = os.path.getsize(path)
    except OSError:
        return rows, offset
    if size < offset:
        offset = 0
    with open(path, "rb") as flow_handle:
        flow_handle.seek(offset)
        for raw_line in flow_handle:
            if not raw_line.endswith(b"\n"):
                break
            offset += len(raw_line)
            try:
                row = json.loads(raw_line.decode("utf-8", errors="replace"))
            except ValueError:
                continue
            if isinstance(row, dict) and isinstance(row.get("seq"), int):
                rows.append(row)
    return rows, offset


class FlowWriter:
    """Lo scrittore unico del flusso. `seq` riparte dall'ultimo scritto: un
    processo rilanciato continua la numerazione, e `wait` col suo `seq` non
    perde e non ripete niente."""

    def __init__(self, path, last_seq):
        self.path = path
        self.seq = last_seq

    def append(self, kind, **fields):
        self.seq += 1
        row = {"seq": self.seq, "ts": now_iso(), "tipo": kind}
        row.update({key: value for key, value in fields.items() if value is not None})
        with open(self.path, "a", encoding="utf-8", newline="\n") as flow_handle:
            flow_handle.write(json.dumps(row, ensure_ascii=False) + "\n")
            flow_handle.flush()
        return row


# ---------------------------------------------------------------------------
# Il replay: lo stato del giro dalle righe
# ---------------------------------------------------------------------------


class Round:
    """Lo stato del giro ricavato dal flusso.

    - `steps`: membro → l'ultima fotografia `passo`, aperta o chiusa;
    - `held`: membro → motivo, per i membri fermi;
    - `released`: i membri liberati da un ordine e non ancora ripartiti: il
      primo passo dopo l'ordine scavalca il motivo che li aveva fermati;
    - `last_step_seq`: il `seq` dell'ultimo cambio di un passo o di un fermo,
      che fa da generazione ai risvegli del giro;
    - `wakes`: le righe `risveglio`, in ordine;
    - `cycles`: i cicli chiusi dall'ultimo checkpoint del perimetro;
    - `orders_done`: l'ultimo numero d'ordine applicato;
    - `start`: l'ultima riga `avvio`; `before`: la riga `prima`;
    - `plan`: l'ultima riga `piano`; `last_seq`: l'ultimo `seq`.
    """

    def __init__(self, head):
        self.head = head
        self.steps = {}
        self.held = {}
        self.released = set()
        self.last_step_seq = 0
        self.wakes = []
        self.cycles = 0
        self.closed_cycles = 0
        self.orders_done = 0
        self.start = None
        self.before = None
        self.plan = None
        self.end = None
        self.last_seq = 0
        self.turns = []

    def apply(self, row):
        self.last_seq = max(self.last_seq, row["seq"])
        kind = row.get("tipo")
        if kind == "avvio":
            self.start, self.end = row, None
        elif kind == "fine":
            self.end = row
        elif kind == "prima":
            self.before = row
        elif kind == "piano":
            self.plan = row
        elif kind == "passo":
            member = row.get("membro")
            self.steps[member] = row
            self.last_step_seq = row["seq"]
            if row.get("fase") == "in apertura":
                self.released.discard(member)
            if row.get("fase") == "chiuso" and row.get("passo") in ("run", "checkpoint"):
                if member == self.head:
                    self.cycles = 0
                else:
                    self.cycles += 1
                    self.closed_cycles += 1
        elif kind == "turno":
            self.turns.append(row)
        elif kind == "risveglio":
            self.wakes.append(row)
        elif kind == "fermo":
            self.held[row.get("membro")] = row.get("motivo", "")
            self.last_step_seq = row["seq"]
        elif kind == "libero":
            self.held.pop(row.get("membro"), None)
            self.last_step_seq = row["seq"]
            if row.get("forza"):
                self.released.add(row.get("membro"))
        elif kind == "ordine":
            self.orders_done = max(self.orders_done, row.get("n", 0))

    def open_steps(self):
        return {member: row for member, row in self.steps.items() if row.get("fase") in OPEN_PHASES}

    def has_stepped(self, member):
        return member in self.steps

    def last_wake(self, exclude_keepalive=False):
        for row in reversed(self.wakes):
            if not exclude_keepalive or row.get("motivo") != KEEPALIVE:
                return row
        return None


def replay(path, head):
    rows, _ = read_rows(path)
    state = Round(head)
    for row in rows:
        state.apply(row)
    return state, rows


# ---------------------------------------------------------------------------
# Gli ordini dell'orchestrator
# ---------------------------------------------------------------------------


def read_orders(path, after=0):
    """Gli ordini con numero oltre `after`, in ordine."""
    orders = []
    try:
        with open(path, encoding="utf-8", errors="replace") as orders_handle:
            for line in orders_handle:
                try:
                    order = json.loads(line)
                except ValueError:
                    continue
                if isinstance(order, dict) and isinstance(order.get("n"), int) and order["n"] > after \
                        and order.get("ordine") in ORDERS and isinstance(order.get("membro"), str):
                    orders.append(order)
    except OSError:
        return []
    return sorted(orders, key=lambda order: order["n"])


def append_order(path, order, member):
    """Un ordine in coda al file, col numero dopo l'ultimo. Lo scrive solo
    l'orchestrator, una chiamata alla volta: nessuna gara sul numero."""
    last = 0
    for existing in read_orders(path):
        last = max(last, existing["n"])
    entry = {"n": last + 1, "ts": now_iso(), "ordine": order, "membro": member}
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a", encoding="utf-8", newline="\n") as orders_handle:
        orders_handle.write(json.dumps(entry, ensure_ascii=False) + "\n")
    return entry
