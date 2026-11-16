"""
sessions — legge le altre sessioni Claude Code di un progetto loom-works.

  list   le sessioni vive del progetto, dal registro ~/.claude/sessions/: id,
         task legata, stato e sua età, sottocartella di nascita, primo prompt
  tail   l'ultimo testo di una sessione e i suoi ultimi prompt dell'utente: cosa
         la sessione sta chiedendo, per decidere cosa risponderle. Cerca il
         prefisso fra le vive, poi fra i transcript del progetto: una sessione
         chiusa si rilegge anche dopo il suo ciclo

Stesse fonti del monitor (watch_sessions.py), lette da regia_common.

Uso:
  python -I sessions.py [--project-root <radice>] list
  python -I sessions.py [--project-root <radice>] tail <prefisso del session id> [--chars 4000] [--prompts 5]
"""

import argparse
import glob
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import regia_common  # noqa: E402  (dopo l'aggiunta della cartella a sys.path)


def first_prompt(path):
    try:
        for record in regia_common.read_records(path):
            prompt = regia_common.user_prompt_text(record)
            if prompt is not None:
                return regia_common.describe_prompt(prompt)
    except OSError:
        pass
    return ""


def status_with_age(session, now):
    text = session.status or "?"
    if session.status_since is not None and now - session.status_since >= 60:
        text += f" {int((now - session.status_since) / 60)} min"
    return text


def command_list(project_root):
    now = time.time()
    registry = regia_common.read_registry(project_root)
    if not registry.readable:
        print("registro delle sessioni illeggibile: ~/.claude/sessions")
        sys.exit(1)
    bindings = regia_common.load_task_bindings(project_root)
    sessions = sorted(registry.sessions, key=lambda session: session.status_since or 0, reverse=True)
    for session in sessions:
        path = regia_common.transcript_path(session.cwd, session.session_id)
        label = regia_common.session_label(
            session.session_id, bindings.get(session.session_id), regia_common.task_of_transcript(path))
        where = ""
        if regia_common.comparable_path(session.cwd) != regia_common.comparable_path(project_root):
            where = f"[{os.path.relpath(session.cwd, project_root)}]  "
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
    projects_dir = os.path.join(regia_common.claude_home(), "projects")
    encoded_root = regia_common.encode_project_dir(project_root)
    if regia_common.IS_WINDOWS:
        encoded_root = encoded_root.lower()
    try:
        names = os.listdir(projects_dir)
    except OSError:
        return []
    directories = []
    for name in names:
        comparable = name.lower() if regia_common.IS_WINDOWS else name
        if comparable == encoded_root or comparable.startswith(encoded_root + "-"):
            directories.append(os.path.join(projects_dir, name))
    return directories


def transcript_cwd(path):
    """Il `cwd` del primo record che lo porta."""
    try:
        for record in regia_common.read_records(path):
            if isinstance(record.get("cwd"), str):
                return record["cwd"]
    except OSError:
        pass
    return None


def find_transcript(project_root, session_prefix):
    """I transcript del progetto il cui sessionId comincia col prefisso: prima
    fra le sessioni vive, poi fra i transcript su disco delle cartelle del
    progetto, tenendo quelli col `cwd` dentro la radice."""
    registry = regia_common.read_registry(project_root)
    live = [session for session in registry.sessions if session.session_id.startswith(session_prefix)]
    if live:
        return [(regia_common.transcript_path(session.cwd, session.session_id), session) for session in live]
    matches = []
    for directory in project_transcript_dirs(project_root):
        for path in glob.glob(os.path.join(glob.escape(directory), glob.escape(session_prefix) + "*.jsonl")):
            cwd = transcript_cwd(path)
            if cwd is None or regia_common.is_within(cwd, project_root):
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
    records = list(regia_common.read_records(path))
    session_id = os.path.basename(path)[:-len(".jsonl")]
    bindings = regia_common.load_task_bindings(project_root)
    label = regia_common.session_label(session_id, bindings.get(session_id), regia_common.task_of_transcript(path))
    state = f"viva, {status_with_age(live_session, time.time())}" if live_session else "chiusa"
    print(f"=== SESSIONE {session_id} · {label} · {state} ===")
    print("=== ULTIMO TESTO DELLA SESSIONE ===")
    print("\n".join(assistant_texts(records))[-chars:])
    print("=== ULTIMI PROMPT DELL'UTENTE ===")
    prompts = [(record.get("timestamp", ""), regia_common.user_prompt_text(record)) for record in records]
    for timestamp, content in [prompt for prompt in prompts if prompt[1] is not None][-prompt_count:]:
        print(f"{timestamp} {content[:600]}")


def main():
    regia_common.setup_stdout()
    parser = argparse.ArgumentParser(description="Legge le altre sessioni di un progetto loom-works")
    parser.add_argument("--project-root", default="",
                        help="default: la prima cartella sopra la corrente con .claude/loom-works.json")
    subcommands = parser.add_subparsers(dest="command", required=True)
    subcommands.add_parser("list")
    tail_parser = subcommands.add_parser("tail")
    tail_parser.add_argument("session_prefix")
    tail_parser.add_argument("--chars", type=int, default=4000)
    tail_parser.add_argument("--prompts", type=int, default=5)
    arguments = parser.parse_args()
    project_root = os.path.abspath(arguments.project_root or regia_common.find_project_root(os.getcwd()))
    if arguments.command == "list":
        command_list(project_root)
    else:
        command_tail(project_root, arguments.session_prefix, arguments.chars, arguments.prompts)


if __name__ == "__main__":
    main()
