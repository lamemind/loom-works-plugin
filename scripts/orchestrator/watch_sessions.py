"""
watch_sessions — segue le sessioni Claude Code vive di un progetto loom-works.

Ogni riga su stdout è un evento per il tool Monitor di Claude Code:
  - dal registro vivo (~/.claude/sessions/<pid>.json): sessione nuova, sessione
    chiusa, transcript nuovo dopo un /clear, legame con la task cambiato,
    richiesta di permesso (`waiting`), sessione `busy` ferma da --stall-minutes;
    turno headless partito e finito, per un `claude -p` (`entrypoint: sdk-cli`)
  - dai transcript delle altre sessioni: turno finito, domanda all'utente,
    skill lanciata, prompt dell'utente
  - dai task file: sezione cambiata, cifre di DLV e AC, campo Progress
  - da tasks.md: colonna Prog della tabella Tasks Overview
  - da git: commit locali nuovi e push su origin, per ogni repo guardato: la
    radice, ogni submodule di .gitmodules e i --repo in più

Gli scanner servono soprattutto allo script del flusso (`flow_engine.py`), che
li chiama dal proprio processo: assegna `sink`, e ogni evento gli arriva come
dict — genere, testo, task, sessioni — invece di uscire su stdout. Il flusso
sceglie da sé quali eventi tenere: quelli del perimetro e dei suoi membri.

Con --context-threshold il monitor misura anche il contesto della sessione che
lo lancia, l'orchestrator, dal suo transcript (watch_context.py): una riga `orchestrator 🧠`
al 20, 40, 60, 80, 100 e 120% della soglia, una volta per gradino. Come le righe
`monitor`, escono sempre.

Le sessioni sono quelle del registro vivo con `cwd` dentro la radice del
progetto, comprese quelle nate in un submodule: il transcript di ognuna si
ricava dal suo `cwd`. La chiave di una sessione è il processo (pid +
`procStart`), non il `sessionId`, che cambia a ogni /clear.

Lo stato sta in un file JSON (--state): un monitor riarmato con lo stesso file
non ripete gli eventi già detti e non perde quelli capitati nel cambio. Il primo
giro registra lo stato attuale e non emette niente sul passato, tranne il
contesto dell'orchestrator: l'orchestrator deve sapere subito se è già oltre un gradino.

Uso da solo, una riga per evento su stdout (dalla cache del plugin):
  python -u -I watch_sessions.py --project-root <radice del progetto> \\
      --own-session <id della sessione da saltare> \\
      --state <file JSON di stato, in una cartella che git ignora> \\
      [--context-threshold <token>] \\
      [--repo nome=path-relativo-alla-radice]...
"""

import argparse
import glob
import hashlib
import json
import os
import re
import subprocess
import sys
import time

# Il modulo comune si carica dal path esplicito della cartella dello script:
# con `python -I` la cartella non entra da sola in sys.path. Nessun __pycache__:
# la cartella è la cache del plugin, che non si scrive.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import orchestrator_common  # noqa: E402  (dopo l'aggiunta della cartella a sys.path)
import watch_context  # noqa: E402

CHECKBOX_PATTERN = re.compile(r"^- \[([ x])\]")
TASK_IN_TEXT_PATTERN = re.compile(r"\bT\d+\b")
# Lo scope di un commit: `run(T23): …`, `orchestrator (T220 DLV5): …`. Il nome davanti
# alla parentesi non conta, conta che la parentesi chiuda prima dei due punti.
COMMIT_SCOPE_PATTERN = re.compile(r"^[\w-]+\s*\(([^)]*)\)\s*:")
CREATE_SUBJECT_PATTERN = re.compile(r"^task\((T\d+)\):\s*create\b")

# La sessione dell'orchestrator vista nell'ultimo giro del registro (`sessionId`,
# `cwd`), o None: la scrive `scan_sessions`, la legge `scan_context`.
own_live = None

# Chi riceve gli eventi: None li stampa su stdout, una riga per evento, per il
# tool Monitor; lo script del flusso assegna una funzione che riceve ogni
# evento come dict (`deliver`).
sink = None


def parse_arguments():
    parser = argparse.ArgumentParser(description="Segue le sessioni vive di un progetto loom-works")
    parser.add_argument("--project-root", default="",
                        help="default: la prima cartella sopra la corrente con .claude/loom-works.json")
    parser.add_argument("--own-session", default="", help="session id da saltare: quello che lancia il monitor")
    parser.add_argument("--state", required=True, help="file JSON di stato, in una cartella che git ignora")
    parser.add_argument("--repo", action="append", default=[],
                        help="nome=path relativo alla radice, oltre a radice e submodule; ripetibile")
    parser.add_argument("--poll-seconds", type=int, default=15)
    parser.add_argument("--stall-minutes", type=float, default=10,
                        help="una sessione busy col transcript fermo da più tempo produce un evento")
    parser.add_argument("--context-threshold", type=int, default=0,
                        help="soglia di contesto dell'orchestrator in token: eventi 🧠 ai gradini; 0 = nessuna misura")
    parser.add_argument("--once", action="store_true",
                        help="un giro solo: legge, salva lo stato ed esce")
    return parser.parse_args()


def deliver(kind, text, tasks=(), session_ids=None, **extra):
    """Un evento al `sink`: `genere` dice di che evento si tratta (`turno`,
    `fine`, `task file`, `contesto`, …), `testo` è la riga che stdout
    stamperebbe, `task` e `sessioni` i suoi attributi; `extra` i campi propri
    del genere, come la sessione e la classe del processo di un evento di
    sessione o il gradino del contesto."""
    sink(dict(extra, genere=kind, testo=text, task=sorted(tasks), sessioni=list(session_ids or [])))


def emit(line, kind="monitor", **extra):
    """Una riga `monitor`: parla del monitor, non di una task."""
    text = line.replace("\n", " ")[:300]
    if sink is not None:
        deliver(kind, text, **extra)
        return
    print(text, flush=True)


def emit_event(line, tasks=(), session_ids=None, kind="evento", **extra):
    """Un evento: `tasks` le task dell'evento, `session_ids` i sessionId del
    processo per un evento di sessione, `None` per tutti gli altri."""
    text = line.replace("\n", " ")[:300]
    if sink is not None:
        deliver(kind, text, tasks, session_ids, **extra)
        return
    print(text, flush=True)


def process_tasks(process):
    """La task di una sessione, come insieme: nessuna per una sessione `?`."""
    label = process.get("label") or ""
    return set() if not label or label.startswith("?") else {label}


def process_session_ids(process):
    """Ogni sessionId che il processo ha avuto, l'attuale compreso: chi riceve
    l'evento segue il processo anche dopo un /clear."""
    return process.get("session_ids") or [process["session_id"]]


def emit_session(process, line, kind):
    emit_event(line, process_tasks(process), process_session_ids(process), kind,
               sessione=process["session_id"], headless=bool(process.get("headless")))


def load_state(state_path):
    state = {}
    if os.path.exists(state_path):
        with open(state_path, encoding="utf-8") as state_handle:
            state = json.load(state_handle)
    for section in ("processes", "task_files", "progress", "git_refs"):
        state.setdefault(section, {})
    state.setdefault("own_processes", [])
    return state


def save_state(state_path, state):
    temporary_path = state_path + ".tmp"
    with open(temporary_path, "w", encoding="utf-8") as state_handle:
        json.dump(state, state_handle)
    os.replace(temporary_path, state_path)


def handle_transcript_record(record, process, label):
    record_type = record.get("type")
    if record_type == "system" and record.get("subtype") == "turn_duration":
        # Un turno headless lo chiude la fine del processo (`⏹`): nessuno
        # aspetta davanti a una tab, e due eventi per una fine sola si
        # leggerebbero come due turni.
        if process.get("headless"):
            return
        summary = orchestrator_common.first_meaningful_line(process.get("last_text", ""))
        emit_session(process, f"{label} ⏸ turno finito, aspetta l'utente: {summary[:160]}", "turno")
        return
    prompt = orchestrator_common.user_prompt_text(record)
    if prompt is not None:
        emit_session(process, f"{label} ✍ prompt utente: {orchestrator_common.describe_prompt(prompt)[:140]}",
                     "prompt")
        return
    content = (record.get("message") or {}).get("content")
    if record_type != "assistant" or record.get("isSidechain") or not isinstance(content, list):
        return
    for block in content:
        if not isinstance(block, dict):
            continue
        block_type = block.get("type")
        if block_type == "text" and block.get("text", "").strip():
            process["last_text"] = block["text"]
        elif block_type == "tool_use":
            tool_name = block.get("name")
            tool_input = block.get("input") or {}
            process["last_tool"] = tool_name
            if tool_name == "Skill":
                emit_session(process, f"{label} ▶ skill {tool_input.get('skill')} {str(tool_input.get('args') or '')[:80]}",
                             "skill")
            elif tool_name == "AskUserQuestion":
                questions = tool_input.get("questions") or [{}]
                emit_session(process, f"{label} ❓ domanda all'utente: {questions[0].get('question', '')[:160]}",
                             "domanda")


def read_new_records(process):
    """Legge i record completi aggiunti al transcript dall'ultimo giro."""
    path = process["transcript"]
    try:
        size = os.path.getsize(path)
    except OSError:
        return  # la sessione non ha ancora scritto il primo record
    if size < process["offset"]:
        process["offset"] = 0  # file riscritto da capo: si rilegge
    if size == process["offset"]:
        return
    with open(path, "rb") as transcript_handle:
        transcript_handle.seek(process["offset"])
        chunk = transcript_handle.read(size - process["offset"])
    last_newline = chunk.rfind(b"\n")
    if last_newline < 0:
        return  # record a metà: si legge al giro dopo
    process["offset"] += last_newline + 1
    for raw_line in chunk[: last_newline + 1].splitlines():
        decoded_line = raw_line.decode("utf-8", errors="replace")
        try:
            record = json.loads(decoded_line)
        except ValueError:
            continue
        if not isinstance(record, dict):
            continue
        if not process.get("transcript_task"):
            match = orchestrator_common.TASK_PHRASE_PATTERN.search(decoded_line)
            if match:
                process["transcript_task"] = match.group(1)
                refresh_label(process)
        handle_transcript_record(record, process, process["label"])


def start_offset(path, since):
    """Da dove leggere un transcript che il monitor non ha ancora letto.

    Al primo giro (`since` assente) dalla fine: niente eventi sul passato.
    Dopo, dall'inizio se il transcript è nato dopo il giro precedente (una
    sessione nuova, un /clear), dalla fine se è più vecchio (un --resume di una
    conversazione già lunga, che ripeterebbe tutta la sua storia).
    """
    try:
        size = os.path.getsize(path)
    except OSError:
        return 0  # nessun record ancora: quando arriva si legge tutto
    if since is None:
        return size
    born = orchestrator_common.first_record_time(path)
    if born is None or born >= since - 5:
        return 0
    return size


def last_activity(process):
    """L'ultimo momento in cui la sessione ha scritto qualcosa: il transcript o
    i file dei suoi subagent (`<sessionId>/subagents/`), che lavorano mentre
    il transcript principale tace. `None` se non ha ancora scritto niente."""
    transcript = process["transcript"]
    subagents_dir = os.path.join(os.path.dirname(transcript), process["session_id"], "subagents")
    moments = []
    for path in [transcript] + glob.glob(os.path.join(glob.escape(subagents_dir), "*")):
        try:
            moments.append(os.path.getmtime(path))
        except OSError:
            continue
    return max(moments) if moments else None


def check_status(process, session, settings, initialized, now):
    """Gli eventi dal campo `status` del registro.

    `waiting` è una richiesta di permesso: non chiude il turno, quindi il
    transcript non la annuncia. Una domanda con AskUserQuestion ha già il suo
    evento, e non ne riceve un secondo.

    Lo stallo è una sessione `busy` col transcript e i subagent fermi da
    --stall-minutes. Un evento per episodio: riparte solo se la sessione si
    muove e si ferma di nuovo. Dice «ferma», non «bloccata»: un comando lungo è
    indistinguibile da una richiesta API appesa.
    """
    label = process["label"]
    if (initialized and session.status == "waiting" and process.get("status") != "waiting"
            and process.get("last_tool") != "AskUserQuestion"):
        tool = process.get("last_tool")
        emit_session(process, f"{label} ⏳ aspetta un permesso" + (f": {tool}" if tool else ""), "permesso")
    process["status"] = session.status
    process["status_since"] = session.status_since
    moved = last_activity(process)
    if moved != process.get("last_move") or session.status != "busy":
        process["last_move"] = moved
        process["stall_reported"] = False
    if (initialized and session.status == "busy" and not process.get("stall_reported")
            and moved is not None and now - moved >= settings.stall_minutes * 60):
        details = "busy"
        if process.get("last_tool"):
            details += f", ultimo tool {process['last_tool']}"
        if session.alive is None:
            details += ", o processo morto"
        emit_session(process, f"{label} 🧊 ferma da {int((now - moved) / 60)} min ({details})", "ferma")
        process["stall_reported"] = True


def describe_status(process, now):
    """`T31 waiting 4 min [loom-deck]` per la riga di armo: lo stato del
    registro e la sua età (`ora − statusUpdatedAt`), dal minuto in su. Un turno
    headless porta la parola `headless` dopo l'etichetta."""
    text = process["label"]
    if process.get("headless"):
        text += " headless"
    if process.get("status"):
        text += f" {process['status']}"
        since = process.get("status_since")
        if since is not None and now - since >= 60:
            text += f" {int((now - since) / 60)} min"
    return text + process.get("where", "")


def short_id(session_id):
    return session_id[:8]


def refresh_label(process):
    """L'etichetta della sessione, a cascata: il sidecar del deck (segue le
    riassegnazioni), la frase dell'hook SessionStart nel transcript, `?`."""
    process["label"] = orchestrator_common.session_label(
        process["session_id"], process.get("sidecar_task"), process.get("transcript_task"))


def announce_label_change(process, old_label):
    """Un evento quando l'etichetta di una sessione già seguita cambia.

    Da `?` a una task è un legame che arriva (la frase dell'hook compare nel
    transcript, o il deck assegna la conversazione); da una task a `?` un
    legame tolto nel deck; fra due task una riassegnazione.
    """
    new_label = process["label"]
    if new_label == old_label:
        return
    session = short_id(process["session_id"])
    # L'evento porta la task vecchia e la nuova: il flusso di un perimetro che
    # ne contiene una vede entrare e uscire la sessione dai suoi membri.
    tasks = {label for label in (old_label, new_label) if not label.startswith("?")}
    session_ids = process_session_ids(process)
    extra = {"sessione": process["session_id"], "headless": bool(process.get("headless"))}
    if old_label.startswith("?"):
        emit_event(f"{new_label} 🏷 sessione {session} legata a {new_label}", tasks, session_ids, "legame", **extra)
    elif new_label.startswith("?"):
        emit_event(f"{new_label} 🔀 sessione {session} staccata da {old_label}", tasks, session_ids, "legame", **extra)
    else:
        emit_event(f"{new_label} 🔀 sessione {session} riassegnata: {old_label} → {new_label}", tasks, session_ids,
                   "legame", **extra)


def new_process(session, transcript, offset):
    return {
        "pid": session.pid,
        "session_id": session.session_id,
        "session_ids": [session.session_id],
        "cwd": session.cwd,
        "transcript": transcript,
        "offset": offset,
        "transcript_task": orchestrator_common.task_of_transcript(transcript),
        "sidecar_task": None,
        "label": "",
        "last_text": "",
        "status": None,
        "headless": session.headless,
    }


def announce_start(process):
    """L'evento di un processo che il monitor vede per la prima volta.

    Un turno headless è un processo che vive un turno solo: la sua nascita è
    l'inizio del turno, e un `--resume` headless della stessa conversazione è un
    processo nuovo, quindi un evento nuovo. Un turno che parte e finisce fra due
    giri del monitor non produce né l'uno né l'altro evento.
    """
    session = short_id(process["session_id"])
    if process.get("headless"):
        emit_session(process, f"{process['label']} ▶ turno headless partito {session}{process['where']}", "avvio")
    else:
        emit_session(process, f"{process['label']} 🆕 nuova sessione {session}{process['where']}", "avvio")


def announce_end(process):
    """L'evento di un processo sparito dal registro. Per un turno headless è
    la fine del turno, con la prima riga dell'ultimo testo: se il turno finisce
    su una domanda lo legge l'orchestrator dal testo, non un riconoscimento a pattern
    qui."""
    session = short_id(process["session_id"])
    if process.get("headless"):
        summary = orchestrator_common.first_meaningful_line(process.get("last_text", ""))
        emit_session(process, f"{process['label']} ⏹ turno headless finito {session}"
                     + (f": {summary[:160]}" if summary else ""), "fine")
    else:
        emit_session(process, f"{process['label']} ✖ sessione chiusa {session}", "fine")


def is_own(session, state, settings):
    """La sessione che lancia il monitor non si segue: riporterebbe i propri
    turni. Il processo si ricorda, così un /clear dell'orchestrator, che cambia il
    suo sessionId, non la fa ricomparire.

    Il processo che risponde a --own-session è anche quello di cui si misura il
    contesto (`own_key`). Gli altri processi della lista sono orchestrator di prima
    sullo stesso file di stato, come quello che ha passato le consegne: non si
    seguono, e non si misurano."""
    if settings.own_session and session.session_id.startswith(settings.own_session):
        state["own_key"] = session.key
        if session.key not in state["own_processes"]:
            state["own_processes"].append(session.key)
        return True
    return session.key in state["own_processes"]


def scan_sessions(state, settings):
    global own_live
    own_live = None
    now = time.time()
    initialized = state.get("initialized")
    since = state.get("last_scan") if initialized else None
    registry = orchestrator_common.read_registry(settings.project_root)
    if not registry.readable:
        emit("monitor ⚠ registro delle sessioni illeggibile: ~/.claude/sessions")
        return
    bindings = orchestrator_common.load_task_bindings(settings.project_root)
    seen = set()
    for session in registry.sessions:
        if is_own(session, state, settings):
            if session.key == state.get("own_key"):
                own_live = {"session_id": session.session_id, "cwd": session.cwd}
            continue
        seen.add(session.key)
        process = state["processes"].get(session.key)
        transcript = orchestrator_common.transcript_path(session.cwd, session.session_id)
        old_label = None
        if process is None:
            process = new_process(session, transcript, start_offset(transcript, since))
            process["sidecar_task"] = bindings.get(session.session_id)
            process["where"] = relative_cwd(session.cwd, settings)
            refresh_label(process)
            state["processes"][session.key] = process
            if initialized:
                announce_start(process)
        elif process["session_id"] != session.session_id:
            process.update(session_id=session.session_id, transcript=transcript,
                           session_ids=process_session_ids(process) + [session.session_id],
                           offset=start_offset(transcript, since),
                           transcript_task=orchestrator_common.task_of_transcript(transcript),
                           sidecar_task=bindings.get(session.session_id))
            refresh_label(process)
            if initialized:
                emit_session(process, f"{process['label']} 🔄 transcript nuovo {short_id(session.session_id)} "
                                      f"(/clear o compattazione)", "clear")
        else:
            old_label = process["label"]
            process["transcript"] = transcript
            process["sidecar_task"] = bindings.get(session.session_id)
            refresh_label(process)
        read_new_records(process)
        if initialized and old_label is not None:
            announce_label_change(process, old_label)
        check_status(process, session, settings, initialized, now)
    for key in list(state["processes"]):
        if key in seen:
            continue
        process = state["processes"][key]
        if process["pid"] in registry.unreadable:
            continue  # entry a metà scrittura: il giro dopo la rilegge
        del state["processes"][key]
        if initialized:
            # I record scritti fra l'ultimo giro e la chiusura (l'ultima
            # risposta prima di un /exit) si leggono ora: dopo non c'è più un
            # processo da cui risalire al transcript.
            read_new_records(process)
            announce_end(process)


def scan_context(state, settings):
    """Il contesto dell'orchestrator, dal suo transcript: un evento `🧠` per gradino
    nuovo. Anche al primo armo, a differenza delle altre fonti: l'orchestrator deve
    sapere subito se è già oltre un gradino."""
    if settings.context_threshold <= 0 or own_live is None:
        return
    transcript = orchestrator_common.transcript_path(own_live["cwd"], own_live["session_id"])
    state["context"], line, step = watch_context.measure(
        state.get("context"), own_live["session_id"], transcript, settings.context_threshold)
    if line:
        emit(line, "contesto", gradino=step, sessione=own_live["session_id"])


def relative_cwd(cwd, settings):
    """` [loom-deck]` per una sessione nata in una sottocartella, niente per
    una nata nella radice."""
    location = orchestrator_common.relative_location(cwd, settings.project_root)
    return f" [{location}]" if location else ""


def split_sections(text):
    sections = {}
    current = "_head"
    lines = []
    for line in text.splitlines():
        if line.startswith("## "):
            sections[current] = "\n".join(lines)
            current = line[3:].strip()
            lines = []
        else:
            lines.append(line)
    sections[current] = "\n".join(lines)
    return sections


def count_checkboxes(section_text):
    marks = [match.group(1) for match in map(CHECKBOX_PATTERN.match, section_text.splitlines()) if match]
    return f"{marks.count('x')}/{len(marks)}"


def summarize_task_file(text):
    sections = split_sections(text)
    deliverables = next((body for name, body in sections.items() if name.startswith("Deliverables")), "")
    acceptance = next((body for name, body in sections.items() if name.startswith("Acceptance")), "")
    progress_match = re.search(r"\*\*Progress\*\*:\s*(.+)", text)
    return {
        "dlv": count_checkboxes(deliverables),
        "ac": count_checkboxes(acceptance),
        "progress": progress_match.group(1).strip() if progress_match else "",
        "has_preflight": "### Preflight" in text,
        "section_hashes": {name: hashlib.sha1(body.encode("utf-8")).hexdigest() for name, body in sections.items()},
    }


def scan_task_files(state, settings):
    for path in glob.glob(os.path.join(settings.docs_path, "tasks", "T*.md")):
        task_id = os.path.basename(path).split("-")[0]
        with open(path, encoding="utf-8", errors="replace") as task_handle:
            summary = summarize_task_file(task_handle.read())
        previous = state["task_files"].get(task_id)
        state["task_files"][task_id] = summary
        if previous is None or not state.get("initialized"):
            continue
        changed_sections = [
            name for name, digest in summary["section_hashes"].items()
            if previous["section_hashes"].get(name) != digest and name != "_head"
        ]
        head_changed = previous["section_hashes"].get("_head") != summary["section_hashes"].get("_head")
        if not changed_sections and not head_changed:
            continue
        deltas = []
        if previous["dlv"] != summary["dlv"]:
            deltas.append(f"DLV {previous['dlv']}→{summary['dlv']}")
        if previous["ac"] != summary["ac"]:
            deltas.append(f"AC {previous['ac']}→{summary['ac']}")
        if previous["progress"] != summary["progress"]:
            deltas.append(f"Prog {summary['progress']}")
        changed_label = ", ".join(changed_sections) if changed_sections else "intestazione"
        emit_event(f"{task_id} 📝 task file: {changed_label}" + (f" · {' · '.join(deltas)}" if deltas else ""),
                   {task_id}, kind="task file")


def overview_progress(text):
    """Le coppie (id, Prog) della tabella Tasks Overview di tasks.md.

    La tabella apre all'header (prima cella `ID`, una colonna `Prog`) e chiude
    alla prima riga che non inizia con `|`: stesso confine di
    `lw_tasks_md_prog_get` in `scripts/utils/lib.sh` e di `overviewRows` nel
    deck. Senza confine le righe cross-deps dell'Execution Plan
    (`| T07 | — | ✔️T08 |`) hanno la stessa forma di una riga task, e la loro
    terza colonna passerebbe per una Prog.
    """
    rows = []
    progress_column = 0
    for line in text.splitlines():
        if not line.lstrip().startswith("|"):
            progress_column = 0
            continue
        cells = [cell.strip() for cell in line.split("|")]
        if len(cells) > 1 and cells[1] == "ID" and "Prog" in cells:
            progress_column = cells.index("Prog")
            continue
        if progress_column and len(cells) > progress_column and re.fullmatch(r"T\d+", cells[1]):
            rows.append((cells[1], cells[progress_column]))
    return rows


def scan_progress_table(state, settings):
    tasks_path = os.path.join(settings.docs_path, "tasks.md")
    if not os.path.exists(tasks_path):
        return
    with open(tasks_path, encoding="utf-8", errors="replace") as tasks_handle:
        rows = overview_progress(tasks_handle.read())
    for task_id, progress in rows:
        previous = state["progress"].get(task_id)
        state["progress"][task_id] = progress
        if previous is not None and previous != progress and state.get("initialized"):
            emit_event(f"{task_id} 📊 tasks.md: Prog {previous} → {progress}", {task_id}, kind="prog")


def run_git(repo_path, *arguments):
    completed = subprocess.run(
        ["git", "--no-optional-locks", "-C", repo_path, *arguments],
        capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30,
    )
    return completed.stdout if completed.returncode == 0 else ""


def scan_git(state, settings):
    for repo_name, repo_path in settings.repos.items():
        refs_output = run_git(repo_path, "for-each-ref", "--format=%(refname) %(objectname)",
                              "refs/heads", "refs/remotes/origin")
        if not refs_output:
            continue
        current_refs = dict(line.split(" ", 1) for line in refs_output.strip().splitlines() if " " in line)
        previous_refs = state["git_refs"].get(repo_name)
        state["git_refs"][repo_name] = current_refs
        if previous_refs is None or not state.get("initialized"):
            continue
        for ref_name, sha in current_refs.items():
            old_sha = previous_refs.get(ref_name)
            if old_sha == sha:
                continue
            short_ref = ref_name.replace("refs/heads/", "").replace("refs/remotes/", "")
            if ref_name.startswith("refs/remotes/"):
                # Un push non ha task: nessun flusso lo tiene.
                emit_event(f"git {repo_name} ⬆ {short_ref} → {sha[:7]}", kind="push")
                continue
            if old_sha:
                log_output = run_git(repo_path, "log", "--format=%h %s", "-n", "5", f"{old_sha}..{sha}")
            else:
                log_output = run_git(repo_path, "log", "--format=%h %s", "-n", "1", sha)
            for commit_line in log_output.strip().splitlines():
                subject = commit_line.partition(" ")[2]
                emit_event(f"git {repo_name} ● {short_ref}: {commit_line[:160]}",
                           commit_tasks(subject, lambda task_id: parent_task(settings, task_id)),
                           kind="commit")


def commit_tasks(subject, parent_of):
    """Le task di un commit, dal suo soggetto.

    L'id dello scope (`run(T23): …`, `orchestrator (T220 DLV5): …`); senza un id nello
    scope, ogni id del soggetto. Il commit di creazione `task(T<n>): create`
    prende anche la task del campo `Parent Task` del file appena nato
    (`parent_of`): è così che la figlia nuova di un'epica arriva al flusso del
    suo perimetro, e la creazione di una task estranea no. Un commit senza id
    non ha task.
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


def parent_task(settings, task_id):
    """La task del campo `Parent Task` del task file di `task_id`, `None` se il
    file o il campo mancano. Il campo può portare una maniglia dopo l'id."""
    path = orchestrator_common.find_task_file(settings.project_root, settings.docs_root, task_id)
    if path is None:
        return None
    try:
        with open(path, encoding="utf-8", errors="replace") as task_handle:
            value = orchestrator_common.header_field(task_handle.read().splitlines(), "Parent Task")
    except OSError:
        return None
    match = re.match(r"(T\d+)\b", value)
    return match.group(1) if match else None


def submodule_paths(project_root):
    """I path dei submodule dichiarati in `.gitmodules`, relativi alla radice.

    Il registro dei submodule è il file, non una lista a mano: un submodule
    aggiunto entra nel monitor senza toccare il comando dell'orchestrator. Stessa
    fonte di `pull-repos`.
    """
    try:
        with open(os.path.join(project_root, ".gitmodules"), encoding="utf-8") as modules_handle:
            text = modules_handle.read()
    except OSError:
        return []
    return [match.strip() for match in re.findall(r"^\s*path\s*=\s*(.+?)\s*$", text, re.M)]


def build_settings(arguments):
    arguments.project_root = os.path.abspath(
        arguments.project_root or orchestrator_common.find_project_root(os.getcwd()))
    arguments.docs_root = orchestrator_common.docs_root(arguments.project_root)
    arguments.docs_path = os.path.join(arguments.project_root, arguments.docs_root)
    repos = {"root": arguments.project_root}
    for relative_path in submodule_paths(arguments.project_root):
        repos[relative_path] = os.path.join(arguments.project_root, relative_path)
    for repo_argument in arguments.repo:
        name, _, relative_path = repo_argument.partition("=")
        repos[name] = os.path.join(arguments.project_root, relative_path)
    arguments.repos = repos
    return arguments


def arm_line(word, state):
    """La riga di armo: ogni sessione seguita con stato ed età."""
    now = time.time()
    sessions = sorted(describe_status(process, now) for process in state["processes"].values())
    return f"monitor ✅ {word}: {', '.join(sessions) or 'nessuna sessione viva'}"


def main():
    orchestrator_common.setup_stdout()
    settings = build_settings(parse_arguments())
    state = load_state(settings.state)
    scanners = (scan_sessions, scan_context, scan_task_files, scan_progress_table, scan_git)
    first_scan = True
    while True:
        scan_started = time.time()
        for scanner in scanners:
            try:
                scanner(state, settings)
            except Exception as error:  # una fonte che si rompe non deve fermare il monitor
                emit(f"monitor ⚠ {scanner.__name__}: {type(error).__name__}: {error}")
        if first_scan:
            word = "riarmato" if state.get("initialized") else "armato"
            state["initialized"] = True
            emit(arm_line(word, state))
            first_scan = False
        state["last_scan"] = scan_started
        save_state(settings.state, state)
        if settings.once:
            return
        time.sleep(settings.poll_seconds)


if __name__ == "__main__":
    main()
