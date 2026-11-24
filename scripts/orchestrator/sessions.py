"""
sessions — legge le altre sessioni Claude Code di un progetto loom-works.

  list   le sessioni vive del progetto, dal registro ~/.claude/sessions/: id,
         task legata, stato e sua età, sottocartella di nascita, primo prompt.
         Un turno headless in corso (`claude -p`) porta `headless` nello stato
  tail   l'ultimo testo di una sessione e i suoi ultimi prompt dell'utente: cosa
         la sessione sta chiedendo, per decidere cosa risponderle. Cerca il
         prefisso fra le vive, poi fra i transcript del progetto: una sessione
         chiusa si rilegge anche dopo il suo ciclo
  orchestrators
         gli altri orchestrator vivi sul progetto, su questa macchina, col perimetro
         che ognuno porta avanti: la guardia al lancio di un orchestrator
  find   le sessioni vive il cui sessionId comincia col prefisso, col sessionId
         intero: l'orchestrator scioglie così l'id che l'utente chiede di escludere
         dal monitor, prima di scriverlo nella blacklist del filtro

Stesse fonti del monitor (watch_sessions.py), lette da orchestrator_common.

Uso:
  python -I sessions.py [--project-root <radice>] list
  python -I sessions.py [--project-root <radice>] tail <prefisso del session id> [--chars 4000] [--prompts 5]
  python -I sessions.py [--project-root <radice>] orchestrators --own-session <session id>
  python -I sessions.py [--project-root <radice>] find <prefisso del session id>
"""

import argparse
import glob
import json
import os
import re
import sys
import time

# Il modulo comune si carica dal path esplicito della cartella dello script:
# con `python -I` la cartella non entra da sola in sys.path. Nessun __pycache__:
# la cartella è la cache del plugin, che non si scrive.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import orchestrator_common  # noqa: E402  (dopo l'aggiunta della cartella a sys.path)


def first_prompt(path):
    try:
        for record in orchestrator_common.read_records(path):
            prompt = orchestrator_common.user_prompt_text(record)
            if prompt is not None:
                return orchestrator_common.describe_prompt(prompt)
    except OSError:
        pass
    return ""


def status_with_age(session, now):
    """`busy 4 min`; un turno headless in corso porta `headless` davanti: un
    processo che lavora senza una tab a cui tornare."""
    text = session.status or "?"
    if session.headless:
        text = f"headless {text}"
    if session.status_since is not None and now - session.status_since >= 60:
        text += f" {int((now - session.status_since) / 60)} min"
    return text


def command_list(project_root):
    now = time.time()
    registry = orchestrator_common.read_registry(project_root)
    if not registry.readable:
        print("registro delle sessioni illeggibile: ~/.claude/sessions")
        sys.exit(1)
    bindings = orchestrator_common.load_task_bindings(project_root)
    sessions = sorted(registry.sessions, key=lambda session: session.status_since or 0, reverse=True)
    for session in sessions:
        path = orchestrator_common.transcript_path(session.cwd, session.session_id)
        label = orchestrator_common.session_label(
            session.session_id, bindings.get(session.session_id), orchestrator_common.task_of_transcript(path))
        location = orchestrator_common.relative_location(session.cwd, project_root)
        where = f"[{location}]  " if location else ""
        unverified = " (pid non verificato)" if session.alive is None else ""
        print(f"{session.session_id[:8]}  {label:7}  {status_with_age(session, now):14}  "
              f"{where}{first_prompt(path)[:100]}{unverified}")
    if not sessions:
        print("nessuna sessione viva nel progetto")


def project_transcript_dirs(project_root):
    """Le cartelle di transcript che possono essere del progetto: quella della
    radice e quelle delle sue sottocartelle, il cui nome codificato comincia
    con quello della radice. La codifica perde informazione (`/` e `-`
    diventano entrambi `-`), quindi il nome dice solo «può essere»: decide il
    `cwd` scritto nei record."""
    projects_dir = os.path.join(orchestrator_common.claude_home(), "projects")
    encoded_root = orchestrator_common.encode_project_dir(project_root)
    if orchestrator_common.IS_WINDOWS:
        encoded_root = encoded_root.lower()
    try:
        names = os.listdir(projects_dir)
    except OSError:
        return []
    directories = []
    for name in names:
        comparable = name.lower() if orchestrator_common.IS_WINDOWS else name
        if comparable == encoded_root or comparable.startswith(encoded_root + "-"):
            directories.append(os.path.join(projects_dir, name))
    return directories


def transcript_cwd(path):
    """Il `cwd` del primo record che lo porta."""
    try:
        for record in orchestrator_common.read_records(path):
            if isinstance(record.get("cwd"), str):
                return record["cwd"]
    except OSError:
        pass
    return None


def find_transcript(project_root, session_prefix):
    """I transcript del progetto il cui sessionId comincia col prefisso: prima
    fra le sessioni vive, poi fra i transcript su disco delle cartelle del
    progetto, tenendo quelli col `cwd` dentro la radice."""
    registry = orchestrator_common.read_registry(project_root)
    live = [session for session in registry.sessions if session.session_id.startswith(session_prefix)]
    if live:
        return [(orchestrator_common.transcript_path(session.cwd, session.session_id), session) for session in live]
    matches = []
    for directory in project_transcript_dirs(project_root):
        for path in glob.glob(os.path.join(glob.escape(directory), glob.escape(session_prefix) + "*.jsonl")):
            cwd = transcript_cwd(path)
            if cwd is None or orchestrator_common.is_within(cwd, project_root):
                matches.append((path, None))
    return matches


def assistant_texts(records):
    for record in records:
        content = (record.get("message") or {}).get("content")
        if record.get("type") == "assistant" and not record.get("isSidechain") and isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text" and block.get("text", "").strip():
                    yield block["text"]


def command_tail(project_root, session_prefix, chars, prompt_count):
    matches = find_transcript(project_root, session_prefix)
    if len(matches) != 1:
        print(f"prefisso {session_prefix}: {len(matches)} transcript trovati, ne serve uno")
        sys.exit(1)
    path, live_session = matches[0]
    records = list(orchestrator_common.read_records(path))
    session_id = os.path.basename(path)[:-len(".jsonl")]
    bindings = orchestrator_common.load_task_bindings(project_root)
    label = orchestrator_common.session_label(session_id, bindings.get(session_id), orchestrator_common.task_of_transcript(path))
    state = f"viva, {status_with_age(live_session, time.time())}" if live_session else "chiusa"
    print(f"=== SESSIONE {session_id} · {label} · {state} ===")
    print("=== ULTIMO TESTO DELLA SESSIONE ===")
    print("\n".join(assistant_texts(records))[-chars:])
    print("=== ULTIMI PROMPT DELL'UTENTE ===")
    prompts = [(record.get("timestamp", ""), orchestrator_common.user_prompt_text(record)) for record in records]
    for timestamp, content in [prompt for prompt in prompts if prompt[1] is not None][-prompt_count:]:
        print(f"{timestamp} {content[:600]}")


# Un orchestrator si riconosce dal suo transcript: l'invocazione della skill — uno
# slash command dell'utente, o una chiamata al tool Skill del modello — col
# perimetro come primo id degli argomenti.
ORCHESTRATOR_SKILL = re.compile(r"(?:^|[/:])orchestrate-mandate$")
TASK_ID = re.compile(r"\bT\d+\b")
# Il passo 2 dello stop dell'orchestrator, e nessun altro passo usa `recap`.
RECAP_COMMAND = re.compile(r"mandate\.py[\"']?\s+(?:--project-root\s+\S+\s+)?recap\b")
COMMAND_NAME = re.compile(r"<command-name>(.*?)</command-name>")
COMMAND_ARGS = re.compile(r"<command-args>(.*?)</command-args>", re.S)


def orchestrator_invocation(prompt):
    """Il perimetro di uno slash command dell'orchestrator scritto in un prompt, o
    `None`. Il comando arriva incartato nei tag `<command-name>`; un turno
    `claude -p` può portarlo nudo, `/loom-works:orchestrate-mandate T214`."""
    name = COMMAND_NAME.search(prompt)
    if name:
        if not ORCHESTRATOR_SKILL.search(name.group(1).strip()):
            return None
        args = COMMAND_ARGS.search(prompt)
        ids = TASK_ID.findall(args.group(1) if args else "")
        return ids[0] if ids else None
    words = prompt.strip().split()
    if words and words[0].startswith("/") and ORCHESTRATOR_SKILL.search(words[0]):
        ids = TASK_ID.findall(" ".join(words[1:]))
        return ids[0] if ids else None
    return None


def orchestrator_of_transcript(path):
    """`(perimetro, ferma)` dell'ultimo orchestrator lanciato nel transcript,
    `(None, False)` se il transcript non ne lancia nessuna.

    Un orchestrator è fermo quando, dopo la sua invocazione, la sessione ha lanciato
    `mandate.py recap`: è il passo 2 dello stop. Una compattazione del
    contesto non cambia transcript, quindi l'invocazione resta leggibile; un
    `/clear` apre un transcript nuovo, e la sessione da lì non è più un orchestrator.

    Il filtro sul testo della riga viene prima del parse: il transcript di un
    orchestrator dura ore, e solo poche righe nominano la skill o lo script.
    """
    head, stopped = None, False
    try:
        with open(path, encoding="utf-8", errors="replace") as transcript_handle:
            for line in transcript_handle:
                if "orchestrate-" not in line and "mandate.py" not in line:
                    continue
                try:
                    record = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(record, dict):
                    continue
                prompt = orchestrator_common.user_prompt_text(record)
                if prompt is not None:
                    perimeter = orchestrator_invocation(prompt)
                    if perimeter:
                        head, stopped = perimeter, False
                    continue
                content = (record.get("message") or {}).get("content")
                if record.get("type") != "assistant" or record.get("isSidechain") or not isinstance(content, list):
                    continue
                for block in content:
                    if not isinstance(block, dict) or block.get("type") != "tool_use":
                        continue
                    tool_input = block.get("input") if isinstance(block.get("input"), dict) else {}
                    if block.get("name") == "Skill" and ORCHESTRATOR_SKILL.search(str(tool_input.get("skill", ""))):
                        ids = TASK_ID.findall(str(tool_input.get("args", "")))
                        if ids:
                            head, stopped = ids[0], False
                    elif block.get("name") == "Bash" and head and RECAP_COMMAND.search(str(tool_input.get("command", ""))):
                        stopped = True
    except OSError:
        return None, False
    return head, stopped


def command_orchestrators(project_root, own_session):
    """Gli altri orchestrator vivi sul progetto, su questa macchina: una riga per
    sessione viva il cui transcript lancia un orchestrator non ancora fermato.

    Il registro delle sessioni vive e i transcript sono locali alla macchina:
    un orchestrator lanciato da un'altra macchina sullo stesso repo qui non c'è.
    """
    registry = orchestrator_common.read_registry(project_root)
    if not registry.readable:
        print("registro delle sessioni illeggibile: ~/.claude/sessions")
        sys.exit(1)
    bindings = orchestrator_common.load_task_bindings(project_root)
    found = 0
    for session in sorted(registry.sessions, key=lambda live: live.session_id):
        if own_session and session.session_id.startswith(own_session):
            continue
        path = orchestrator_common.transcript_path(session.cwd, session.session_id)
        head, stopped = orchestrator_of_transcript(path)
        if head is None or stopped:
            continue
        label = orchestrator_common.session_label(
            session.session_id, bindings.get(session.session_id), orchestrator_common.task_of_transcript(path))
        print(f"ORCHESTRATOR|{session.session_id}|{head}|{label}")
        found += 1
    print(f"ORCHESTRATORS={found}")


def command_find(project_root, session_prefix):
    """Le sessioni vive del progetto il cui sessionId comincia col prefisso:
    una riga `SESSIONE|<sessionId intero>|<etichetta>|<stato>` ciascuna, poi
    `TROVATE=<n>`. Exit 0 con una sola, 1 con nessuna, 2 con più d'una.

    Solo fra le vive, a differenza di `tail`: la blacklist del filtro esclude
    una conversazione aperta, e un id che indica due sessioni non si scrive,
    perché escluderebbe anche quella che l'utente non ha nominato.
    """
    registry = orchestrator_common.read_registry(project_root)
    if not registry.readable:
        print("registro delle sessioni illeggibile: ~/.claude/sessions")
        sys.exit(1)
    bindings = orchestrator_common.load_task_bindings(project_root)
    now = time.time()
    matches = sorted((session for session in registry.sessions if session.session_id.startswith(session_prefix)),
                     key=lambda live: live.session_id)
    for session in matches:
        path = orchestrator_common.transcript_path(session.cwd, session.session_id)
        label = orchestrator_common.session_label(
            session.session_id, bindings.get(session.session_id), orchestrator_common.task_of_transcript(path))
        print(f"SESSIONE|{session.session_id}|{label}|{status_with_age(session, now)}")
    print(f"TROVATE={len(matches)}")
    sys.exit(0 if len(matches) == 1 else 1 if not matches else 2)


def main():
    orchestrator_common.setup_stdout()
    parser = argparse.ArgumentParser(description="Legge le altre sessioni di un progetto loom-works")
    parser.add_argument("--project-root", default="",
                        help="default: la prima cartella sopra la corrente con .claude/loom-works.json")
    subcommands = parser.add_subparsers(dest="command", required=True)
    subcommands.add_parser("list")
    tail_parser = subcommands.add_parser("tail")
    tail_parser.add_argument("session_prefix")
    tail_parser.add_argument("--chars", type=int, default=4000)
    tail_parser.add_argument("--prompts", type=int, default=5)
    orchestrators_parser = subcommands.add_parser("orchestrators")
    orchestrators_parser.add_argument("--own-session", default="", help="session id dell'orchestrator che chiede: fuori dall'elenco")
    find_parser = subcommands.add_parser("find")
    find_parser.add_argument("session_prefix")
    arguments = parser.parse_args()
    project_root = os.path.abspath(arguments.project_root or orchestrator_common.find_project_root(os.getcwd()))
    if arguments.command == "list":
        command_list(project_root)
    elif arguments.command == "orchestrators":
        command_orchestrators(project_root, arguments.own_session)
    elif arguments.command == "find":
        command_find(project_root, arguments.session_prefix)
    else:
        command_tail(project_root, arguments.session_prefix, arguments.chars, arguments.prompts)


if __name__ == "__main__":
    main()
