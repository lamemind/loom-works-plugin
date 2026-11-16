"""
watch_sessions — segue le sessioni Claude Code vive di un progetto loom-works.

Ogni riga su stdout è un evento per il tool Monitor di Claude Code:
  - dai transcript delle altre sessioni: turno finito, domanda all'utente,
    skill lanciata, prompt dell'utente, sessione nuova
  - dai task file: sezione cambiata, cifre di DLV e AC, campo Progress
  - da tasks.md: colonna Prog della tabella Tasks Overview
  - da git: commit locali nuovi e push su origin, per ogni repo guardato

Lo stato sta in un file JSON (--state): un monitor riarmato con lo stesso file
non ripete gli eventi già detti e non perde quelli capitati nel cambio. Il primo
giro registra lo stato attuale e non emette niente sul passato.

Uso (lo lancia la skill della regia, dalla cache del plugin):
  python -u -I watch_sessions.py --project-root <radice del progetto> \\
      --own-session <id della sessione che lancia il monitor> \\
      --state <scratchpad>/watch_state.json \\
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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import regia_common  # noqa: E402  (dopo l'aggiunta della cartella a sys.path)

TASK_ID_PATTERN = re.compile(r"LOOM_TASK=(T\d+)")
CHECKBOX_PATTERN = re.compile(r"^- \[([ x])\]")


def parse_arguments():
    parser = argparse.ArgumentParser(description="Segue le sessioni vive di un progetto loom-works")
    parser.add_argument("--project-root", default="",
                        help="default: la prima cartella sopra la corrente con .claude/loom-works.json")
    parser.add_argument("--own-session", default="", help="session id da saltare: quello che lancia il monitor")
    parser.add_argument("--state", required=True, help="file JSON di stato; tenerlo fuori dal repo")
    parser.add_argument("--transcript-dir", default="", help="default: ~/.claude/projects/<radice codificata>")
    parser.add_argument("--repo", action="append", default=[],
                        help="nome=path relativo alla radice; ripetibile")
    parser.add_argument("--poll-seconds", type=int, default=15)
    parser.add_argument("--live-window-minutes", type=int, default=20,
                        help="un transcript fermo da più tempo resta fuori finché non si muove")
    parser.add_argument("--once", action="store_true",
                        help="un giro solo: legge, salva lo stato ed esce")
    return parser.parse_args()


def default_transcript_dir(project_root):
    encoded = re.sub(r"[^A-Za-z0-9]", "-", project_root)
    return os.path.join(os.path.expanduser("~"), ".claude", "projects", encoded)


def emit(line):
    print(line.replace("\n", " ")[:300], flush=True)


def load_state(state_path):
    if os.path.exists(state_path):
        with open(state_path, encoding="utf-8") as state_handle:
            return json.load(state_handle)
    return {"transcripts": {}, "task_files": {}, "progress": {}, "git_refs": {}}


def save_state(state_path, state):
    temporary_path = state_path + ".tmp"
    with open(temporary_path, "w", encoding="utf-8") as state_handle:
        json.dump(state, state_handle)
    os.replace(temporary_path, state_path)


def first_meaningful_line(text):
    for raw_line in text.splitlines():
        cleaned = raw_line.strip().lstrip("#").strip().strip("*").strip()
        if cleaned:
            return cleaned
    return ""


def task_id_of_transcript(path):
    with open(path, encoding="utf-8", errors="replace") as transcript_handle:
        for index, line in enumerate(transcript_handle):
            match = TASK_ID_PATTERN.search(line)
            if match:
                return match.group(1)
            if index > 400:
                break
    return "?" + os.path.basename(path)[:6]


def describe_user_prompt(content):
    command_match = re.search(r"<command-name>(.*?)</command-name>", content)
    if command_match:
        args_match = re.search(r"<command-args>(.*?)</command-args>", content, re.S)
        args = args_match.group(1).strip() if args_match else ""
        return f"{command_match.group(1)} {args}".strip()
    return first_meaningful_line(content)


def handle_transcript_record(record, session, label):
    record_type = record.get("type")
    if record_type == "system" and record.get("subtype") == "turn_duration":
        summary = first_meaningful_line(session.get("last_text", ""))
        emit(f"{label} ⏸ turno finito, aspetta l'utente: {summary[:160]}")
        return
    message = record.get("message") or {}
    content = message.get("content")
    if record_type == "user" and isinstance(content, str):
        if "<system-reminder>" in content[:40] or "<local-command" in content:
            return
        emit(f"{label} ✍ prompt utente: {describe_user_prompt(content)[:140]}")
        return
    if record_type != "assistant" or not isinstance(content, list):
        return
    for block in content:
        block_type = block.get("type")
        if block_type == "text" and block.get("text", "").strip():
            session["last_text"] = block["text"]
        elif block_type == "tool_use":
            tool_name = block.get("name")
            tool_input = block.get("input") or {}
            if tool_name == "Skill":
                emit(f"{label} ▶ skill {tool_input.get('skill')} {str(tool_input.get('args') or '')[:80]}")
            elif tool_name == "AskUserQuestion":
                questions = tool_input.get("questions") or [{}]
                emit(f"{label} ❓ domanda all'utente: {questions[0].get('question', '')[:160]}")


def scan_transcripts(state, settings):
    now = time.time()
    for path in glob.glob(os.path.join(settings.transcript_dir, "*.jsonl")):
        session_id = os.path.basename(path)[:-6]
        if session_id == settings.own_session:
            continue
        size = os.path.getsize(path)
        session = state["transcripts"].get(session_id)
        if session is None:
            if now - os.path.getmtime(path) > settings.live_window_minutes * 60:
                continue
            label = task_id_of_transcript(path)
            session = {"offset": size, "label": label, "last_text": ""}
            state["transcripts"][session_id] = session
            if state.get("initialized"):
                emit(f"{label} 🆕 nuova sessione {session_id[:8]}")
            continue
        if size <= session["offset"]:
            continue
        with open(path, "rb") as transcript_handle:
            transcript_handle.seek(session["offset"])
            chunk = transcript_handle.read(size - session["offset"])
        last_newline = chunk.rfind(b"\n")
        if last_newline < 0:
            continue
        session["offset"] += last_newline + 1
        for raw_line in chunk[: last_newline + 1].splitlines():
            decoded_line = raw_line.decode("utf-8", errors="replace")
            try:
                record = json.loads(decoded_line)
            except json.JSONDecodeError:
                continue
            if session["label"].startswith("?"):
                match = TASK_ID_PATTERN.search(decoded_line)
                if match:
                    session["label"] = match.group(1)
            handle_transcript_record(record, session, session["label"])


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
        emit(f"{task_id} 📝 task file: {changed_label}" + (f" · {' · '.join(deltas)}" if deltas else ""))


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
            emit(f"{task_id} 📊 tasks.md: Prog {previous} → {progress}")


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
                emit(f"git {repo_name} ⬆ {short_ref} → {sha[:7]}")
                continue
            if old_sha:
                log_output = run_git(repo_path, "log", "--format=%h %s", "-n", "5", f"{old_sha}..{sha}")
            else:
                log_output = run_git(repo_path, "log", "--format=%h %s", "-n", "1", sha)
            for commit_line in log_output.strip().splitlines():
                emit(f"git {repo_name} ● {short_ref}: {commit_line[:160]}")


def build_settings(arguments):
    arguments.project_root = os.path.abspath(
        arguments.project_root or regia_common.find_project_root(os.getcwd()))
    arguments.docs_path = os.path.join(arguments.project_root, regia_common.docs_root(arguments.project_root))
    arguments.transcript_dir = arguments.transcript_dir or default_transcript_dir(arguments.project_root)
    repos = {"root": arguments.project_root}
    for repo_argument in arguments.repo:
        name, _, relative_path = repo_argument.partition("=")
        repos[name] = os.path.join(arguments.project_root, relative_path)
    arguments.repos = repos
    return arguments


def main():
    regia_common.setup_stdout()
    settings = build_settings(parse_arguments())
    if not os.path.isdir(settings.transcript_dir):
        emit(f"monitor ⚠ cartella dei transcript assente: {settings.transcript_dir}")
        sys.exit(1)
    state = load_state(settings.state)
    scanners = (scan_transcripts, scan_task_files, scan_progress_table, scan_git)
    while True:
        for scanner in scanners:
            try:
                scanner(state, settings)
            except Exception as error:  # una fonte che si rompe non deve fermare il monitor
                emit(f"monitor ⚠ {scanner.__name__}: {type(error).__name__}: {error}")
        if not state.get("initialized"):
            state["initialized"] = True
            labels = sorted(session["label"] for session in state["transcripts"].values())
            emit(f"monitor ✅ armato: {', '.join(labels) or 'nessuna sessione viva'}")
        save_state(settings.state, state)
        if settings.once:
            return
        time.sleep(settings.poll_seconds)


if __name__ == "__main__":
    main()
