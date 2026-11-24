"""
orchestrator_common — le letture condivise dagli script dell'orchestrator.

`watch_sessions.py` (il monitor), `sessions.py` (list, tail, orchestrators, find),
`mandate.py` e `orchestrator_state.py` leggono le stesse fonti: la radice del progetto,
la sua docs-root, i task file, il registro delle sessioni vive. Stanno qui, in
un posto solo, perché due copie della stessa lettura divergono alla prima
correzione.

Solo libreria standard di Python: gli script girano dalla cache del plugin su
Linux e su Windows, dove nessuno installa pacchetti per loro.

Come si carica. Ogni script aggiunge la propria cartella a `sys.path` prima di
importare questo modulo: con `python -I` (modalità isolata) la cartella dello
script non entra da sola in `sys.path`, e un `import` nudo fallirebbe.
"""

import datetime
import glob
import json
import os
import re
import sys

PROJECT_CONFIG = os.path.join(".claude", "loom-works.json")


def setup_stdout():
    """Stdout in UTF-8 e a capo `\\n` su ogni piattaforma.

    Su Windows la console di default non è UTF-8, e le emoji degli eventi
    farebbero fallire la `print`. Il monitor scrive in una pipe (il tool
    Monitor di Claude Code), quindi la codifica la decide lo script.
    """
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")


def find_project_root(start):
    """La radice del progetto: la prima cartella, salendo da `start`, che
    contiene `.claude/loom-works.json`.

    Stessa regola di `lw_find_project_root` in `scripts/utils/lib.sh`, senza la
    risalita a git: un progetto loom ha sempre il suo file di configurazione.
    Senza file, `start` stesso.
    """
    current = os.path.abspath(start)
    while True:
        if os.path.isfile(os.path.join(current, PROJECT_CONFIG)):
            return current
        parent = os.path.dirname(current)
        if parent == current:
            return os.path.abspath(start)
        current = parent


def docs_root(project_root):
    """La docs-root del progetto: campo `docsRoot` di `.claude/loom-works.json`,
    poi `LOOM_DOCS_ROOT`, poi `docs`.

    Stessa precedenza di `lw_docs_root` in `scripts/utils/lib.sh`: il file del
    progetto vince, l'ambiente resta una via di fuga per banchi e fixture.
    """
    config_path = os.path.join(project_root, PROJECT_CONFIG)
    try:
        with open(config_path, encoding="utf-8") as config_handle:
            value = json.load(config_handle).get("docsRoot")
        if isinstance(value, str) and value:
            return value
    except (OSError, ValueError, AttributeError):
        pass
    return os.environ.get("LOOM_DOCS_ROOT") or "docs"


def find_task_file(project_root, docs, task_id):
    """Il task file di `task_id` sotto `<docs>/tasks/`, `None` se non c'è.

    Il nome è `<id>-<slug>.md`: il trattino dopo l'id tiene `T7` fuori da
    `T74-…`. Con più file per lo stesso id vale il primo in ordine alfabetico.
    """
    matches = sorted(glob.glob(os.path.join(glob.escape(os.path.join(project_root, docs, "tasks")),
                                            glob.escape(task_id) + "-*.md")))
    return matches[0] if matches else None


def header_field(lines, name):
    """Il valore di un campo dell'header di un task file (`- **<name>**: …`),
    stringa vuota se il campo manca."""
    prefix = f"- **{name}**:"
    for line in lines:
        if line.startswith(prefix):
            return line[len(prefix):].strip()
    return ""


# ---------------------------------------------------------------------------
# Path: confronto per piattaforma
# ---------------------------------------------------------------------------

IS_WINDOWS = os.name == "nt"


def comparable_path(path, windows=IS_WINDOWS):
    """La forma di un path su cui si confronta, mai quella che si mostra.

    Su Windows: separatori portati a `\\`, forma MSYS `/c/…` riportata a
    `c:\\…`, tutto minuscolo, nessun separatore in coda. NTFS non distingue le
    maiuscole e Claude Code non normalizza la lettera del drive (`c:\\…` da VS
    Code, `C:\\…` da Windows Terminal). Altrove il path com'è, senza `/` in
    coda: il confronto resta case-sensitive come il filesystem.

    Gemella di `comparablePath` in `loom-deck/src/project-path.ts`.
    """
    if not windows:
        return path.rstrip("/") or path
    normalized = path.replace("/", "\\")
    msys = re.match(r"^\\([a-zA-Z])(?:\\|$)", normalized)
    if msys:
        normalized = msys.group(1) + ":\\" + normalized[msys.end():]
    normalized = normalized.rstrip("\\")
    if re.fullmatch(r"[a-zA-Z]:", normalized):
        normalized += "\\"
    return normalized.lower()


def is_within(path, root, windows=IS_WINDOWS):
    """`path` è `root` o sta sotto di lei. Mai un prefisso di nome: la radice
    `/a/loom` non contiene `/a/loom-works`."""
    candidate = comparable_path(path, windows)
    base = comparable_path(root, windows)
    if candidate == base:
        return True
    separator = "\\" if windows else "/"
    return candidate.startswith(base if base.endswith(separator) else base + separator)


def relative_location(cwd, project_root):
    """La sottocartella in cui è nata una sessione, relativa alla radice;
    stringa vuota per la radice stessa.

    Su Windows `os.path.relpath` solleva `ValueError` su due path di drive
    diversi, e la grafia MSYS (`/c/…`) che a volte compare nel `cwd` è per lui
    un altro drive: lì vale l'ultimo segmento del path.
    """
    if comparable_path(cwd) == comparable_path(project_root):
        return ""
    try:
        return os.path.relpath(cwd, project_root)
    except ValueError:
        return os.path.basename(cwd.rstrip("/\\")) or cwd


# ---------------------------------------------------------------------------
# Registro vivo: ~/.claude/sessions/<pid>.json
# ---------------------------------------------------------------------------
#
# Una entry per processo `claude` in esecuzione, scritta dal CLI. È la sola
# fonte locale che dica se una conversazione è aperta ora: i transcript restano
# su disco per sempre. Schema interno di Claude Code, non documentato: la
# lettura sta qui e solo qui. La legge allo stesso modo `loom-deck/src/
# live-sessions.ts`, senza che il plugin ne importi il codice.


def claude_home():
    return os.path.join(os.path.expanduser("~"), ".claude")


def linux_proc_start(pid):
    """Campo 22 (`starttime`) di `/proc/<pid>/stat`, `None` se il processo non
    c'è.

    Il taglio è sull'ULTIMA `)`: il campo 2 (`comm`) è il nome dell'eseguibile
    fra parentesi e può contenere spazi e parentesi a sua volta. Dopo l'ultima
    `)` il primo token è il campo 3, quindi `starttime` è l'indice 19.
    """
    try:
        with open(f"/proc/{pid}/stat", encoding="utf-8", errors="replace") as stat_handle:
            stat_line = stat_handle.read()
    except OSError:
        return None
    fields = stat_line[stat_line.rfind(")") + 1:].split()
    return fields[19] if len(fields) > 19 else None


_PROCESS_GONE = object()
_kernel32 = None


def _windows_kernel32():
    """kernel32 con i tipi degli argomenti dichiarati, caricato una volta.

    Senza `argtypes` ctypes passa un handle come `int` a 32 bit, e su Windows
    a 64 bit un handle alto verrebbe troncato.
    """
    global _kernel32
    if _kernel32 is None:
        import ctypes
        from ctypes import wintypes
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel32.OpenProcess.argtypes = (wintypes.DWORD, wintypes.BOOL, wintypes.DWORD)
        kernel32.OpenProcess.restype = wintypes.HANDLE
        kernel32.GetExitCodeProcess.argtypes = (wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD))
        kernel32.GetExitCodeProcess.restype = wintypes.BOOL
        filetime_pointer = ctypes.POINTER(wintypes.FILETIME)
        kernel32.GetProcessTimes.argtypes = (wintypes.HANDLE,) + (filetime_pointer,) * 4
        kernel32.GetProcessTimes.restype = wintypes.BOOL
        kernel32.CloseHandle.argtypes = (wintypes.HANDLE,)
        kernel32.CloseHandle.restype = wintypes.BOOL
        _kernel32 = kernel32
    return _kernel32


def windows_creation_filetime(pid):
    """L'ora di creazione del processo `pid` come FILETIME UTC in decimale (lo
    stesso numero che il CLI scrive in `procStart`), `_PROCESS_GONE` se il
    processo non c'è più, `None` se non si riesce a saperlo.

    Nessun processo esterno: `OpenProcess` + `GetProcessTimes` via ctypes.
    `os.kill(pid, 0)` è escluso: su Windows Python lo traduce in
    `TerminateProcess`, e ucciderebbe la sessione invece di guardarla.

    `ERROR_ACCESS_DENIED` vale come processo assente: è la risposta per i
    processi di un altro utente (servizi, sessione 0), e nessuno di loro è una
    conversazione dell'utente. Stessa scelta del deck (`windows-liveness.ts`).
    """
    import ctypes
    from ctypes import wintypes
    kernel32 = _windows_kernel32()
    process_query_limited_information = 0x1000
    handle = kernel32.OpenProcess(process_query_limited_information, False, pid)
    if not handle:
        error = ctypes.get_last_error()
        if error in (5, 87):  # ERROR_ACCESS_DENIED, ERROR_INVALID_PARAMETER (nessun pid)
            return _PROCESS_GONE
        return None
    try:
        exit_code = wintypes.DWORD()
        still_active = 259
        if kernel32.GetExitCodeProcess(handle, ctypes.byref(exit_code)) and exit_code.value != still_active:
            return _PROCESS_GONE
        creation, exit_time, kernel_time, user_time = (wintypes.FILETIME() for _ in range(4))
        if not kernel32.GetProcessTimes(handle, ctypes.byref(creation), ctypes.byref(exit_time),
                                        ctypes.byref(kernel_time), ctypes.byref(user_time)):
            return None
        return str((creation.dwHighDateTime << 32) | creation.dwLowDateTime)
    finally:
        kernel32.CloseHandle(handle)


def process_is_alive(pid, proc_start):
    """Il processo `pid` è ancora quello che ha scritto l'entry del registro?

    `True` vivo, `False` morto, `None` non verificabile.

    Il registro è keyed su pid, e i pid si riciclano: senza il confronto con
    `procStart` un pid riusato da un altro programma marcherebbe viva una
    conversazione morta, e un'entry lasciata da un `kill -9` resterebbe viva
    per sempre. Su Linux `procStart` è il campo 22 di `/proc/<pid>/stat`; su
    Windows il FILETIME di creazione del processo. Il confronto è fra stringhe:
    il FILETIME ha 18 cifre, e un numero in virgola mobile perderebbe le ultime.

    Dove nessuna delle due letture esiste (né `/proc` né Windows), `None`: la
    sessione resta fra le vive, e chi la mostra dice che il processo potrebbe
    essere morto.
    """
    if IS_WINDOWS:
        try:
            created = windows_creation_filetime(pid)
        except (OSError, AttributeError, ValueError):
            return None
        if created is _PROCESS_GONE:
            return False
        return None if created is None else created == proc_start
    if os.path.isdir("/proc"):
        return linux_proc_start(pid) == proc_start
    return None


class LiveSession:
    """Una entry viva del registro, ridotta a ciò che l'orchestrator legge."""

    def __init__(self, pid, entry, alive, headless=False):
        self.pid = pid
        self.proc_start = entry["procStart"]
        self.session_id = entry["sessionId"]
        self.cwd = entry["cwd"]
        self.status = entry.get("status") if isinstance(entry.get("status"), str) else ""
        timestamp = entry.get("statusUpdatedAt")
        self.status_since = timestamp / 1000.0 if isinstance(timestamp, (int, float)) else None
        self.name = entry.get("name") if isinstance(entry.get("name"), str) else ""
        # True = verificata, None = processo non verificabile su questa piattaforma
        self.alive = alive
        # Un turno `claude -p` in corso (`entrypoint: sdk-cli`): un processo che
        # scrive sul transcript senza una tab. Il processo vive un turno solo,
        # quindi la sua nascita e la sua fine sono l'inizio e la fine del turno.
        self.headless = headless

    @property
    def key(self):
        """La chiave di una sessione è il processo, non il `sessionId`: un
        `/clear` o una compattazione cambiano il `sessionId` dentro lo stesso
        processo, ed è un transcript nuovo della stessa sessione."""
        return f"{self.pid}:{self.proc_start}"


def process_class(entry):
    """Che cosa è il processo di una entry del registro: `tab`, `headless` o `None`.

    `tab` è una conversazione in una tab dell'utente (`entrypoint: cli`,
    `kind: interactive`); `headless` un turno `claude -p` in corso
    (`entrypoint: sdk-cli`, `kind: interactive`). Tutto il resto è `None`, e
    il job in background per primo: scrive `entrypoint: cli` come una tab e si
    distingue solo per `kind: bg`, quindi le due classi si riconoscono in
    positivo, campo per campo. Campi assenti valgono come tab: una versione del
    CLI che non li scrivesse non deve svuotare la lista. Stessa regola di
    `processClass` nel deck e di `loadLiveSessions` in compass.
    """
    entrypoint = entry.get("entrypoint") if isinstance(entry.get("entrypoint"), str) else "cli"
    kind = entry.get("kind") if isinstance(entry.get("kind"), str) else "interactive"
    if kind != "interactive":
        return None
    if entrypoint == "cli":
        return "tab"
    if entrypoint == "sdk-cli":
        return "headless"
    return None


def parse_registry_entry(content):
    """Il dict di una entry utilizzabile, di qualunque classe, o `None`.

    Senza `sessionId`, `procStart` o `cwd` l'entry non serve: il primo porta al
    transcript, il secondo è la guardia sul pid, il terzo il filtro di progetto.
    """
    try:
        entry = json.loads(content)
    except ValueError:
        return None
    if not isinstance(entry, dict):
        return None
    for field in ("sessionId", "procStart", "cwd"):
        if not isinstance(entry.get(field), str) or not entry[field]:
            return None
    return entry


def parse_live_entry(content):
    """Il dict di una entry che è una tab dell'utente, o `None` (`process_class`)."""
    entry = parse_registry_entry(content)
    if entry is None or process_class(entry) != "tab":
        return None
    return entry


class Registry:
    """Una lettura del registro: le sessioni vive del progetto — tab e turni
    headless, `LiveSession.headless` le distingue —, più i pid la
    cui entry esiste ma non si è potuta leggere.

    `readable` è falso quando la cartella stessa non si legge: chi confronta
    due letture non deve prendere un registro illeggibile per «tutte chiuse».
    Un'entry illeggibile (il CLI la sta riscrivendo) finisce in `unreadable`
    per la stessa ragione.
    """

    def __init__(self):
        self.sessions = []
        self.unreadable = set()
        self.readable = True


def read_registry(project_root):
    registry = Registry()
    registry_dir = os.path.join(claude_home(), "sessions")
    try:
        file_names = os.listdir(registry_dir)
    except OSError:
        registry.readable = False
        return registry
    for file_name in file_names:
        if not file_name.endswith(".json"):
            continue
        pid_text = file_name[:-5]
        if not pid_text.isdigit():
            continue
        pid = int(pid_text)
        try:
            with open(os.path.join(registry_dir, file_name), encoding="utf-8") as entry_handle:
                content = entry_handle.read()
        except OSError:
            continue  # il processo è finito fra listdir e open
        entry = parse_registry_entry(content)
        if entry is None:
            try:
                json.loads(content)
            except ValueError:
                registry.unreadable.add(pid)  # scrittura a metà: si rilegge al giro dopo
            continue
        kind = process_class(entry)
        if kind is None or not is_within(entry["cwd"], project_root):
            continue
        alive = process_is_alive(pid, entry["procStart"])
        if alive is False:
            continue
        registry.sessions.append(LiveSession(pid, entry, alive, headless=kind == "headless"))
    return registry


# ---------------------------------------------------------------------------
# Transcript: ~/.claude/projects/<cwd codificato>/<sessionId>.jsonl
# ---------------------------------------------------------------------------


def encode_project_dir(cwd):
    """Il nome della cartella dei transcript di una sessione nata in `cwd`:
    ogni carattere non alfanumerico portato a `-`. Stessa regola di
    `projectDirName` in `loom-deck/src/sessions.ts`."""
    return re.sub(r"[^A-Za-z0-9]", "-", cwd)


def transcript_path(cwd, session_id):
    """Il transcript di una sessione, dal `cwd` del registro.

    Il `cwd` del registro è la cartella in cui il processo è nato, la stessa da
    cui Claude Code ricava il nome della cartella dei transcript: una sessione
    nata in un submodule ha la sua cartella, e da qui la si trova.

    Se il file non c'è al path calcolato lo si cerca per `sessionId` in tutte le
    cartelle dei progetti: copre una regola di codifica diversa da quella sopra
    (un path lungo, un carattere fuori dall'ASCII). Se non c'è da nessuna
    parte, il path calcolato: la sessione non ha ancora scritto il primo record.
    """
    projects_dir = os.path.join(claude_home(), "projects")
    candidate = os.path.join(projects_dir, encode_project_dir(cwd), session_id + ".jsonl")
    if os.path.exists(candidate):
        return candidate
    matches = glob.glob(os.path.join(glob.escape(projects_dir), "*", glob.escape(session_id) + ".jsonl"))
    return matches[0] if matches else candidate


def first_record_time(path, max_lines=60):
    """L'epoch del primo `timestamp` del transcript, `None` se non c'è.

    Dice se un transcript è nato dopo un istante: un transcript nato da un
    `/clear` o da una sessione nuova si legge dall'inizio, uno ripreso con
    `--resume` dalla fine.
    """
    try:
        with open(path, encoding="utf-8", errors="replace") as transcript_handle:
            for index, line in enumerate(transcript_handle):
                if index >= max_lines:
                    break
                match = re.search(r'"timestamp":"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)', line)
                if match:
                    moment = datetime.datetime.strptime(match.group(1), "%Y-%m-%dT%H:%M:%S")
                    return moment.replace(tzinfo=datetime.timezone.utc).timestamp()
    except OSError:
        return None
    return None


def read_records(path):
    with open(path, encoding="utf-8", errors="replace") as transcript_handle:
        for line in transcript_handle:
            try:
                yield json.loads(line)
            except ValueError:
                continue


def first_meaningful_line(text):
    for raw_line in text.splitlines():
        cleaned = raw_line.strip().lstrip("#").strip().strip("*").strip()
        if cleaned:
            return cleaned
    return ""


# Messaggi che Claude Code registra come `type: user` ma che non ha scritto
# nessuno: la fine di un comando o di un subagent in background, il messaggio di
# un subagent o di un'altra sessione, i promemoria, i comandi locali, e
# l'interruzione di un turno (esc, o un permesso negato), che ha anche la
# variante `[Request interrupted by user for tool use]`: si confronta per
# prefisso.
MACHINE_PROMPT_PREFIXES = (
    "<task-notification>",
    "<agent-message",
    "<cross-session-message",
    "<system-reminder>",
    "<local-command",
    "[Request interrupted by user",
)


def user_prompt_text(record):
    """Il testo di un prompt scritto dall'utente, o `None` se il record non lo è.

    Fuori: i record di macchina (`isMeta`, come il corpo di una skill espansa;
    `isCompactSummary`; i subagent), i risultati dei tool e i messaggi di
    macchina sopra. Un prompt con un'immagine arriva come lista di blocchi.
    """
    if record.get("type") != "user" or record.get("isMeta") or record.get("isCompactSummary"):
        return None
    if record.get("isSidechain"):
        return None
    content = (record.get("message") or {}).get("content")
    if isinstance(content, list):
        if any(isinstance(block, dict) and block.get("type") == "tool_result" for block in content):
            return None
        content = "\n".join(block.get("text", "") for block in content
                            if isinstance(block, dict) and block.get("type") == "text")
    if not isinstance(content, str) or not content.strip():
        return None
    if content.lstrip().startswith(MACHINE_PROMPT_PREFIXES):
        return None
    return content


def describe_prompt(content):
    """Una riga per un prompt: `/comando argomenti` per uno slash command, la
    prima riga di testo per il resto."""
    command_match = re.search(r"<command-name>(.*?)</command-name>", content)
    if command_match:
        args_match = re.search(r"<command-args>(.*?)</command-args>", content, re.S)
        args = args_match.group(1).strip() if args_match else ""
        return f"{command_match.group(1)} {args}".replace("\n", " ").strip()
    return first_meaningful_line(content)


# ---------------------------------------------------------------------------
# Legame sessione → task
# ---------------------------------------------------------------------------

# La frase che l'hook SessionStart di loom-works (`inject-task.sh`) scrive nel
# primo messaggio di una sessione legata a una task via `$LOOM_TASK`.
TASK_PHRASE_PATTERN = re.compile(r"risolta via \$LOOM_TASK=(T\d+)")


def sidecar_path(project_root):
    return os.path.join(project_root, ".claude", "loom", "session-tasks.jsonl")


def load_task_bindings(project_root):
    """sessionId → taskId dal sidecar del deck, `.claude/loom/session-tasks.jsonl`.

    JSONL append-only, last-wins per campo: un record con un `taskId` diverso
    riassegna la conversazione, `taskId` vuoto la stacca (torna senza task), un
    record senza il campo non tocca il legame. È il canale che segue le
    riassegnazioni fatte nel deck, quindi viene prima della frase nel
    transcript, che resta quella scritta all'apertura. Stessa lettura di
    `loadSessionIndex` in `loom-deck/src/task-index.ts`.
    """
    bindings = {}
    try:
        with open(sidecar_path(project_root), encoding="utf-8", errors="replace") as sidecar_handle:
            lines = sidecar_handle.readlines()
    except OSError:
        return bindings
    for line in lines:
        try:
            record = json.loads(line)
        except ValueError:
            continue
        if not isinstance(record, dict) or not isinstance(record.get("sessionId"), str):
            continue
        task_id = record.get("taskId")
        if not isinstance(task_id, str):
            continue
        if task_id:
            bindings[record["sessionId"]] = task_id
        else:
            bindings.pop(record["sessionId"], None)
    return bindings


def task_of_transcript(path, max_lines=400):
    """La task della frase `risolta via $LOOM_TASK=<id>` nei primi record del
    transcript, `None` se non c'è."""
    try:
        with open(path, encoding="utf-8", errors="replace") as transcript_handle:
            for index, line in enumerate(transcript_handle):
                match = TASK_PHRASE_PATTERN.search(line)
                if match:
                    return match.group(1)
                if index >= max_lines:
                    break
    except OSError:
        pass
    return None


def session_label(session_id, sidecar_task, transcript_task):
    """L'etichetta di una sessione: la task del sidecar, poi quella della frase
    nel transcript, poi `?` più l'inizio del sessionId."""
    return sidecar_task or transcript_task or "?" + session_id[:6]
