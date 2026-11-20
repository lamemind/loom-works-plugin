"""
watch_filter — il filtro a monte del monitor della regia: whitelist e blacklist.

Ogni riga che il monitor scrive arriva alla regia come notifica del tool
Monitor, e la regia spende un turno del modello anche per decidere di
ignorarla. Il filtro toglie le righe prima che escano, dentro il processo del
monitor: è l'unico punto in cui una riga scartata non costa niente.

Il file del filtro (`--filter` di watch_sessions.py) è un oggetto JSON:

  {"whitelist": ["task:T210", "task:T211"], "blacklist": ["session:0a1b2c3d"]}

Le due liste hanno la stessa forma: 0 o più filtri, e un filtro è una stringa
col tipo in testa.

  task:T210         l'evento riguarda la task T210
  session:0a1b2c3d  l'evento è di una conversazione il cui sessionId comincia
                    così, anche uno che ha avuto prima di un /clear
  re:<regex>        la regex trova un punto della riga, come esce dal monitor

Il tipo è esplicito perché un filtro letto col tipo sbagliato non dà errore:
perde un evento o ne lascia passare uno. Senza prefisso, una regex di sole
cifre esadecimali passerebbe per una conversazione, e `T21` sarebbe una task o
una regex.

Un evento passa se la whitelist lo ammette — una whitelist vuota ammette tutto
— e nessun filtro della blacklist lo prende. Task e conversazione lavorano sugli
attributi dell'evento, non sul testo: sei eventi di sessione su quattordici non
portano il sessionId nella riga, e due conversazioni sulla stessa task scrivono
righe uguali. Solo la regex guarda il testo, e lì sceglie per classe di evento
(`^git .* ⬆`, ` 📊 `), cosa che gli altri due tipi non fanno.

Gli attributi di un evento:

  - un evento di sessione porta la task della sessione (nessuna per una `?`) e
    i sessionId del processo; un cambio di legame porta la task vecchia e la
    nuova
  - un evento di task file o di tasks.md porta la sua task, e nessuna
    sessione: il monitor vede un file che cambia, non chi lo cambia. Una
    conversazione in blacklist lascia quindi passare i fatti della sua task
  - un commit porta le task del suo soggetto (`commit_tasks`); un push nessuna
  - le righe `monitor` non passano dal filtro: un monitor rotto deve parlare

Un file mancante, non JSON o con un filtro non valido non ferma il monitor:
resta l'ultimo filtro valido, o passa tutto se non ce n'è ancora uno, ed esce
una riga `monitor ⚠ filtro …`. Un evento in più costa un turno; una domanda
persa lascia una sessione ad aspettare.
"""

import json
import os
import re

TASK_ID_PATTERN = re.compile(r"^T\d+$")
SESSION_PREFIX_PATTERN = re.compile(r"^[0-9A-Za-z-]+$")
TASK_IN_TEXT_PATTERN = re.compile(r"\bT\d+\b")
# Lo scope di un commit: `run(T23): …`, `regia (T220 DLV5): …`. Il nome davanti
# alla parentesi non conta, conta che la parentesi chiuda prima dei due punti.
COMMIT_SCOPE_PATTERN = re.compile(r"^[\w-]+\s*\(([^)]*)\)\s*:")
CREATE_SUBJECT_PATTERN = re.compile(r"^task\((T\d+)\):\s*create\b")
LIST_KEYS = ("whitelist", "blacklist")


class FilterError(ValueError):
    """Un file del filtro che non si può applicare: il motivo, in una riga."""


class Rule:
    """Un filtro di una lista: tipo, valore, e la regex compilata per `re:`."""

    def __init__(self, text):
        if not isinstance(text, str):
            raise FilterError(f"filtro non stringa: {json.dumps(text, ensure_ascii=False)}")
        kind, separator, value = text.partition(":")
        kind = kind.strip()
        if not separator or kind not in ("task", "session", "re"):
            raise FilterError(f"prefisso ignoto in «{text}»: attesi task:, session:, re:")
        self.text = text
        self.kind = kind
        self.pattern = None
        if kind == "re":
            if not value:
                raise FilterError(f"regex vuota in «{text}»")
            try:
                self.pattern = re.compile(value)
            except re.error as error:
                raise FilterError(f"regex che non compila in «{text}»: {error}") from None
            self.value = value
            return
        self.value = value.strip()
        if kind == "task" and not TASK_ID_PATTERN.match(self.value):
            raise FilterError(f"task non valida in «{text}»: atteso task:T<numero>")
        if kind == "session" and not SESSION_PREFIX_PATTERN.match(self.value):
            raise FilterError(f"sessione non valida in «{text}»: atteso session:<inizio del sessionId>")

    def matches(self, line, tasks, session_ids):
        if self.kind == "task":
            return self.value in tasks
        if self.kind == "session":
            return any(session_id.startswith(self.value) for session_id in session_ids or ())
        return self.pattern.search(line) is not None


class EventFilter:
    """Whitelist e blacklist lette e valide. `rules` è la forma che si salva
    nello stato del monitor: le stringhe del file, liste complete."""

    def __init__(self, data):
        if not isinstance(data, dict):
            raise FilterError("atteso un oggetto JSON con whitelist e blacklist")
        unknown = sorted(key for key in data if key not in LIST_KEYS)
        if unknown:
            raise FilterError(f"chiave ignota «{unknown[0]}»: attese whitelist e blacklist")
        self.rules = {}
        lists = {}
        for key in LIST_KEYS:
            texts = data.get(key, [])
            if not isinstance(texts, list):
                raise FilterError(f"«{key}» non è una lista di filtri")
            lists[key] = [Rule(text) for text in texts]
            self.rules[key] = list(texts)
        self.whitelist = lists["whitelist"]
        self.blacklist = lists["blacklist"]

    def admits(self, line, tasks=(), session_ids=None):
        """L'evento passa? `tasks` le sue task, `session_ids` i sessionId del
        suo processo, `None` per un evento che non viene da una sessione."""
        if self.whitelist and not any(rule.matches(line, tasks, session_ids) for rule in self.whitelist):
            return False
        return not any(rule.matches(line, tasks, session_ids) for rule in self.blacklist)


class FilterSource:
    """Il file del filtro, riletto quando cambia.

    Una `stat` per giro, nessun processo figlio: il file si rilegge solo quando
    cambiano data di modifica, dimensione o inode. L'ultimo filtro valido si
    salva nello stato del monitor (`saved`), così un riarmo davanti a un file
    rotto tiene il filtro di prima invece di lasciar passare tutto.
    """

    def __init__(self, path, saved):
        self.path = os.path.abspath(path)
        self.name = os.path.basename(self.path)
        self.signature = "unread"
        self.broken = False
        self.active = None
        if saved is not None:
            try:
                self.active = EventFilter(saved)
            except FilterError:
                self.active = None

    def _warning(self, reason):
        self.broken = True
        outcome = "resta il filtro di prima" if self.active is not None else "passa tutto"
        return f"monitor ⚠ filtro {self.name}: {reason} — {outcome}"

    def refresh(self):
        """Rilegge il file se è cambiato. Torna la riga `monitor` da scrivere,
        o `None`."""
        try:
            info = os.stat(self.path)
            signature = (info.st_mtime_ns, info.st_size, info.st_ino)
        except OSError:
            signature = None
        if signature == self.signature:
            return None
        self.signature = signature
        if signature is None:
            return self._warning("file assente")
        try:
            with open(self.path, encoding="utf-8") as filter_handle:
                data = json.load(filter_handle)
            self.active = EventFilter(data)
        except FilterError as error:
            return self._warning(str(error))
        except ValueError:
            return self._warning("non è JSON")
        except OSError as error:
            return self._warning(f"file illeggibile: {error.strerror or error}")
        if self.broken:
            self.broken = False
            return f"monitor ✅ filtro {self.name}: di nuovo in vigore"
        return None


def commit_tasks(subject, parent_of):
    """Le task di un commit, dal suo soggetto.

    L'id dello scope (`run(T23): …`, `regia (T220 DLV5): …`); senza un id nello
    scope, ogni id del soggetto. Il commit di creazione `task(T<n>): create`
    prende anche la task del campo `Parent Task` del file appena nato
    (`parent_of`): è così che la figlia nuova di un'epica passa una whitelist
    che porta il perimetro, e la creazione di una task estranea no. Un commit
    senza id non ha task.
    """
    scope = COMMIT_SCOPE_PATTERN.match(subject)
    tasks = set(TASK_IN_TEXT_PATTERN.findall(scope.group(1))) if scope else set()
    if not tasks:
        tasks = set(TASK_IN_TEXT_PATTERN.findall(subject))
    created = CREATE_SUBJECT_PATTERN.match(subject)
    if created:
        parent = parent_of(created.group(1))
        if parent:
            tasks.add(parent)
    return tasks
