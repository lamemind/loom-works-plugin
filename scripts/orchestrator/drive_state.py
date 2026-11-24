"""
drive_state — i controlli d'ingresso di `drive-task` e il verdetto sul suo
stato su disco.

`drive-task` è l'orchestrazione di un passo solo: una conversazione lancia un
preflight headless su una task e risponde lei alle sue domande. Prima di aprire
o riprendere il passo, `check` dice in un colpo solo se si può:

  - la task: file, Prog, Size, preflight, e le dipendenze ancora aperte (un
    avviso, mai un rifiuto: il passo lo chiede l'utente, per nome);
  - il deck: `loom-deck-headless` sul PATH, in una versione che conosce
    `--context`, l'opzione con cui il contesto della conversazione entra nelle
    Note utente del passo;
  - il permission mode del progetto: `auto`, perché il passo headless non ha
    nessuno che approva, e il preflight deve scrivere il task file e committare;
  - lo stato su disco: `.claude/loom/drive/T<id>.md`, ignorato da git, e chi lo
    tiene;
  - le conversazioni vive sulla task, oltre a quella che chiede e al passo
    stesso: due conversazioni sulla stessa task lavorano sugli stessi file;
  - gli orchestrator: i turni headless aperti da un orchestrator su questa task, finché
    l'orchestrator non è fermo, e gli orchestrator vivi, che la skill confronta coi membri del
    loro perimetro col lettore unico (`resolve-task.sh --members`).

La testa dello stato, le prime righe prima del primo heading, le scrive la
skill col tool `Write`:

  Stato: aperto · <sessionId>     il passo è aperto, e la conversazione che lo
                                  tiene: lei sola ci risponde
  Stato: lasciato · <sessionId>   il titolare ha lasciato il passo su richiesta
                                  dell'utente: chi rilancia lo riprende
  Stato: chiuso · <sessionId>     il passo è finito
  Task: T<id> · Created on <data del task file>

Il corpo porta, nella sezione `## Passo`, le righe `- passo: <kind>` e
`- sessionId: <sessionId del passo>`, che `check` rilegge su una ripresa.

Verdetti (riga `STATE=`):

  assente      nessuno stato: passo nuovo                              avanti
  altro        lo stato di una task passata con lo stesso id: passo
               nuovo, la skill lo sovrascrive                          avanti
  chiuso       l'ultimo passo è finito: passo nuovo                    avanti
  mio          `aperto` tenuto da questa conversazione: ripresa di
               tutto, delega compresa                                  avanti
  lasciato     il titolare l'ha lasciato: ripresa, senza la delega     avanti
  morto        `aperto` di una conversazione che non è più viva:
               ripresa, senza la delega                                avanti
  vivo         `aperto` di un'altra conversazione viva                 stop
  illeggibile  il file c'è, la testa no                                stop

Una headless ferma su domande non ha un processo, e `loom-deck-headless reply`
fra due turni non rifiuta nessuno: senza il titolare nello stato una seconda
conversazione risponderebbe allo stesso preflight mentre la prima aspetta
ancora. Lo stesso verdetto che `orchestrator_state.py` applica allo stato dell'orchestrator.

Uso:
  python -I drive_state.py [--project-root <radice>] check <TaskID> [--own-session <session id>]

`--own-session` assente = `CLAUDE_CODE_SESSION_ID`, l'id che Claude Code mette
nell'ambiente della Bash della conversazione.

Exit: 0 avanti (`CHECK=ok`) · 1 id malformato, task file mancante, registro
delle sessioni illeggibile, sessione propria ignota · 2 stop (`CHECK=stop`, una
riga `STOP|<motivo>` per ogni ragione).
"""

import argparse
import glob
import json
import os
import re
import shutil
import sys

# Il modulo comune si carica dal path esplicito della cartella dello script:
# con `python -I` la cartella non entra da sola in sys.path. Nessun __pycache__:
# la cartella è la cache del plugin, che non si scrive.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import mandate  # noqa: E402  (dopo l'aggiunta della cartella a sys.path)
import orchestrator_common  # noqa: E402
import orchestrator_state  # noqa: E402
import sessions  # noqa: E402

TASK_ID_PATTERN = re.compile(r"^T\d+$")
STATE_DIR = os.path.join(".claude", "loom", "drive")
HEADLESS_DIR = os.path.join(".claude", "loom", "headless")

# L'opzione di `loom-deck-headless open` che accoda un testo al prompt del
# passo: senza, il contesto della conversazione non arriva al preflight.
HEADLESS_CONTEXT_FLAG = "--context"

STATE_LINE = re.compile(r"^Stato:\s*(aperto|lasciato|chiuso)\s*·\s*(\S+)\s*$")
IDENTITY_LINE = re.compile(r"^Task:\s*(T\d+)\s*·\s*Created on\s*(.*?)\s*$")
STEP_SESSION_LINE = re.compile(r"^-\s*sessionId:\s*([0-9a-fA-F-]{8,})\s*$")
STEP_KIND_LINE = re.compile(r"^-\s*passo:\s*(\S+)")

NEW_STEP = {"assente", "altro", "chiuso"}
RESUME = {"mio", "lasciato", "morto"}


def state_path(project_root, task_id):
    return os.path.join(project_root, STATE_DIR, f"{task_id}.md")


def read_state(path):
    """`{kind, holder, task, created_on, step_session, step_kind}` dello stato,
    o `None` se manca la riga `Stato:` o la riga `Task:`."""
    found = {}
    in_head = True
    with open(path, encoding="utf-8", errors="replace") as state_handle:
        for raw_line in state_handle:
            line = raw_line.rstrip("\n").strip()
            if line.startswith("#"):
                in_head = False
                continue
            if in_head:
                state_match = STATE_LINE.match(line)
                identity_match = IDENTITY_LINE.match(line)
                if state_match:
                    found["kind"], found["holder"] = state_match.group(1), state_match.group(2)
                elif identity_match:
                    found["task"], found["created_on"] = identity_match.group(1), identity_match.group(2)
                continue
            session_match = STEP_SESSION_LINE.match(line)
            kind_match = STEP_KIND_LINE.match(line)
            if session_match and "step_session" not in found:
                found["step_session"] = session_match.group(1)
            elif kind_match and "step_kind" not in found:
                found["step_kind"] = kind_match.group(1)
    if "kind" not in found or "task" not in found:
        return None
    return found


def verdict_of(state, task_id, created_on, own_session, live_session_ids):
    if state is None:
        return "illeggibile"
    if state["task"] != task_id or state["created_on"] != created_on:
        return "altro"
    if state["kind"] == "chiuso":
        return "chiuso"
    if state["kind"] == "lasciato":
        return "lasciato"
    holder = state["holder"]
    if orchestrator_state.same_session(holder, own_session):
        return "mio"
    if any(orchestrator_state.same_session(holder, session_id) for session_id in live_session_ids):
        return "vivo"
    return "morto"


def task_of_session(project_root, session, bindings):
    """La task di una sessione viva: il sidecar del deck, poi la frase del
    transcript. Stessa precedenza dell'etichetta di `sessions.py list`."""
    path = orchestrator_common.transcript_path(session.cwd, session.session_id)
    return bindings.get(session.session_id) or orchestrator_common.task_of_transcript(path)


def headless_orchestrator_steps(project_root, task_id):
    """`(sessionId, orchestrator)` dei turni headless su questa task aperti da un
    orchestrator: lo stato di `loom-deck-headless` porta il campo `orchestrator` quando il
    turno l'ha dichiarato. Resta su disco sette giorni dopo la fine del turno,
    quindi da solo non distingue un passo fermo su domande da uno chiuso."""
    found = []
    for path in sorted(glob.glob(os.path.join(glob.escape(os.path.join(project_root, HEADLESS_DIR)), "*.json"))):
        if path.endswith(".out.json"):
            continue
        try:
            with open(path, encoding="utf-8") as state_handle:
                state = json.load(state_handle)
        except (OSError, ValueError):
            continue
        if not isinstance(state, dict) or state.get("task") != task_id:
            continue
        orchestrator = state.get("orchestrator")
        if isinstance(orchestrator, str) and TASK_ID_PATTERN.match(orchestrator):
            found.append((str(state.get("sessionId", os.path.basename(path)[:-5])), orchestrator))
    return found


def orchestrator_state_kind(project_root, orchestrator):
    """La parola della riga `Stato:` dello stato dell'orchestrator, `assente` se il
    file non c'è, `illeggibile` se la testa non si legge."""
    path = orchestrator_state.state_paths(project_root, orchestrator)["state"]
    if not os.path.exists(path):
        return "assente"
    head = orchestrator_state.read_head(path)
    return head["kind"] if head else "illeggibile"


def task_lines(project_root, docs, task_id, overview, tasks_md_lines):
    """La riga `TASK|…` e le righe `DEP|…` della task, con le dipendenze ancora
    aperte: quelle di `## Dependencies` e quelle del grafo, lette con le regole
    di `mandate.py tree`."""
    task = mandate.read_task(project_root, docs, task_id, overview)
    if task["file"] is None:
        return None, [], 0
    head = (f"TASK|{task_id}|prog={task['prog']}|size={task['size']}|preflight={task['preflight']}"
            f"|title={task['title']}")
    dependencies = [(dependency, "deps") for dependency in task["deps"] if dependency != task_id]
    for dependent, dependency, source in mandate.graph_edges(tasks_md_lines):
        if dependent == task_id and dependency != task_id:
            dependencies.append((dependency, source))
    closed = mandate.normalize_glyph("✔️")
    lines, seen, open_count = [], set(), 0
    for dependency, source in dependencies:
        if dependency in seen:
            continue
        seen.add(dependency)
        progress = mandate.normalize_glyph(overview.get(dependency, ("?", ""))[0]) or "?"
        if progress != closed:
            open_count += 1
            lines.append(f"DEP|{dependency}|{progress}|{source}")
    return head, lines, open_count


def command_check(project_root, task_id, own_session):
    stops = []
    docs = orchestrator_common.docs_root(project_root)
    try:
        with open(os.path.join(project_root, docs, "tasks.md"), encoding="utf-8", errors="replace") as tasks_handle:
            tasks_md_lines = tasks_handle.read().splitlines()
    except OSError:
        tasks_md_lines = []
    overview = mandate.overview_rows(tasks_md_lines)
    head, dependency_lines, open_dependencies = task_lines(project_root, docs, task_id, overview, tasks_md_lines)
    if head is None:
        print(f"ERROR: task file di {task_id} non trovato", file=sys.stderr)
        return 1
    print(f"PROJECT_ROOT={project_root}")
    print(f"OWN_SESSION={own_session}")
    print(head)
    for line in dependency_lines:
        print(line)
    print(f"DEPS_OPEN={open_dependencies}")

    headless = shutil.which(mandate.HEADLESS_COMMAND)
    print(f"HEADLESS={headless or 'assente'}")
    knows_context = headless is not None and HEADLESS_CONTEXT_FLAG in mandate.command_usage(headless)
    print(f"HEADLESS_CONTEXT={'sì' if knows_context else ('no' if headless else '-')}")
    if headless is None:
        stops.append("loom-deck-headless non è sul PATH")
    elif not knows_context:
        stops.append("loom-deck-headless non conosce --context: il deck installato è più vecchio")
    project_mode = mandate.project_permission_mode(project_root)
    print(f"PROJECT_MODE={project_mode}")
    if project_mode != "auto":
        stops.append(f"permissionMode del progetto {project_mode}: il passo headless non ha nessuno che approva")

    path = state_path(project_root, task_id)
    print(f"STATE_FILE={path}")
    ignored = orchestrator_state.gitignore_state(project_root, path)
    print(f"IGNORED={ignored}")
    if ignored == "no":
        print(f"IGNORE_RULE={orchestrator_state.GITIGNORE_RULE}")
        stops.append("git non ignora .claude/loom/")

    registry = orchestrator_common.read_registry(project_root)
    if not registry.readable:
        print("ERROR: registro delle sessioni illeggibile: ~/.claude/sessions", file=sys.stderr)
        return 1
    live_ids = [session.session_id for session in registry.sessions]
    with open(orchestrator_common.find_task_file(project_root, docs, task_id), encoding="utf-8", errors="replace") as task_handle:
        created_on = orchestrator_common.header_field(task_handle.read().splitlines(), "Created on")
    state = read_state(path) if os.path.exists(path) else None
    verdict = "assente" if not os.path.exists(path) else verdict_of(state, task_id, created_on, own_session, live_ids)
    print(f"CREATED_ON={created_on}")
    print(f"STATE={verdict}")
    step_session = ""
    if state is not None:
        print(f"STATE_HOLDER={state['holder']}")
        if verdict in RESUME and state.get("step_session"):
            step_session = state["step_session"]
            print(f"STEP_SESSION={step_session}")
            print(f"STEP_KIND={state.get('step_kind', '?')}")
    if verdict == "vivo":
        stops.append(f"il passo è tenuto da un'altra conversazione viva: {state['holder']}")
    elif verdict == "illeggibile":
        stops.append(f"stato illeggibile: {path}")

    bindings = orchestrator_common.load_task_bindings(project_root)
    step_live = "no"
    for session in sorted(registry.sessions, key=lambda live: live.session_id):
        if orchestrator_state.same_session(session.session_id, own_session):
            continue
        if task_of_session(project_root, session, bindings) != task_id:
            continue
        form = "headless" if session.headless else "tab"
        if step_session and orchestrator_state.same_session(session.session_id, step_session):
            step_live = form
            continue
        print(f"VIVA|{session.session_id}|{form}|{session.status or '?'}")
        stops.append(f"conversazione viva sulla task: {session.session_id[:8]} ({form})")
    if step_session:
        print(f"STEP_LIVE={step_live}")
        if step_live == "tab":
            stops.append(f"il passo {step_session[:8]} è aperto in una tab: si risponde lì")

    for step_id, orchestrator in headless_orchestrator_steps(project_root, task_id):
        kind = orchestrator_state_kind(project_root, orchestrator)
        if kind == "ferma":
            continue
        print(f"ORCHESTRATOR_PASSO|{step_id}|{orchestrator}|{kind}")
        stops.append(f"l'orchestrator di {orchestrator} ({kind}) ha aperto il passo {step_id[:8]} su {task_id}")

    for session in sorted(registry.sessions, key=lambda live: live.session_id):
        if orchestrator_state.same_session(session.session_id, own_session):
            continue
        perimeter, stopped = sessions.orchestrator_of_transcript(
            orchestrator_common.transcript_path(session.cwd, session.session_id))
        if perimeter is None or stopped:
            continue
        print(f"ORCHESTRATOR|{session.session_id}|{perimeter}|{task_of_session(project_root, session, bindings) or '?'}")

    if verdict in NEW_STEP:
        print("ROUND=nuovo")
    elif verdict in RESUME:
        print("ROUND=ripresa")
    for reason in stops:
        print(f"STOP|{reason}")
    if not stops:
        os.makedirs(os.path.dirname(path), exist_ok=True)
    print(f"CHECK={'stop' if stops else 'ok'}")
    return 2 if stops else 0


def parse_arguments():
    parser = argparse.ArgumentParser(description="I controlli d'ingresso di drive-task")
    parser.add_argument("--project-root", default="",
                        help="default: la prima cartella sopra la corrente con .claude/loom-works.json")
    subcommands = parser.add_subparsers(dest="command", required=True)
    check_parser = subcommands.add_parser("check")
    check_parser.add_argument("task", help="l'id della task del passo")
    check_parser.add_argument("--own-session", default="",
                              help="session id della conversazione che lancia (default: CLAUDE_CODE_SESSION_ID)")
    return parser.parse_args()


def main():
    orchestrator_common.setup_stdout()
    arguments = parse_arguments()
    if not TASK_ID_PATTERN.match(arguments.task):
        print(f"ERROR: id task malformato: '{arguments.task}' (atteso T<numero>)", file=sys.stderr)
        return 1
    own_session = arguments.own_session or os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    if not own_session:
        print("ERROR: sessione propria ignota: --own-session, o CLAUDE_CODE_SESSION_ID nell'ambiente",
              file=sys.stderr)
        return 1
    project_root = os.path.abspath(arguments.project_root) if arguments.project_root \
        else orchestrator_common.find_project_root(os.getcwd())
    return command_check(project_root, arguments.task, own_session)


if __name__ == "__main__":
    sys.exit(main())
